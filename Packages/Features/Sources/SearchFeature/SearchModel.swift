import Foundation
import Observation
import Core
import Library
import DesignSystem

/// Search: videos, channels or playlists; suggestions while typing (from the instance, debounced);
/// and this device's recent searches.
@Observable
public final class SearchModel {
    public enum Phase: Equatable {
        case idle
        case loading
        case results
        case empty
        case failed(String)
    }

    /// A result, ready to draw.
    public enum Row: Identifiable, Hashable {
        case video(FeedRow)
        case channel(ChannelSummary, avatar: VideoCellContent.Avatar)
        case playlist(PlaylistRow)

        public var id: String {
            switch self {
            case .video(let row): "video/\(row.id.rawValue)"
            case .channel(let channel, _): "channel/\(channel.id.rawValue)"
            case .playlist(let row): "playlist/\(row.id.rawValue)"
            }
        }
    }

    public var query = "" {
        didSet {
            guard query != oldValue else { return }
            if query.isEmpty { reset() }
            scheduleSuggestions()
            if searchesAsYouType { scheduleLiveSearch() }
        }
    }
    /// Changing it searches the submitted query again.
    public var filter = SearchFilter.videos {
        didSet {
            guard filter != oldValue, !submitted.isEmpty else { return }
            Task { await run(submitted) }
        }
    }
    /// With YouTube and PeerTube both set up, the two to choose between (the switch above the
    /// results); empty otherwise, and every search goes where it can.
    public var networks: [ContentNetwork] = [] {
        didSet {
            guard networks != oldValue else { return }
            if !networks.isEmpty, !networks.contains(network) { network = networks[0] }
        }
    }
    /// Changing it searches the submitted query again.
    public var network = ContentNetwork.youTube {
        didSet {
            guard network != oldValue else { return }
            networkChanged(network)
            guard !submitted.isEmpty else { return }
            Task { await run(submitted) }
        }
    }
    public private(set) var rows: [Row] = []
    public private(set) var phase = Phase.idle
    public private(set) var isLoadingMore = false
    public private(set) var suggestions: [String] = []
    public private(set) var recent: [String] = []
    /// Before typing: the person's channels, A to Z, to jump to one.
    public private(set) var channels: [IdleChannel] = []
    /// Before typing: the top of Explore's trending list.
    public private(set) var trending: [FeedRow] = []

    /// A subscribed channel on the starting screen.
    public struct IdleChannel: Identifiable, Hashable, Sendable {
        public let channel: ChannelSummary
        public let avatar: VideoCellContent.Avatar
        public var id: ChannelID { channel.id }
    }
    /// What the search field offers: recent searches before typing, suggestions after.
    public var completions: [String] { query.isEmpty ? recent : suggestions }

    @ObservationIgnored private let search: @Sendable (String, SearchFilter, ContentNetwork, String?) async throws -> Page<SearchResult>
    @ObservationIgnored private let networkChanged: (ContentNetwork) -> Void
    @ObservationIgnored private let suggest: ((String) async -> [String])?
    @ObservationIgnored private let recentStore: RecentSearchStore?
    /// Apple TV: the inline keyboard has no return key, so typing searches (debounced).
    @ObservationIgnored private let searchesAsYouType: Bool
    @ObservationIgnored private var liveSearch: Task<Void, Never>?
    @ObservationIgnored private var cursor: String?
    @ObservationIgnored private var submitted = ""
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?
    @ObservationIgnored private var recentObservation: Task<Void, Never>?
    @ObservationIgnored private let subscriptions: SubscriptionStore?
    @ObservationIgnored private let trendingStore: TrendingStore?
    @ObservationIgnored private var idleObservations: [Task<Void, Never>] = []

    /// - Parameters:
    ///   - search: (query, filter, network, cursor) → a page of results, through the app's router.
    ///   - network: the network last searched; `networkChanged` remembers a new pick.
    ///   - suggest: completions for a partial query; nil turns suggestions off.
    ///   - recent: where recent searches are kept; nil keeps none.
    ///   - searchesAsYouType: search after typing pauses (Apple TV) rather than on submit.
    ///   - subscriptions, trending: what the starting screen shows before typing (nil: nothing).
    public convenience init(search: @escaping @Sendable (String, SearchFilter, String?) async throws -> Page<SearchResult>,
                            suggest: ((String) async -> [String])? = nil, recent: RecentSearchStore? = nil,
                            searchesAsYouType: Bool = false,
                            subscriptions: SubscriptionStore? = nil, trending: TrendingStore? = nil) {
        self.init(search: { query, filter, _, cursor in try await search(query, filter, cursor) }, suggest: suggest,
                  recent: recent, searchesAsYouType: searchesAsYouType, subscriptions: subscriptions, trending: trending)
    }

    public init(search: @escaping @Sendable (String, SearchFilter, ContentNetwork, String?) async throws -> Page<SearchResult>,
                network: ContentNetwork = .youTube, networkChanged: @escaping (ContentNetwork) -> Void = { _ in },
                suggest: ((String) async -> [String])? = nil, recent: RecentSearchStore? = nil,
                searchesAsYouType: Bool = false,
                subscriptions: SubscriptionStore? = nil, trending: TrendingStore? = nil) {
        self.network = network
        self.networkChanged = networkChanged
        self.subscriptions = subscriptions
        self.trendingStore = trending
        channels = Self.idle((try? subscriptions?.channels()) ?? [])
        self.trending = Array(((try? trending?.rows()) ?? []).prefix(Self.trendingCount))
        self.search = search
        self.suggest = suggest
        self.searchesAsYouType = searchesAsYouType
        recentStore = recent
        self.recent = (try? recent?.all()) ?? []
    }

    /// Observe recent searches. Call from `.task`.
    public func start() async {
        if idleObservations.isEmpty {
            if let changes = subscriptions?.observe() {
                idleObservations.append(Task { [weak self] in
                    do { for try await list in changes { self?.channels = Self.idle(list) } } catch {}
                })
            }
            if let changes = trendingStore?.observe() {
                idleObservations.append(Task { [weak self] in
                    do {
                        for try await rows in changes { self?.trending = Array(rows.prefix(Self.trendingCount)) }
                    } catch {}
                })
            }
        }
        guard recentObservation == nil, let changes = recentStore?.observe() else { return }
        recentObservation = Task { [weak self] in
            do { for try await list in changes { self?.recent = list } } catch {}
        }
    }

    /// Whether the starting screen has anything to show besides the explanation.
    public var hasIdleContent: Bool { !recent.isEmpty || !channels.isEmpty || !trending.isEmpty }

    static let trendingCount = 6

    static func idle(_ list: [ChannelSummary]) -> [IdleChannel] {
        list.map { IdleChannel(channel: $0, avatar: .init(url: $0.avatar?.url, initial: RowFormatter.initial($0.name))) }
    }

    /// Runs on submit (or picking a suggestion or a recent search).
    public func submit() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        suggestionTask?.cancel()
        suggestions = []
        try? recentStore?.record(text)
        await run(text)
    }

    /// A recent search tapped in the list.
    public func search(_ text: String) async {
        query = text
        await submit()
    }

    /// A result was opened: the query that found it is worth keeping (searches as you type
    /// would otherwise fill Recent with fragments).
    public func rememberSearch() {
        guard !submitted.isEmpty else { return }
        try? recentStore?.record(submitted)
    }

    public func removeRecent(_ text: String) {
        try? recentStore?.remove(text)
    }

    public func clearRecent() {
        try? recentStore?.clear()
    }

    public func loadMoreIfNeeded(after id: String) async {
        guard id == rows.last?.id, let cursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let text = submitted, filter = self.filter, network = self.network
        guard let page = try? await search(text, filter, network, cursor),
              text == submitted, filter == self.filter, network == self.network else { return }
        let known = Set(rows.map(\.id))
        rows += Self.format(page.items).filter { !known.contains($0.id) }
        self.cursor = page.nextCursor
    }

    /// A cleared field goes back to the start (recent searches), not the last results.
    private func reset() {
        submitted = ""
        cursor = nil
        rows = []
        phase = .idle
    }

    private func run(_ text: String) async {
        submitted = text
        let filter = self.filter, network = self.network
        phase = .loading
        rows = []
        do {
            let page = try await search(text, filter, network, nil)
            guard text == submitted, filter == self.filter, network == self.network else { return }
            rows = Self.format(page.items)
            cursor = page.nextCursor
            phase = rows.isEmpty ? .empty : .results
        } catch {
            guard text == submitted, filter == self.filter, network == self.network else { return }
            phase = .failed(String(localized: "Search failed. Check your instances and try again."))
        }
    }

    private func scheduleLiveSearch() {
        liveSearch?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, text != submitted else { return }
        liveSearch = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await self?.run(text)
        }
    }

    /// A quarter second after typing stops, so each keystroke doesn't become a request.
    private func scheduleSuggestions() {
        suggestionTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Suggestions come from YouTube; a PeerTube search keeps its words off YouTube.
        guard let suggest, network == .youTube, !text.isEmpty, text != submitted else {
            suggestions = []
            return
        }
        suggestionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = await suggest(text)
            guard !Task.isCancelled, let self, self.query.trimmingCharacters(in: .whitespacesAndNewlines) == text else { return }
            self.suggestions = Array(found.prefix(8))
        }
    }

    static func format(_ results: [SearchResult]) -> [Row] {
        let formatter = RowFormatter()
        return results.map { result in
            switch result {
            case .video(let video):
                .video(formatter.row(video, positionSeconds: nil, durationSeconds: nil))
            case .channel(let channel):
                .channel(channel, avatar: VideoCellContent.Avatar(url: channel.avatar?.url,
                                                                  initial: RowFormatter.initial(channel.name)))
            case .playlist(let playlist):
                .playlist(PlaylistRow(playlist))
            }
        }
    }
}

extension ContentNetwork {
    /// The network's own name, untranslated.
    public var title: String {
        switch self {
        case .youTube: "YouTube"
        case .peerTube: "PeerTube"
        }
    }
}
