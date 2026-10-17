import SwiftUI
import Observation
import Core
import Library
import DesignSystem

/// Saved playlists, newest first, live from the database.
@Observable
public final class SavedPlaylistsModel {
    public private(set) var rows: [PlaylistRow]

    @ObservationIgnored private let store: PlaylistStore
    @ObservationIgnored private var observation: Task<Void, Never>?

    public init(store: PlaylistStore) {
        self.store = store
        rows = ((try? store.all()) ?? []).map(PlaylistRow.init)
    }

    /// Observe the database. Call from `.task`.
    public func start() async {
        guard observation == nil else { return }
        let changes = store.observe()
        observation = Task { [weak self] in
            do { for try await list in changes { self?.rows = list.map(PlaylistRow.init) } } catch {}
        }
    }

    public func remove(_ id: PlaylistID) {
        try? store.remove(id)
    }
}

#if os(iOS)
/// Library → Playlists: tap to open, swipe to remove.
public struct SavedPlaylistsScreen: View {
    @State private var model: SavedPlaylistsModel
    private let onOpen: (PlaylistSummary) -> Void
    @Environment(\.displayScale) private var displayScale

    public init(model: SavedPlaylistsModel, onOpen: @escaping (PlaylistSummary) -> Void) {
        _model = State(initialValue: model)
        self.onOpen = onOpen
    }

    public var body: some View {
        List(model.rows) { row in
            Button { onOpen(row.playlist) } label: {
                VideoCell(VideoCellContent(playlist: row, pixelWidth: Int(140 * displayScale)), style: .row,
                          thumbnailWidth: 140)
                    .equatable()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("playlists.row")
            .swipeActions {
                Button(role: .destructive) { model.remove(row.id) } label: { Text("Remove") }
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.rows.isEmpty {
                ContentUnavailableView {
                    Label { Text("No saved playlists") } icon: { Image(systemName: "list.bullet.rectangle") }
                } description: {
                    Text("Save a playlist from a channel and it shows up here.")
                }
            }
        }
        .navigationTitle(Text("Playlists"))
        .task { await model.start() }
    }
}

extension VideoCellContent {
    init(playlist row: PlaylistRow, pixelWidth: Int) {
        self.init(title: row.playlist.title, channelName: row.playlist.channelName ?? "", detail: "",
                  durationText: row.countText, thumbnailURL: row.playlist.thumbnails.best(forPixelWidth: pixelWidth)?.url,
                  isLive: false, progress: nil, badgeSymbol: "list.bullet")
    }
}
#endif
