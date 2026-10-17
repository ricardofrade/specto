import Foundation
import Observation
import Core
import Library

/// Explore: what's trending on the instances in the person's region. Cache first (the last
/// list seen), then the network when it's more than an hour old or on pull to refresh.
@Observable
public final class ExploreModel {
    /// Number one, shown large.
    public private(set) var featured: FeedRow?
    /// The rest, in the instance's order.
    public private(set) var rows: [FeedRow] = []
    public private(set) var isRefreshing = false
    /// Shown when a refresh fails; the cached list stays.
    public private(set) var refreshError: String?
    /// "Trending in Portugal" (YouTube's list is regional), or "Trending on PeerTube".
    public var heading: String {
        category == .peerTube || onlyPeerTube ? String(localized: "Trending on PeerTube") : regionHeading
    }
    private let regionHeading: String
    /// Only PeerTube servers added: their lists aren't regional.
    public private(set) var onlyPeerTube = false
    /// The lists the instances offer: just `.all`, or Gaming too (Invidious).
    public private(set) var categories: [TrendingCategory] = [.all]
    public private(set) var category = TrendingCategory.all

    @ObservationIgnored private let store: TrendingStore
    @ObservationIgnored private let refresher: @Sendable (TrendingCategory) async throws -> Void
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var lastRefresh: [TrendingCategory: Date] = [:]

    /// - Parameters:
    ///   - regionName: the person's region, for the heading; nil says just "Trending".
    ///   - refresh: fetches a category's list and saves it to `store`.
    public init(store: TrendingStore, regionName: String?,
                refresh: @escaping @Sendable (TrendingCategory) async throws -> Void) {
        self.store = store
        self.refresher = refresh
        regionHeading = regionName.map { String(localized: "Trending in \($0)") } ?? String(localized: "Trending")
        apply((try? store.rows()) ?? [])
    }

    /// What the instances can list: Gaming (Invidious, or PeerTube alone), and PeerTube's own
    /// list beside YouTube's. Without, Explore shows the general list only.
    public func setCategoriesAvailable(_ gaming: Bool, peerTube: Bool = false, onlyPeerTube: Bool = false) {
        self.onlyPeerTube = onlyPeerTube
        var list: [TrendingCategory] = [.all]
        if gaming { list.append(.gaming) }
        if peerTube { list.append(.peerTube) }
        guard list != categories else { return }
        categories = list
        if !list.contains(category) { select(.all) }
    }

    /// Show a category: its cached list at once, then a refresh if it's stale.
    public func select(_ new: TrendingCategory) {
        guard new != category else { return }
        category = new
        refreshError = nil
        apply((try? store.rows(new)) ?? [])
        observation?.cancel()
        observation = nil
        observe()
        Task { await refresh(force: false) }
    }

    public var isEmpty: Bool { featured == nil }

    /// Observe the cache and refresh it if stale. Call from `.task`.
    public func start() async {
        observe()
        await refresh(force: false)
    }

    private func observe() {
        guard observation == nil else { return }
        let category = self.category
        observation = Task { [weak self, store] in
            do {
                for try await rows in store.observe(category) where self?.category == category { self?.apply(rows) }
            } catch {}
        }
    }

    public func refresh(force: Bool) async {
        guard !isRefreshing else { return }
        let category = self.category
        if !force, !isEmpty, let last = lastRefresh[category], last > .now.addingTimeInterval(-3600) { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            try await refresher(category)
            lastRefresh[category] = .now
            refreshError = nil
        } catch is CancellationError {
        } catch {
            refreshError = FeedModel.message(for: error)
        }
    }

    private func apply(_ list: [FeedRow]) {
        featured = list.first
        rows = Array(list.dropFirst())
    }
}

extension TrendingCategory {
    /// The chip's name.
    public var title: String {
        switch self {
        case .all: String(localized: "All")
        case .gaming: String(localized: "Gaming")
        case .peerTube: String(localized: "PeerTube")
        }
    }

    var symbol: String {
        switch self {
        case .all: "flame.fill"
        case .gaming: "gamecontroller.fill"
        case .peerTube: "play.tv.fill"
        }
    }
}
