import SwiftUI
import Core
import Library
import DesignSystem

#if os(iOS)
/// iPhone and iPad (Apple TV has its own view on the same model).
public struct SearchScreen: View {
    @Bindable private var model: SearchModel
    private let onSelect: (VideoSummary) -> Void
    private let onOpenChannel: (ChannelSummary) -> Void
    private let onOpenPlaylist: (PlaylistSummary) -> Void
    @Environment(\.displayScale) private var displayScale

    public init(model: SearchModel, onSelect: @escaping (VideoSummary) -> Void,
                onOpenChannel: @escaping (ChannelSummary) -> Void = { _ in },
                onOpenPlaylist: @escaping (PlaylistSummary) -> Void = { _ in }) {
        self.model = model
        self.onSelect = onSelect
        self.onOpenChannel = onOpenChannel
        self.onOpenPlaylist = onOpenPlaylist
    }

    /// Hosted in the app's `NavigationStack`.
    public var body: some View {
        content
            .navigationTitle(Text("Search"))
            .searchable(text: $model.query, prompt: Text("Videos, channels, playlists"))
            .searchScopes($model.filter, activation: .onSearchPresentation) {
                Text("Videos").tag(SearchFilter.videos)
                Text("Channels").tag(SearchFilter.channels)
                Text("Playlists").tag(SearchFilter.playlists)
            }
            .searchSuggestions {
                ForEach(model.suggestions, id: \.self) { suggestion in
                    Label { Text(verbatim: suggestion) } icon: { Image(systemName: "magnifyingglass") }
                        .searchCompletion(suggestion)
                }
            }
            .onSubmit(of: .search) { Task { await model.submit() } }
            .task { await model.start() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            if model.recent.isEmpty {
                ContentUnavailableView {
                    Label { Text("Search your instances") } icon: { Image(systemName: "magnifyingglass") }
                } description: {
                    Text("Suggestions and results come from your own instances.")
                }
            } else {
                recentList
            }
        case .loading:
            ScrollView {
                LoadingPlaceholders()
                    .padding(Tokens.Spacing.screenInset)
            }
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
                result(row)
                    .task { await model.loadMoreIfNeeded(after: row.id) }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("search.results")
        }
    }

    private var recentList: some View {
        List {
            Section {
                ForEach(model.recent, id: \.self) { text in
                    Button { Task { await model.search(text) } } label: {
                        Label { Text(verbatim: text) } icon: { Image(systemName: "clock.arrow.circlepath") }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search.recent")
                    .swipeActions { Button(role: .destructive) { model.removeRecent(text) } label: { Text("Remove") } }
                }
            } header: {
                HStack {
                    Text("Recent")
                    Spacer()
                    Button { model.clearRecent() } label: { Text("Clear") }
                        .font(.subheadline)
                        .accessibilityIdentifier("search.clearRecent")
                }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func result(_ row: SearchModel.Row) -> some View {
        switch row {
        case .video(let video):
            Button { onSelect(video.video) } label: {
                VideoCell(VideoCellContent(row: video, pixelWidth: Int(160 * displayScale)), style: .row, thumbnailWidth: 160)
                    .equatable()
            }
            .buttonStyle(.plain)
        case .channel(let channel, let avatar):
            Button { onOpenChannel(channel) } label: {
                HStack(spacing: Tokens.Spacing.m) {
                    AvatarView(avatar, size: 56)
                        .frame(width: 160)   // Lines up with the video thumbnails.
                    Text(channel.name).font(Tokens.Typography.cellTitle).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search.channel")
        case .playlist(let playlist):
            Button { onOpenPlaylist(playlist.playlist) } label: {
                VideoCell(VideoCellContent(playlist: playlist, pixelWidth: Int(160 * displayScale)), style: .row,
                          thumbnailWidth: 160)
                    .equatable()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("search.playlist")
        }
    }
}

#endif

extension VideoCellContent {
    init(row: FeedRow, pixelWidth: Int) {
        self.init(title: row.title, channelName: row.channelName, detail: row.detail, durationText: row.durationText,
                  thumbnailURL: row.thumbnails.best(forPixelWidth: pixelWidth)?.url, isLive: row.isLive,
                  progress: row.progress)
    }

    init(playlist row: PlaylistRow, pixelWidth: Int) {
        self.init(title: row.playlist.title, channelName: row.playlist.channelName ?? "", detail: "",
                  durationText: row.countText, thumbnailURL: row.playlist.thumbnails.best(forPixelWidth: pixelWidth)?.url,
                  isLive: false, progress: nil, badgeSymbol: "list.bullet")
    }
}
