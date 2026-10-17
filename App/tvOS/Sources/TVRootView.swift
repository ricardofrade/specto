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
    @State private var savedPlaylists: SavedPlaylistsModel
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
                                              queue: QueueStore(environment.database)) { force in
            try await environment.refreshFeed(force: force)
        })
        _library = State(initialValue: LibraryModel(watchState: WatchStateStore(environment.database),
                                                    queue: QueueStore(environment.database)))
        _savedPlaylists = State(initialValue: SavedPlaylistsModel(store: PlaylistStore(environment.database)))
        _search = State(initialValue: environment.makeSearchModel())
    }

    var body: some View {
        TabView {
            Tab {
                NavigationStack(path: $homePath) {
                    HomeView(environment: environment, feed: feed, actions: actions { homePath.append($0) })
                        .onAppear(perform: onFirstFeedFrame)
                        .routes(environment: environment, actions: actions { homePath.append($0) })
                }
            } label: {
                Text("Home")
            }
            Tab {
                NavigationStack(path: $libraryPath) {
                    TVLibraryView(model: library, playlists: savedPlaylists, actions: actions { libraryPath.append($0) })
                        .routes(environment: environment, actions: actions { libraryPath.append($0) })
                }
            } label: {
                Text("Library")
            }
            Tab(role: .search) {
                NavigationStack(path: $searchPath) {
                    TVSearchView(model: search, actions: actions { searchPath.append($0) })
                        .routes(environment: environment, actions: actions { searchPath.append($0) })
                }
            }
            Tab {
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
                     hideChannel: { environment.setHiddenFromHome($0, true) })
    }

    private func play(_ video: VideoSummary) {
        environment.prefetch(video)
        playing = video
    }

}

enum TVRoute: Hashable {
    case channel(ChannelID, String)
    case playlist(PlaylistSummary)
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
            case .playlist(let summary):
                TVPlaylistView(model: PlaylistModel(summary: summary, store: PlaylistStore(environment.database),
                                                    load: { id, cursor in try await environment.playlist(id, cursor: cursor) }),
                               actions: actions)
            }
        }
    }
}
