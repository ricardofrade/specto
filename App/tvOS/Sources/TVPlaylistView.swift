import SwiftUI
import Core
import Library
import PlaylistFeature
import DesignSystem

/// A playlist on Apple TV: Play All and Save above its videos. Any video plays the rest after it.
struct TVPlaylistView: View {
    @State private var model: PlaylistModel
    let actions: VideoActions

    init(model: PlaylistModel, actions: VideoActions) {
        _model = State(initialValue: model)
        self.actions = actions
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVMetrics.sectionSpacing) {
                HStack(alignment: .bottom, spacing: TVMetrics.gridSpacing) {
                    RemoteImage(model.thumbnailURL, pointSize: CGSize(width: 480, height: 270))
                        .frame(width: 480, height: 270)
                        .clipShape(.rect(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
                        Text(model.title).font(.title2.weight(.semibold)).lineLimit(2)
                        if let channel = model.channelName {
                            Text(channel).foregroundStyle(Tokens.Colors.textSecondary)
                        }
                        if let count = model.countText {
                            Text(count).font(.caption).foregroundStyle(Tokens.Colors.textSecondary)
                        }
                        HStack(spacing: TVMetrics.gridSpacing) {
                            Button {
                                Task {
                                    let videos = await model.allVideos()
                                    if !videos.isEmpty { actions.playPlaylist(videos, 0) }
                                }
                            } label: {
                                Label { Text("Play All") } icon: { Image(systemName: "play.fill") }
                            }
                            .disabled(model.rows.isEmpty)
                            Button { model.toggleSaved() } label: {
                                Label { Text(model.isSaved ? "Saved" : "Save") } icon: {
                                    Image(systemName: model.isSaved ? "bookmark.fill" : "bookmark")
                                }
                            }
                        }
                        .padding(.top, Tokens.Spacing.m)
                    }
                }
                .focusSection()
                if let error = model.error, model.rows.isEmpty {
                    Text(error).foregroundStyle(Tokens.Colors.textSecondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: TVMetrics.cardWidth), spacing: TVMetrics.gridSpacing,
                                             alignment: .top)],
                          spacing: TVMetrics.rowSpacing) {
                    ForEach(model.rows) { row in
                        VideoCard(row: row, actions: playingFromHere)
                            .task { await model.loadMoreIfNeeded(after: row.id) }
                    }
                }
            }
        }
        .task { await model.loadFirstPage() }
    }

    /// Selecting a video plays the playlist from there.
    private var playingFromHere: VideoActions {
        var copy = actions
        let rows = model.rows
        copy.play = { video in
            actions.playPlaylist(rows.map(\.video), rows.firstIndex { $0.id == video.id } ?? 0)
        }
        return copy
    }
}

/// A focusable playlist card: thumbnail with the video count, title below.
struct PlaylistCard: View {
    let row: PlaylistRow
    let open: (PlaylistSummary) -> Void
    var remove: (() -> Void)?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            Button { open(row.playlist) } label: {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        RemoteImage(row.playlist.thumbnails.best(forPixelWidth: Int(TVMetrics.cardWidth * displayScale))?.url,
                                    pointSize: CGSize(width: TVMetrics.cardWidth, height: TVMetrics.cardWidth * 9 / 16))
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if let count = row.countText {
                            Label { Text(count) } icon: { Image(systemName: "list.bullet") }
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, Tokens.Spacing.s).padding(.vertical, Tokens.Spacing.xxs)
                                .background(.black.opacity(0.75), in: .rect(cornerRadius: 6))
                                .foregroundStyle(.white)
                                .padding(Tokens.Spacing.s)
                        }
                    }
            }
            .buttonStyle(.card)
            .contextMenu {
                if let remove {
                    Button(role: .destructive, action: remove) {
                        Label { Text("Remove") } icon: { Image(systemName: "trash") }
                    }
                }
            }
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                Text(row.playlist.title).font(.callout.weight(.medium)).lineLimit(2)
                if let channel = row.playlist.channelName {
                    Text(channel).font(.caption).foregroundStyle(Tokens.Colors.textSecondary).lineLimit(1)
                }
            }
        }
    }
}
