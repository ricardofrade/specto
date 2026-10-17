import Foundation
import Observation
import Core
import Library
import DesignSystem

/// The subscriptions feed: cache first, then the network (stale-while-revalidate).
@Observable
public final class FeedModel {
    public private(set) var rows: [FeedRow] {
        didSet {
            indexByID = Self.index(rows)
            (featured, latest) = Self.split(rows)
            sections = FeedSection.group(latest)
        }
    }
    /// The newest video not started yet, shown large at the top of Home.
    public private(set) var featured: FeedRow?
    /// Everything else, newest first.
    public private(set) var latest: [FeedRow] = []
    /// `latest` by when it was published: Today, Yesterday, This Week, Earlier.
    public private(set) var sections: [FeedSection] = []
    /// Started but unfinished, most recent first.
    public private(set) var continueWatching: [FeedRow] = []
    public private(set) var queue: [FeedRow] = []
    /// Shorts get their own shelf and vertical player instead of mixing into the grid; empty
    /// when the person hides them.
    public private(set) var shorts: [FeedRow] = []
    public private(set) var isRefreshing = false
    /// Shown above the list when a refresh fails; the cached rows stay visible.
    public private(set) var refreshError: String?

    @ObservationIgnored private let store: FeedStore
    @ObservationIgnored private var options: FeedStore.Options
    @ObservationIgnored private let refresher: @Sendable (_ force: Bool) async throws -> Void
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var shortsObservation: Task<Void, Never>?
    @ObservationIgnored private var shelfObservations: [Task<Void, Never>] = []
    @ObservationIgnored private let watchState: WatchStateStore?
    @ObservationIgnored private let queueStore: QueueStore?
    @ObservationIgnored private var indexByID: [VideoID: Int] = [:]
    @ObservationIgnored private var lastAppeared = 0
    @ObservationIgnored private var warmedManifests = false
    /// Set by the screen: the thumbnail's size in pixels.
    @ObservationIgnored var thumbnailPixelSize = CGSize(width: 1080, height: 608)
    @ObservationIgnored var onWarmManifest: (FeedRow) -> Void = { _ in }

    /// - Parameters:
    ///   - watchState, queue: sources for the Continue Watching and Queue shelves (nil: none).
    ///   - refresher: refreshes the cache; `force` false skips a recent refresh.
    public init(store: FeedStore, options: FeedStore.Options = .init(),
                watchState: WatchStateStore? = nil, queue: QueueStore? = nil,
                refresher: @escaping @Sendable (_ force: Bool) async throws -> Void) {
        self.store = store
        self.options = options
        self.watchState = watchState
        self.queueStore = queue
        self.refresher = refresher
        // First frame from cache: a small synchronous read (indexed, ~30 rows), so launch shows
        // the feed immediately. The observation below then delivers the full list.
        var firstScreen = options
        firstScreen.limit = 30
        rows = (try? store.rows(Self.videosOnly(firstScreen))) ?? []
        indexByID = Self.index(rows)
        (featured, latest) = Self.split(rows)
        sections = FeedSection.group(latest)
        continueWatching = (try? watchState?.inProgress()) ?? []
        self.queue = (try? queue?.rows()) ?? []
    }

    private static func split(_ rows: [FeedRow]) -> (FeedRow?, [FeedRow]) {
        guard let index = rows.firstIndex(where: { $0.progress == nil && !$0.isLive }) else { return (nil, rows) }
        var rest = rows
        let featured = rest.remove(at: index)
        return (featured, rest)
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
        shortsObservation?.cancel()
        shortsObservation = nil
        if options.hideShorts { shorts = [] }
        observe()
    }

    /// Start observing the cache and refresh if stale. Call from `.task`.
    public func start() async {
        observe()
        observeShelves()
        await refresh(force: false)
    }

    private func observeShelves() {
        guard shelfObservations.isEmpty else { return }
        if let watchState {
            let stream = watchState.observeInProgress()
            shelfObservations.append(Task { [weak self] in
                do { for try await rows in stream { self?.continueWatching = rows } } catch {}
            })
        }
        if let queueStore {
            let stream = queueStore.observe()
            shelfObservations.append(Task { [weak self] in
                do { for try await rows in stream { self?.queue = rows } } catch {}
            })
        }
    }

    /// Shorts never mix into the grid: they have their own shelf and player.
    private static func videosOnly(_ options: FeedStore.Options) -> FeedStore.Options {
        var query = options
        query.hideShorts = true
        return query
    }

    private func observe() {
        if shortsObservation == nil, !options.hideShorts {
            var query = options
            query.onlyShorts = true
            query.limit = 30
            shortsObservation = Task { [weak self, store, query] in
                do { for try await rows in store.observe(query) { self?.shorts = rows } } catch {}
            }
        }
        if observation == nil {
            observation = Task { [weak self, store, options] in
                do {
                    for try await rows in store.observe(Self.videosOnly(options)) {
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

/// A run of feed rows published in the same period, with its title already localized.
nonisolated public struct FeedSection: Identifiable, Sendable, Equatable {
    public enum Period: Int, Sendable { case today, yesterday, thisWeek, earlier }

    public let period: Period
    public let rows: [FeedRow]
    public var id: Period { period }

    public var title: String {
        switch period {
        case .today: String(localized: "Today")
        case .yesterday: String(localized: "Yesterday")
        case .thisWeek: String(localized: "This Week")
        case .earlier: String(localized: "Earlier")
        }
    }

    /// Rows keep their order (newest first); videos without a date go under Earlier.
    static func group(_ rows: [FeedRow], now: Date = .now, calendar: Calendar = .current) -> [FeedSection] {
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)) ?? now
        var buckets: [Period: [FeedRow]] = [:]
        for row in rows {
            let period: Period
            if let date = row.video.publishedAt {
                if calendar.isDateInToday(date) { period = .today }
                else if calendar.isDateInYesterday(date) { period = .yesterday }
                else if date >= weekAgo { period = .thisWeek }
                else { period = .earlier }
            } else {
                period = .earlier
            }
            buckets[period, default: []].append(row)
        }
        return buckets.sorted { $0.key.rawValue < $1.key.rawValue }.map { FeedSection(period: $0.key, rows: $0.value) }
    }
}
