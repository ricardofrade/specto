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
    private var regionHeading: String
    /// YouTube's lists are per country; PeerTube's aren't.
    public var choosesRegion: Bool { category != .peerTube && !onlyPeerTube }
    /// The person's pick; nil follows the device's region.
    public private(set) var region: String?
    /// Every country with a list, by name in the person's language.
    public let regions: [Region]
    /// "Automatic (Portugal)": what nil means here.
    public let automaticTitle: String
    /// Only PeerTube servers added: their lists aren't regional.
    public private(set) var onlyPeerTube = false
    /// The lists the instances offer: just `.all`, or Gaming too (Invidious).
    public private(set) var categories: [TrendingCategory] = [.all]
    public private(set) var category = TrendingCategory.all

    @ObservationIgnored private let store: TrendingStore
    @ObservationIgnored private let refresher: @Sendable (TrendingCategory) async throws -> Void
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var lastRefresh: [TrendingCategory: Date] = [:]
    @ObservationIgnored private let deviceRegion: String?
    @ObservationIgnored private let regionChanged: (String?) -> Void

    public struct Region: Identifiable, Hashable, Sendable {
        public let code: String
        public let name: String
        public var id: String { code }
    }

    /// - Parameters:
    ///   - region: the person's pick of country, nil for the device's.
    ///   - deviceRegion: the device's region code, which nil stands for.
    ///   - regionChanged: saves a new pick; Explore then refetches its lists.
    ///   - refresh: fetches a category's list and saves it to `store`.
    public init(store: TrendingStore, region: String?, deviceRegion: String?,
                regionChanged: @escaping (String?) -> Void = { _ in },
                refresh: @escaping @Sendable (TrendingCategory) async throws -> Void) {
        self.store = store
        self.refresher = refresh
        self.region = region
        self.deviceRegion = deviceRegion
        self.regionChanged = regionChanged
        regions = TrendingRegions.youTube
            .map { Region(code: $0, name: Self.name(of: $0)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        automaticTitle = deviceRegion.map { String(localized: "Automatic (\(Self.name(of: $0)))") }
            ?? String(localized: "Automatic")
        regionHeading = Self.heading(for: region ?? deviceRegion)
        apply((try? store.rows()) ?? [])
    }

    /// Switch country: every list is refetched for it, the shown one at once.
    public func selectRegion(_ code: String?) {
        guard code != region else { return }
        region = code
        regionHeading = Self.heading(for: code ?? deviceRegion)
        regionChanged(code)
        Task { await reload() }
    }

    /// Every list is out of date (country or filters changed): fetch the shown one now, the
    /// others when next shown.
    public func reload() async {
        lastRefresh = [:]
        await refresh(force: true)
    }

    private static func name(of code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    private static func heading(for code: String?) -> String {
        code.map { String(localized: "Trending in \(name(of: $0))") } ?? String(localized: "Trending")
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
