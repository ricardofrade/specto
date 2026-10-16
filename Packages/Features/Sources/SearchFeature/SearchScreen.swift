import SwiftUI
import Core
import Library
import DesignSystem

@Observable
public final class SearchModel {
    public enum Phase: Equatable {
        case idle
        case loading
        case results
        case empty
        case failed(String)
    }

    public var query = ""
    public private(set) var rows: [FeedRow] = []
    public private(set) var phase = Phase.idle
    public private(set) var isLoadingMore = false

    @ObservationIgnored private let search: @Sendable (String, String?) async throws -> Page<VideoSummary>
    @ObservationIgnored private var cursor: String?
    @ObservationIgnored private var submitted = ""

    /// - Parameter search: (query, cursor) → a page of results, through the app's router.
    public init(search: @escaping @Sendable (String, String?) async throws -> Page<VideoSummary>) {
        self.search = search
    }

    /// Runs on submit only: nothing is sent while typing.
    public func submit() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        submitted = text
        phase = .loading
        rows = []
        do {
            let page = try await search(text, nil)
            guard text == submitted else { return }
            rows = Self.format(page.items)
            cursor = page.nextCursor
            phase = rows.isEmpty ? .empty : .results
        } catch {
            phase = .failed(String(localized: "Search failed. Check your instances and try again."))
        }
    }

    func loadMoreIfNeeded(after id: VideoID) async {
        guard id == rows.last?.id, let cursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let text = submitted
        guard let page = try? await search(text, cursor), text == submitted else { return }
        let known = Set(rows.map(\.id))
        rows += Self.format(page.items.filter { !known.contains($0.id) })
        self.cursor = page.nextCursor
    }

    static func format(_ videos: [VideoSummary]) -> [FeedRow] {
        let formatter = RowFormatter()
        return videos.map { formatter.row($0, positionSeconds: nil, durationSeconds: nil) }
    }
}

public struct SearchScreen: View {
    @Bindable private var model: SearchModel
    private let onSelect: (VideoSummary) -> Void
    @Environment(\.displayScale) private var displayScale

    public init(model: SearchModel, onSelect: @escaping (VideoSummary) -> Void) {
        self.model = model
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("Search"))
                .searchable(text: $model.query, prompt: Text("Videos"))
                .onSubmit(of: .search) { Task { await model.submit() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            ContentUnavailableView {
                Label { Text("Search your instances") } icon: { Image(systemName: "magnifyingglass") }
            } description: {
                Text("Nothing is sent until you search.")
            }
        case .loading:
            ProgressView()
        case .empty:
            ContentUnavailableView.search(text: model.query)
        case .failed(let message):
            ContentUnavailableView {
                Label { Text("Search failed") } icon: { Image(systemName: "exclamationmark.triangle") }
            } description: {
                Text(message)
            }
        case .results:
            List(model.rows) { row in
                Button { onSelect(row.video) } label: {
                    VideoCell(VideoCellContent(row: row, pixelWidth: Int(160 * displayScale)), style: .row,
                              thumbnailWidth: 160)
                        .equatable()
                }
                .buttonStyle(.plain)
                .task { await model.loadMoreIfNeeded(after: row.id) }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("search.results")
        }
    }
}

extension VideoCellContent {
    init(row: FeedRow, pixelWidth: Int) {
        self.init(title: row.title, channelName: row.channelName, detail: row.detail, durationText: row.durationText,
                  thumbnailURL: row.thumbnails.best(forPixelWidth: pixelWidth)?.url, isLive: row.isLive,
                  progress: row.progress)
    }
}
