import Foundation
import Observation
import Core
import Library
import DesignSystem

/// The subscriptions feed: cache first, then the network (stale-while-revalidate).
@Observable
public final class FeedModel {
    public private(set) var rows: [FeedRow] {
        didSet { indexByID = Self.index(rows) }
    }
    public private(set) var isRefreshing = false
    /// Shown above the list when a refresh fails; the cached rows stay visible.
    public private(set) var refreshError: String?

    @ObservationIgnored private let store: FeedStore
    @ObservationIgnored private var options: FeedStore.Options
    @ObservationIgnored private let refresher: @Sendable (_ force: Bool) async throws -> Void
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var indexByID: [VideoID: Int] = [:]
    @ObservationIgnored private var lastAppeared = 0
    @ObservationIgnored private var warmedManifests = false
    /// Set by the screen: the thumbnail's size in pixels.
    @ObservationIgnored var thumbnailPixelSize = CGSize(width: 1080, height: 608)
    @ObservationIgnored var onWarmManifest: (FeedRow) -> Void = { _ in }

    /// - Parameter refresher: refreshes the cache; `force` false skips a recent refresh.
    public init(store: FeedStore, options: FeedStore.Options = .init(),
                refresher: @escaping @Sendable (_ force: Bool) async throws -> Void) {
        self.store = store
        self.options = options
        self.refresher = refresher
        // First frame from cache: a small synchronous read (indexed, ~30 rows), so launch shows
        // the feed immediately. The observation below then delivers the full list.
        var firstScreen = options
        firstScreen.limit = 30
        rows = (try? store.rows(firstScreen)) ?? []
        indexByID = Self.index(rows)
    }

    private static func index(_ rows: [FeedRow]) -> [VideoID: Int] {
        Dictionary(rows.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Prefetch thumbnails a few rows ahead in the scroll direction, and warm the manifests of
    /// the top rows once per refresh (each manifest costs the instance real work).
    func rowAppeared(_ id: VideoID) {
        guard let index = indexByID[id] else { return }
        let ahead = index >= lastAppeared ? (index + 1)..<min(index + 7, rows.count) : max(index - 6, 0)..<index
        lastAppeared = index
        let width = Int(thumbnailPixelSize.width)
        let urls = rows[ahead].compactMap { $0.thumbnails.best(forPixelWidth: width)?.url }
        let size = thumbnailPixelSize
        Task { await ImagePipeline.shared.prefetch(urls, pixelSize: size) }
        if !warmedManifests, index == 0 {
            warmedManifests = true
            rows.prefix(3).forEach(onWarmManifest)
        }
    }

    /// Settings changed (for example hiding Shorts): re-query the cache.
    public func setOptions(_ options: FeedStore.Options) {
        guard options != self.options else { return }
        self.options = options
        observation?.cancel()
        observation = nil
        observe()
    }

    /// Start observing the cache and refresh if stale. Call from `.task`.
    public func start() async {
        observe()
        await refresh(force: false)
    }

    private func observe() {
        if observation == nil {
            observation = Task { [weak self, store, options] in
                do {
                    for try await rows in store.observe(options) {
                        self?.rows = rows
                    }
                } catch is CancellationError {
                } catch {
                    self?.refreshError = error.localizedDescription
                }
            }
        }
    }

    /// Pull to refresh (force) or foreground/tab return (only if stale).
    public func refresh(force: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await refresher(force)
            refreshError = nil
            warmedManifests = false
        } catch is CancellationError {
        } catch {
            refreshError = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case SourceError.blockedUpstream:
            String(localized: "Your instance is being blocked by YouTube right now. Showing saved videos.")
        case SourceError.unsupported:
            String(localized: "None of your instances can load a subscription feed.")
        case SourceError.network, is URLError:
            String(localized: "Couldn't reach your instance. Showing saved videos.")
        default:
            String(localized: "Couldn't refresh the feed. Showing saved videos.")
        }
    }
}
