import SwiftUI
import Core
import Library
import SearchFeature
import DesignSystem

/// The system search keyboard above a results grid. Before typing, recent searches are offered;
/// while typing, the instance's suggestions. Videos, channels or playlists.
struct TVSearchView: View {
    @Bindable var model: SearchModel
    let actions: VideoActions

    var body: some View {
        ScrollView {
            switch model.phase {
            case .idle:
                EmptyView()
            case .loading:
                ProgressView().frame(maxWidth: .infinity)
            case .empty:
                ContentUnavailableView.search(text: model.query)
            case .failed(let message):
                ContentUnavailableView {
                    Label { Text("Search failed") } icon: { Image(systemName: "exclamationmark.triangle") }
                } description: {
                    Text(message)
                }
            case .results:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: TVMetrics.cardWidth), spacing: TVMetrics.gridSpacing,
                                             alignment: .top)],
                          spacing: TVMetrics.rowSpacing) {
                    ForEach(model.rows) { row in
                        result(row)
                            .accessibilityIdentifier("tv.search.result")
                            .task { await model.loadMoreIfNeeded(after: row.id) }
                    }
                }
            }
        }
        .searchable(text: $model.query)
        .searchScopes($model.filter) {
            Text("Videos").tag(SearchFilter.videos)
            Text("Channels").tag(SearchFilter.channels)
            Text("Playlists").tag(SearchFilter.playlists)
        }
        .searchSuggestions {
            ForEach(model.completions, id: \.self) { text in
                Text(verbatim: text).searchCompletion(text)
            }
        }
        .onSubmit(of: .search) { Task { await model.submit() } }
        .task { await model.start() }
    }

    /// Opening a result keeps the search in Recent.
    private var remembering: VideoActions {
        var copy = actions
        let play = actions.play
        copy.play = { video in
            model.rememberSearch()
            play(video)
        }
        return copy
    }

    @ViewBuilder
    private func result(_ row: SearchModel.Row) -> some View {
        switch row {
        case .video(let video):
            VideoCard(row: video, actions: remembering)
        case .channel(let channel, let avatar):
            Button {
                model.rememberSearch()
                actions.openChannel(channel.id, channel.name)
            } label: {
                VStack(spacing: Tokens.Spacing.m) {
                    AvatarView(avatar, size: 160)
                    Text(channel.name).font(.callout.weight(.medium)).lineLimit(1)
                }
                .frame(width: TVMetrics.cardWidth)
                .padding(.vertical, Tokens.Spacing.l)
            }
            .buttonStyle(.borderless)
        case .playlist(let playlist):
            PlaylistCard(row: playlist) { summary in
                model.rememberSearch()
                actions.openPlaylist(summary)
            }
        }
    }
}
