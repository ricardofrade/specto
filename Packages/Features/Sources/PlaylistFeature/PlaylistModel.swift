import Foundation
import Observation
import Core
import Library

/// One playlist: its videos page by page, saving it to the Library, and everything for Play All.
@Observable
public final class PlaylistModel {
    public let id: PlaylistID
    public private(set) var title: String
    public private(set) var channelName: String?
    public private(set) var countText: String?
    public private(set) var thumbnailURL: URL?
    public private(set) var rows: [FeedRow] = []
    public private(set) var isSaved: Bool
    public private(set) var isLoading = false
    public private(set) var error: String?

    @ObservationIgnored private var summary: PlaylistSummary
    @ObservationIgnored private let store: PlaylistStore
    @ObservationIgnored private let load: @Sendable (PlaylistID, String?) async throws -> PlaylistPage
    @ObservationIgnored private var cursor: String?
    @ObservationIgnored private var loadedFirstPage = false

    public init(summary: PlaylistSummary, store: PlaylistStore,
                load: @escaping @Sendable (PlaylistID, String?) async throws -> PlaylistPage) {
        id = summary.id
        self.summary = summary
        self.store = store
        self.load = load
        title = summary.title
        channelName = summary.channelName
        thumbnailURL = summary.thumbnails.first?.url
        countText = PlaylistRow(summary).countText
        isSaved = (try? store.isSaved(summary.id)) ?? false
    }

    public func loadFirstPage() async {
        guard !loadedFirstPage else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await load(id, nil)
            loadedFirstPage = true
            apply(page)
            rows = Self.format(page.videos.items)
            cursor = page.videos.nextCursor
            error = nil
        } catch {
            self.error = String(localized: "Couldn't load this playlist.")
        }
    }

    public func loadMoreIfNeeded(after id: VideoID) async {
        guard id == rows.last?.id, cursor != nil, !isLoading else { return }
        await loadNextPage()
    }

    /// Every video, for Play All: the rest of the pages, up to `limit` videos.
    public func allVideos(limit: Int = 500) async -> [VideoSummary] {
        await loadFirstPage()
        while cursor != nil, rows.count < limit {
            let before = rows.count
            await loadNextPage()
            if rows.count == before { break }
        }
        return rows.prefix(limit).map(\.video)
    }

    public func toggleSaved() {
        do {
            if isSaved { try store.remove(id) } else { try store.save(summary) }
            isSaved.toggle()
        } catch {
            self.error = String(localized: "Couldn't update your saved playlists.")
        }
    }

    private func loadNextPage() async {
        guard let cursor else { return }
        isLoading = true
        defer { isLoading = false }
        guard let page = try? await load(id, cursor) else { return }
        let known = Set(rows.map(\.id))
        rows += Self.format(page.videos.items.filter { !known.contains($0.id) })
        self.cursor = page.videos.nextCursor
    }

    /// Later pages carry no title; the first page's details refresh what the list showed.
    private func apply(_ page: PlaylistPage) {
        if !page.title.isEmpty { title = page.title }
        if let name = page.channelName, !name.isEmpty, name != "Playlist" { channelName = name }
        let thumbnails = summary.thumbnails.isEmpty ? Array(page.videos.items.first?.thumbnails.prefix(1) ?? []) : summary.thumbnails
        summary = PlaylistSummary(id: id, title: title, channelName: channelName,
                                  videoCount: page.videoCount ?? summary.videoCount, thumbnails: thumbnails)
        countText = PlaylistRow(summary).countText
        thumbnailURL = thumbnails.first?.url
        if isSaved { try? store.save(summary) }   // Keep the saved copy current.
    }

    static func format(_ videos: [VideoSummary]) -> [FeedRow] {
        let formatter = RowFormatter()
        return videos.map { formatter.row($0, positionSeconds: nil, durationSeconds: nil) }
    }
}
