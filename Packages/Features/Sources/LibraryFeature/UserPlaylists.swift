import SwiftUI
import Observation
import Core
import Library
import DesignSystem

/// One of the person's playlists, ready to draw.
public struct UserPlaylistRow: Identifiable, Hashable, Sendable {
    public let playlist: UserPlaylist
    public let title: String
    public let countText: String
    public let thumbnailURL: URL?
    /// The videos, formatted for cells.
    public let videoRows: [FeedRow]
    public var id: String { playlist.id }

    init(_ playlist: UserPlaylist, formatter: RowFormatter) {
        self.playlist = playlist
        title = playlist.displayTitle
        countText = String(localized: "\(playlist.videos.count) videos")
        thumbnailURL = playlist.videos.first?.thumbnails.best(forPixelWidth: 480)?.url
        videoRows = playlist.videos.map { formatter.row($0, positionSeconds: nil, durationSeconds: nil) }
    }
}

/// Watch Later and the person's playlists, live from the database.
@Observable
public final class UserPlaylistsModel {
    public private(set) var rows: [UserPlaylistRow] {
        didSet { shelfRows = rows.filter { !$0.playlist.isWatchLater || !$0.playlist.videos.isEmpty } }
    }
    /// For shelves: Watch Later once it has something, made playlists always.
    public private(set) var shelfRows: [UserPlaylistRow] = []

    @ObservationIgnored private let store: UserPlaylistStore
    @ObservationIgnored private var observation: Task<Void, Never>?

    public init(store: UserPlaylistStore) {
        self.store = store
        rows = Self.rows((try? store.all()) ?? [])
        shelfRows = rows.filter { !$0.playlist.isWatchLater || !$0.playlist.videos.isEmpty }
    }

    public func row(_ id: String) -> UserPlaylistRow? { rows.first { $0.id == id } }

    private static func rows(_ list: [UserPlaylist]) -> [UserPlaylistRow] {
        let formatter = RowFormatter()
        return list.map { UserPlaylistRow($0, formatter: formatter) }
    }

    /// Observe the database. Call from `.task`.
    public func start() async {
        guard observation == nil else { return }
        let changes = store.observe()
        observation = Task { [weak self] in
            do { for try await list in changes { self?.rows = Self.rows(list) } } catch {}
        }
    }

    @discardableResult
    public func create(_ title: String, with video: VideoSummary? = nil) -> String? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return try? store.create(title: title, with: video).id
    }

    public func delete(_ id: String) { try? store.delete(id) }
    public func rename(_ id: String, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { try? store.rename(id, to: title) }
    }
    public func contains(_ video: VideoID, in id: String) -> Bool {
        rows.first { $0.id == id }?.playlist.contains(video) ?? false
    }
    public func toggle(_ video: VideoSummary, in id: String) {
        if contains(video.id, in: id) { try? store.remove(video.id, from: id) } else { try? store.add(video, to: id) }
    }
    public func remove(_ video: VideoID, from id: String) { try? store.remove(video, from: id) }
    public func move(in id: String, from source: IndexSet, to destination: Int) {
        try? store.move(in: id, from: source, to: destination)
    }
}

#if os(iOS)
/// Library → Playlists: Watch Later and the person's playlists (with New Playlist), then the
/// playlists saved from channels and search.
public struct PlaylistsScreen: View {
    @State private var saved: SavedPlaylistsModel
    @State private var own: UserPlaylistsModel
    private let onOpenSaved: (PlaylistSummary) -> Void
    private let onOpenOwn: (String) -> Void
    @State private var naming = false
    @State private var newTitle = ""
    @Environment(\.displayScale) private var displayScale

    public init(saved: SavedPlaylistsModel, own: UserPlaylistsModel, onOpenSaved: @escaping (PlaylistSummary) -> Void,
                onOpenOwn: @escaping (String) -> Void) {
        _saved = State(initialValue: saved)
        _own = State(initialValue: own)
        self.onOpenSaved = onOpenSaved
        self.onOpenOwn = onOpenOwn
    }

    public var body: some View {
        List {
            Section {
                ForEach(own.rows) { row in
                    Button { onOpenOwn(row.id) } label: { UserPlaylistCell(row: row) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(row.playlist.isWatchLater ? "playlists.watchLater" : "playlists.own")
                        .swipeActions {
                            if !row.playlist.isWatchLater {
                                Button(role: .destructive) { own.delete(row.id) } label: { Text("Delete") }
                            }
                        }
                }
                Button { newTitle = ""; naming = true } label: {
                    Label { Text("New Playlist") } icon: { Image(systemName: "plus") }
                }
                .accessibilityIdentifier("playlists.new")
            } header: {
                Text("Your Playlists")
            }
            if !saved.rows.isEmpty {
                Section {
                    ForEach(saved.rows) { row in
                        Button { onOpenSaved(row.playlist) } label: {
                            VideoCell(VideoCellContent(playlist: row, pixelWidth: Int(140 * displayScale)), style: .row,
                                      thumbnailWidth: 140)
                                .equatable()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("playlists.row")
                        .swipeActions {
                            Button(role: .destructive) { saved.remove(row.id) } label: { Text("Remove") }
                        }
                    }
                } header: {
                    Text("Saved")
                }
            }
        }
        .navigationTitle(Text("Playlists"))
        .alert(Text("New Playlist"), isPresented: $naming) {
            TextField(text: $newTitle) { Text("Name") }
            Button(role: .cancel) {} label: { Text("Cancel") }
            Button { own.create(newTitle) } label: { Text("Create") }
        }
        .task {
            await saved.start()
            await own.start()
        }
    }
}

/// A row of the person's playlists: first video's thumbnail, title, count.
struct UserPlaylistCell: View {
    let row: UserPlaylistRow

    var body: some View {
        HStack(spacing: Tokens.Spacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: Tokens.Radius.thumbnail).fill(Tokens.Colors.accent.opacity(0.15))
                if let url = row.thumbnailURL {
                    RemoteImage(url, pointSize: CGSize(width: 140, height: 79))
                } else {
                    Image(systemName: row.playlist.isWatchLater ? "clock" : "list.bullet")
                        .font(.title2).foregroundStyle(Tokens.Colors.accent)
                }
            }
            .frame(width: 140, height: 79)
            .clipShape(.rect(cornerRadius: Tokens.Radius.thumbnail))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                Text(row.title).font(Tokens.Typography.cellMeta.weight(.semibold)).lineLimit(2)
                Text(row.countText).font(Tokens.Typography.caption).foregroundStyle(Tokens.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// One of the person's playlists: Play All, drag to reorder, swipe to remove; rename or delete.
public struct UserPlaylistScreen: View {
    @State private var model: UserPlaylistsModel
    private let id: String
    private let onPlay: (_ videos: [VideoSummary], _ start: Int) -> Void
    @State private var renaming = false
    @State private var newTitle = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    public init(model: UserPlaylistsModel, id: String, onPlay: @escaping (_ videos: [VideoSummary], _ start: Int) -> Void) {
        _model = State(initialValue: model)
        self.id = id
        self.onPlay = onPlay
    }

    public var body: some View {
        let row = model.row(id)
        let videos = row?.playlist.videos ?? []
        List {
            ForEach(Array((row?.videoRows ?? []).enumerated()), id: \.element.id) { index, video in
                Button { onPlay(videos, index) } label: {
                    VideoCell(VideoCellContent(row: video, pixelWidth: Int(140 * displayScale)), style: .row,
                              thumbnailWidth: 140)
                        .equatable()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("userPlaylist.video")
                .swipeActions {
                    Button(role: .destructive) { model.remove(video.id, from: id) } label: { Text("Remove") }
                }
            }
            .onMove { model.move(in: id, from: $0, to: $1) }
        }
        .listStyle(.plain)
        .overlay {
            if videos.isEmpty {
                ContentUnavailableView {
                    Label { Text("Nothing here yet") } icon: { Image(systemName: "list.bullet") }
                } description: {
                    Text("Save videos here from their menus or the player.")
                }
            }
        }
        .navigationTitle(row?.title ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { onPlay(videos, 0) } label: {
                    Label { Text("Play All") } icon: { Image(systemName: "play.fill") }
                }
                .disabled(videos.isEmpty)
                .accessibilityIdentifier("userPlaylist.playAll")
            }
            if row?.playlist.isWatchLater == false {
                ToolbarItem(placement: .secondaryAction) {
                    Button { newTitle = row?.title ?? ""; renaming = true } label: { Text("Rename") }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button(role: .destructive) { model.delete(id); dismiss() } label: { Text("Delete Playlist") }
                }
            }
        }
        .alert(Text("Rename Playlist"), isPresented: $renaming) {
            TextField(text: $newTitle) { Text("Name") }
            Button(role: .cancel) {} label: { Text("Cancel") }
            Button { model.rename(id, to: newTitle) } label: { Text("Save") }
        }
        .task { await model.start() }
    }
}

/// "Save to Playlist": Watch Later and every playlist with a checkmark where the video is;
/// tap to add or remove; New Playlist creates one with the video in it.
public struct SaveToPlaylistSheet: View {
    @State private var model: UserPlaylistsModel
    private let video: VideoSummary
    @State private var naming = false
    @State private var newTitle = ""
    @Environment(\.dismiss) private var dismiss

    public init(model: UserPlaylistsModel, video: VideoSummary) {
        _model = State(initialValue: model)
        self.video = video
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(model.rows) { row in
                    Button { model.toggle(video, in: row.id) } label: {
                        HStack {
                            UserPlaylistCell(row: row)
                            Image(systemName: row.playlist.contains(video.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(row.playlist.contains(video.id) ? Tokens.Colors.accent : .secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(row.playlist.contains(video.id) ? .isSelected : [])
                    .accessibilityIdentifier("save.playlist")
                }
                Button { newTitle = ""; naming = true } label: {
                    Label { Text("New Playlist") } icon: { Image(systemName: "plus") }
                }
                .accessibilityIdentifier("save.new")
            }
            .navigationTitle(Text("Save to Playlist"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
            .alert(Text("New Playlist"), isPresented: $naming) {
                TextField(text: $newTitle) { Text("Name") }
                Button(role: .cancel) {} label: { Text("Cancel") }
                Button { model.create(newTitle, with: video) } label: { Text("Create") }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await model.start() }
    }
}
#endif
