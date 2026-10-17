import SwiftUI
import ChannelFeature
import DesignSystem

/// A channel's uploads, cached ones first, with a Subscribe button above them.
struct TVChannelView: View {
    @State private var model: ChannelModel
    let actions: VideoActions

    init(model: ChannelModel, actions: VideoActions) {
        _model = State(initialValue: model)
        self.actions = actions
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVMetrics.sectionSpacing) {
                HStack(spacing: TVMetrics.gridSpacing) {
                    RemoteImage(model.avatarURL, pointSize: CGSize(width: 120, height: 120))
                        .frame(width: 120, height: 120)
                        .clipShape(.circle)
                    Text(model.name).font(.title2.weight(.semibold))
                    Spacer()
                    Button { Task { await model.toggleSubscription() } } label: {
                        Text(model.isSubscribed ? "Subscribed" : "Subscribe")
                    }
                }
                if let error = model.error {
                    Text(error).foregroundStyle(Tokens.Colors.textSecondary)
                }
                if !model.playlists.isEmpty {
                    VStack(alignment: .leading, spacing: TVMetrics.gridSpacing) {
                        Text("Playlists").font(.title3.weight(.semibold))
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: TVMetrics.gridSpacing) {
                                ForEach(model.playlists) { row in
                                    PlaylistCard(row: row, open: actions.openPlaylist)
                                        .frame(width: TVMetrics.cardWidth)
                                        .task { await model.loadPlaylistsIfNeeded(after: row.id) }
                                }
                            }
                            .padding(.vertical, TVMetrics.gridSpacing)
                        }
                        .scrollClipDisabled()
                    }
                    .focusSection()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: TVMetrics.cardWidth), spacing: TVMetrics.gridSpacing,
                                             alignment: .top)],
                          spacing: TVMetrics.rowSpacing) {
                    ForEach(model.rows) { row in
                        VideoCard(row: row, actions: actions)
                            .task { await model.loadMoreIfNeeded(after: row.id) }
                    }
                }
            }
        }
        .task {
            await model.loadFirstPage()
            await model.loadPlaylistsIfNeeded()
        }
    }
}
