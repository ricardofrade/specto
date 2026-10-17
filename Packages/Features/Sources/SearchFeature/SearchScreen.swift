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
    private let onOpenExplore: (() -> Void)?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameter onOpenExplore: "See All" under Trending on the starting screen (nil: none).
    public init(model: SearchModel, onSelect: @escaping (VideoSummary) -> Void,
                onOpenChannel: @escaping (ChannelSummary) -> Void = { _ in },
                onOpenPlaylist: @escaping (PlaylistSummary) -> Void = { _ in },
                onOpenExplore: (() -> Void)? = nil) {
        self.onOpenExplore = onOpenExplore
        self.model = model
        self.onSelect = onSelect
        self.onOpenChannel = onOpenChannel
        self.onOpenPlaylist = onOpenPlaylist
    }

    /// Hosted in the app's `NavigationStack`.
    public var body: some View {
        content
            .navigationTitle(Text("Search"))
            // Always showing: the starting screen scrolls, and a field that hides until pulled
            // down is no use on the Search tab.
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Videos, channels, playlists"))
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
            .safeAreaInset(edge: .top, spacing: 0) { networkPicker }
            .task { await model.start() }
    }

    /// YouTube or PeerTube, with both set up: the same query searches the other.
    @ViewBuilder
    private var networkPicker: some View {
        if model.networks.count > 1 {
            Picker(selection: $model.network) {
                ForEach(model.networks, id: \.self) { Text(verbatim: $0.title).tag($0) }
            } label: {
                Text("Search on")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Tokens.Spacing.screenInset)
            .padding(.vertical, Tokens.Spacing.s)
            .accessibilityIdentifier("search.network")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            if model.hasIdleContent {
                idle
            } else {
                ContentUnavailableView {
                    Label { Text("Search your instances") } icon: { Image(systemName: "magnifyingglass") }
                } description: {
                    Text("Suggestions and results come from your own instances.")
                }
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

    /// Before typing: recent searches as chips, the person's channels, and what's trending.
    private var idle: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.section) {
                if !model.recent.isEmpty {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
                        header(Text("Recent")) {
                            Button { model.clearRecent() } label: { Text("Clear") }
                                .accessibilityIdentifier("search.clearRecent")
                        }
                        FlowLayout {
                            ForEach(model.recent, id: \.self) { text in
                                Button { Task { await model.search(text) } } label: {
                                    Label { Text(verbatim: text).lineLimit(1) } icon: { Image(systemName: "clock.arrow.circlepath") }
                                }
                                .buttonStyle(.glass)
                                .accessibilityIdentifier("search.recent")
                                .contextMenu {
                                    Button(role: .destructive) { model.removeRecent(text) } label: {
                                        Label { Text("Remove") } icon: { Image(systemName: "trash") }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Tokens.Spacing.screenInset)
                }
                if !model.channels.isEmpty {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
                        header(Text("Your Channels")) { EmptyView() }
                            .padding(.horizontal, Tokens.Spacing.screenInset)
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: Tokens.Spacing.m) {
                                ForEach(model.channels) { item in
                                    Button { onOpenChannel(item.channel) } label: {
                                        VStack(spacing: Tokens.Spacing.xs) {
                                            AvatarView(item.avatar, size: 60)
                                            // Left out at accessibility sizes (a letter or two
                                            // wide); VoiceOver still reads it.
                                            if !typeSize.isAccessibilitySize {
                                                Text(verbatim: item.channel.name)
                                                    .font(.caption)
                                                    .foregroundStyle(Tokens.Colors.textSecondary)
                                                    .lineLimit(1)
                                                    .frame(width: 72)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(Text(verbatim: item.channel.name))
                                    .accessibilityIdentifier("search.yourChannel")
                                }
                            }
                            .padding(.horizontal, Tokens.Spacing.screenInset)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                if !model.trending.isEmpty {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
                        header(Label { Text("Trending") } icon: { Image(systemName: "flame.fill") }) {
                            if let onOpenExplore {
                                Button(action: onOpenExplore) { Text("See All") }
                                    .accessibilityIdentifier("search.seeAllTrending")
                            }
                        }
                        ForEach(model.trending) { row in
                            Button { onSelect(row.video) } label: {
                                VideoCell(VideoCellContent(row: row, pixelWidth: Int(160 * displayScale)), style: .row,
                                          thumbnailWidth: 160)
                                    .equatable()
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("search.trending")
                        }
                    }
                    .padding(.horizontal, Tokens.Spacing.screenInset)
                }
            }
            .padding(.vertical, Tokens.Spacing.l)
        }
        .accessibilityIdentifier("search.idle")
    }

    private func header(_ title: some View, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            title
                .font(Tokens.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
        }
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
                  progress: row.progress, isPeerTube: row.id.isPeerTube)
    }

    init(playlist row: PlaylistRow, pixelWidth: Int) {
        self.init(title: row.playlist.title, channelName: row.playlist.channelName ?? "", detail: "",
                  durationText: row.countText, thumbnailURL: row.playlist.thumbnails.best(forPixelWidth: pixelWidth)?.url,
                  isLive: false, progress: nil, badgeSymbol: "list.bullet")
    }
}
