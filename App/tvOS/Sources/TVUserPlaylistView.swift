import SwiftUI
import Core
import Library
import LibraryFeature
import DesignSystem

/// Watch Later or one of the person's playlists on Apple TV: Play All, then its videos in order.
/// Long press a video to remove it.
struct TVUserPlaylistView: View {
    @State private var model: UserPlaylistsModel
    let id: String
    let actions: VideoActions

    init(model: UserPlaylistsModel, id: String, actions: VideoActions) {
        _model = State(initialValue: model)
        self.id = id
        self.actions = actions
    }

    var body: some View {
        let row = model.row(id)
        let videos = row?.playlist.videos ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: TVMetrics.sectionSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: TVMetrics.gridSpacing) {
                    Text(row?.title ?? "").font(.title2.weight(.semibold))
                    Text(row?.countText ?? "").foregroundStyle(Tokens.Colors.textSecondary)
                    Spacer()
                    Button { actions.playPlaylist(videos, 0) } label: {
                        Label { Text("Play All") } icon: { Image(systemName: "play.fill") }
                    }
                    .disabled(videos.isEmpty)
                }
                .focusSection()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: TVMetrics.cardWidth), spacing: TVMetrics.gridSpacing,
                                             alignment: .top)],
                          spacing: TVMetrics.rowSpacing) {
                    ForEach(Array((row?.videoRows ?? []).enumerated()), id: \.element.id) { index, video in
                        VideoCard(row: video,
                                  actions: playingFrom(index, of: videos),
                                  remove: (Text("Remove from Playlist"), { model.remove(video.id, from: id) }))
                    }
                }
            }
        }
        .task { await model.start() }
    }

    private func playingFrom(_ index: Int, of videos: [VideoSummary]) -> VideoActions {
        var copy = actions
        copy.play = { _ in actions.playPlaylist(videos, index) }
        return copy
    }
}

/// A card for one of the person's playlists.
struct UserPlaylistCard: View {
    let row: UserPlaylistRow
    let open: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            Button { open(row.id) } label: {
                ZStack {
                    Tokens.Colors.accent.opacity(0.15)
                    if let url = row.thumbnailURL {
                        RemoteImage(url, pointSize: CGSize(width: TVMetrics.cardWidth, height: TVMetrics.cardWidth * 9 / 16))
                    } else {
                        Image(systemName: row.playlist.isWatchLater ? "clock" : "list.bullet").font(.largeTitle)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
            }
            .buttonStyle(.card)
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                Text(row.title).font(.callout.weight(.medium)).lineLimit(2)
                Text(row.countText).font(.caption).foregroundStyle(Tokens.Colors.textSecondary)
            }
        }
    }
}
