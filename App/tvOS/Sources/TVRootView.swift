import SwiftUI
import Core
import Library
import FeedFeature
import LibraryFeature
import SearchFeature
import ChannelFeature
import PlaylistFeature
import InstancesFeature
import DesignSystem

/// Home, Search and Settings in the tvOS top tab bar. Each tab has its own stack; channels push
/// onto it, and videos play full screen over everything.
struct TVRootView: View {
    let environment: AppEnvironment
    let onFirstFeedFrame: () -> Void
    @State private var feed: FeedModel
    @State private var search: SearchModel
    @State private var library: LibraryModel
    @State private var explore: ExploreModel
    @State private var explorePath: [TVRoute] = []
    @State private var tab = TVTab.home
    @State private var savedPlaylists: SavedPlaylistsModel
    @State private var ownPlaylists: UserPlaylistsModel
    @State private var libraryPath: [TVRoute] = []
    @State private var homePath: [TVRoute] = []
    @State private var searchPath: [TVRoute] = []
    @State private var playing: VideoSummary?
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment, onFirstFeedFrame: @escaping () -> Void) {
        self.environment = environment
        self.onFirstFeedFrame = onFirstFeedFrame
        _feed = State(initialValue: FeedModel(store: FeedStore(environment.database),
                                              options: AppSettings.shared.feedOptions,
                                              watchState: WatchStateStore(environment.database),
                                              queue: QueueStore(environment.database),
                                              loadTrending: { [environment] in try await environment.trending() }) { force in
            try await environment.refreshFeed(force: force)
        })
        _library = State(initialValue: LibraryModel(watchState: WatchStateStore(environment.database),
                                                    queue: QueueStore(environment.database)))
        _savedPlaylists = State(initialValue: SavedPlaylistsModel(store: PlaylistStore(environment.database)))
        _ownPlaylists = State(initialValue: UserPlaylistsModel(store: UserPlaylistStore(environment.database)))
        _search = State(initialValue: environment.makeSearchModel())
        _explore = State(initialValue: ExploreModel(store: TrendingStore(environment.database),
                                                    regionName: AppEnvironment.regionName) { category in
            try await environment.refreshTrending(category)
        })
    }

    enum TVTab: Hashable { case home, explore, library, search, settings }

    var body: some View {
        TabView(selection: $tab) {
            Tab(value: TVTab.home) {
                NavigationStack(path: $homePath) {
                    HomeView(environment: environment, feed: feed, actions: actions { homePath.append($0) },
                             openSettings: { tab = .settings })
                        .onAppear(perform: onFirstFeedFrame)
                        .routes(environment: environment, actions: actions { homePath.append($0) })
                }
            } label: {
                Text("Home")
            }
            Tab(value: TVTab.explore) {
                NavigationStack(path: $explorePath) {
                    TVExploreView(model: explore, actions: actions { explorePath.append($0) })
                        .routes(environment: environment, actions: actions { explorePath.append($0) })
                }
            } label: {
                Text("Explore")
            }
            Tab(value: TVTab.library) {
                NavigationStack(path: $libraryPath) {
                    TVLibraryView(model: library, playlists: savedPlaylists, own: ownPlaylists, actions: actions { libraryPath.append($0) })
                        .routes(environment: environment, actions: actions { libraryPath.append($0) })
                }
            } label: {
                Text("Library")
            }
            Tab(value: TVTab.search, role: .search) {
                NavigationStack(path: $searchPath) {
                    TVSearchView(model: search, actions: actions { searchPath.append($0) })
                        .routes(environment: environment, actions: actions { searchPath.append($0) })
                }
            }
            Tab(value: TVTab.settings) {
                NavigationStack {
                    TVSettingsView(environment: environment)
                }
            } label: {
                Text("Settings")
            }
        }
        .fullScreenCover(item: $playing) { video in
            TVPlayerView(environment: environment, video: video)
        }
        .onOpenURL { environment.open($0) }
        .onChange(of: environment.pendingVideo) { _, video in
            guard let video else { return }
            environment.pendingVideo = nil
            play(video)
        }
        .onChange(of: AppSettings.shared.feedOptions) { _, options in
            feed.setOptions(options)
            Task { await feed.refresh(force: false) }
        }
        .onChange(of: scenePhase) { _, phase in
            environment.scenePhaseChanged(phase)
        }
        .onChange(of: environment.instances, initial: true) {
            explore.setCategoriesAvailable(environment.supportsTrendingCategories)
        }
        .task { environment.warmUp() }
    }

    /// - Parameter push: onto the tab's own stack.
    private func actions(push: @escaping (TVRoute) -> Void) -> VideoActions {
        VideoActions(play: play, openChannel: { push(.channel($0, $1)) }, addToQueue: { environment.addToQueue($0) },
                     openPlaylist: { push(.playlist($0)) },
                     playPlaylist: { videos, start in
                         if let video = environment.startPlaylist(videos, at: start) { play(video) }
                     },
                     setWatched: { environment.setWatched($0, $1) },
                     hideChannel: { environment.setHiddenFromHome($0, true) },
                     saveToWatchLater: { environment.saveToWatchLater($0) },
                     openUserPlaylist: { push(.userPlaylist($0)) })
    }

    private func play(_ video: VideoSummary) {
        environment.prefetch(video)
        playing = video
    }

}

enum TVRoute: Hashable {
    case channel(ChannelID, String)
    case playlist(PlaylistSummary)
    case userPlaylist(String)
}

private extension View {
    func routes(environment: AppEnvironment, actions: VideoActions) -> some View {
        navigationDestination(for: TVRoute.self) { route in
            switch route {
            case .channel(let id, let name):
                TVChannelView(model: ChannelModel(
                    channelID: id, name: name,
                    cached: (try? FeedStore(environment.database).videos(channel: id)) ?? [],
                    isSubscribed: environment.isSubscribed(id),
                    load: { id, cursor in try await environment.channel(id, cursor: cursor) },
                    loadPlaylists: environment.channelPlaylistsLoader,
                    setSubscribed: { channel, subscribed in try await environment.setSubscribed(channel, subscribed) }),
                    actions: actions)
            case .userPlaylist(let id):
                TVUserPlaylistView(model: UserPlaylistsModel(store: UserPlaylistStore(environment.database)), id: id,
                                   actions: actions)
            case .playlist(let summary):
                TVPlaylistView(model: PlaylistModel(summary: summary, store: PlaylistStore(environment.database),
                                                    load: { id, cursor in try await environment.playlist(id, cursor: cursor) }),
                               actions: actions)
            }
        }
    }
}
