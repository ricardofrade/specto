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
        }
    }
    /// Changing it searches the submitted query again.
    public var filter = SearchFilter.videos {
        didSet {
            guard filter != oldValue, !submitted.isEmpty else { return }
            Task { await run(submitted) }
        }
    }
    public private(set) var rows: [Row] = []
    public private(set) var phase = Phase.idle
    public private(set) var isLoadingMore = false
    public private(set) var suggestions: [String] = []
    public private(set) var recent: [String] = []
    /// What the search field offers: recent searches before typing, suggestions after.
    public var completions: [String] { query.isEmpty ? recent : suggestions }

    @ObservationIgnored private let search: @Sendable (String, SearchFilter, String?) async throws -> Page<SearchResult>
    @ObservationIgnored private let suggest: ((String) async -> [String])?
    @ObservationIgnored private let recentStore: RecentSearchStore?
    @ObservationIgnored private var cursor: String?
    @ObservationIgnored private var submitted = ""
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?
    @ObservationIgnored private var recentObservation: Task<Void, Never>?

    /// - Parameters:
    ///   - search: (query, filter, cursor) → a page of results, through the app's router.
    ///   - suggest: completions for a partial query; nil turns suggestions off.
    ///   - recent: where recent searches are kept; nil keeps none.
    public init(search: @escaping @Sendable (String, SearchFilter, String?) async throws -> Page<SearchResult>,
                suggest: ((String) async -> [String])? = nil, recent: RecentSearchStore? = nil) {
        self.search = search
        self.suggest = suggest
        recentStore = recent
        self.recent = (try? recent?.all()) ?? []
    }

    /// Observe recent searches. Call from `.task`.
    public func start() async {
        guard recentObservation == nil, let changes = recentStore?.observe() else { return }
        recentObservation = Task { [weak self] in
            do { for try await list in changes { self?.recent = list } } catch {}
        }
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
        let text = submitted, filter = self.filter
        guard let page = try? await search(text, filter, cursor), text == submitted, filter == self.filter else { return }
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
        let filter = self.filter
        phase = .loading
        rows = []
        do {
            let page = try await search(text, filter, nil)
            guard text == submitted, filter == self.filter else { return }
            rows = Self.format(page.items)
            cursor = page.nextCursor
            phase = rows.isEmpty ? .empty : .results
        } catch {
            guard text == submitted, filter == self.filter else { return }
            phase = .failed(String(localized: "Search failed. Check your instances and try again."))
        }
    }

    /// A quarter second after typing stops, so each keystroke doesn't become a request.
    private func scheduleSuggestions() {
        suggestionTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let suggest, !text.isEmpty, text != submitted else {
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
