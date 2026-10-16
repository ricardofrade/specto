import Foundation
import Observation
import Core
import Library

/// The subscriptions feed: cache first, then the network (stale-while-revalidate).
@Observable
public final class FeedModel {
    public private(set) var rows: [FeedRow]
    public private(set) var isRefreshing = false
    /// Shown above the list when a refresh fails; the cached rows stay visible.
    public private(set) var refreshError: String?

    @ObservationIgnored private let store: FeedStore
    @ObservationIgnored private let refresher: @Sendable (_ force: Bool) async throws -> Void
    @ObservationIgnored private var observation: Task<Void, Never>?

    /// - Parameter refresher: refreshes the cache; `force` false skips a recent refresh.
    public init(store: FeedStore, refresher: @escaping @Sendable (_ force: Bool) async throws -> Void) {
        self.store = store
        self.refresher = refresher
        // First frame from cache: a small synchronous read (indexed, ~30 rows), so launch shows
        // the feed immediately. The observation below then delivers the full list.
        rows = (try? store.rows(.init(limit: 30))) ?? []
    }

    /// Start observing the cache and refresh if stale. Call from `.task`.
    public func start() async {
        if observation == nil {
            observation = Task { [weak self, store] in
                do {
                    for try await rows in store.observe() {
                        self?.rows = rows
                    }
                } catch {
                    self?.refreshError = error.localizedDescription
                }
            }
        }
        await refresh(force: false)
    }

    /// Pull to refresh (force) or foreground/tab return (only if stale).
    public func refresh(force: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await refresher(force)
            refreshError = nil
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
