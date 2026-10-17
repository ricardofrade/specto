import SwiftUI
import Core
import Library
import FeedFeature
import SearchFeature
import ChannelFeature
import InstancesFeature
import DesignSystem

/// Home, Search and Settings in the tvOS top tab bar. Each tab has its own stack; channels push
/// onto it, and videos play full screen over everything.
struct TVRootView: View {
    let environment: AppEnvironment
    let onFirstFeedFrame: () -> Void
    @State private var feed: FeedModel
    @State private var search: SearchModel
    @State private var homePath: [TVRoute] = []
    @State private var searchPath: [TVRoute] = []
    @State private var playing: VideoSummary?
    /// Bumped when the player closes so shelves (continue watching, queue) re-read.
    @State private var shelvesVersion = 0
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment, onFirstFeedFrame: @escaping () -> Void) {
        self.environment = environment
        self.onFirstFeedFrame = onFirstFeedFrame
        _feed = State(initialValue: FeedModel(store: FeedStore(environment.database),
                                              options: AppSettings.shared.feedOptions) { force in
            try await environment.refreshFeed(force: force)
        })
        _search = State(initialValue: SearchModel { query, cursor in
            try await environment.search(query, cursor: cursor)
        })
    }

    var body: some View {
        TabView {
            Tab {
                NavigationStack(path: $homePath) {
                    HomeView(environment: environment, feed: feed, shelvesVersion: shelvesVersion,
                             actions: actions { homePath.append(.channel($0, $1)) })
                        .onAppear(perform: onFirstFeedFrame)
                        .routes(environment: environment, actions: actions { homePath.append(.channel($0, $1)) })
                }
            } label: {
                Text("Home")
            }
            Tab(role: .search) {
                NavigationStack(path: $searchPath) {
                    TVSearchView(model: search, actions: actions { searchPath.append(.channel($0, $1)) })
                        .routes(environment: environment, actions: actions { searchPath.append(.channel($0, $1)) })
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
        .fullScreenCover(item: $playing, onDismiss: { shelvesVersion += 1 }) { video in
            TVPlayerView(environment: environment, video: video)
        }
        .onOpenURL(perform: open)
        .onChange(of: AppSettings.shared.feedOptions) { _, options in
            feed.setOptions(options)
            Task { await feed.refresh(force: false) }
        }
        .onChange(of: scenePhase) { _, phase in
            environment.scenePhaseChanged(phase)
            if phase == .background { TopShelfPublisher.publish(environment.database) }
        }
        .task { environment.warmUp() }
    }

    private func actions(openChannel: @escaping (ChannelID, String) -> Void) -> VideoActions {
        VideoActions(play: play, openChannel: openChannel, addToQueue: { environment.addToQueue($0) })
    }

    private func play(_ video: VideoSummary) {
        environment.prefetch(video)
        playing = video
    }

    /// Top Shelf deep links: play the named video, from the cache when it's there.
    private func open(_ url: URL) {
        guard let raw = TopShelfSnapshot.videoID(in: url) else { return }
        let id = VideoID(rawValue: raw)
        playing = (try? FeedStore(environment.database).video(id))
            ?? VideoSummary(id: id, title: "", channelID: ChannelID(rawValue: ""), channelName: "",
                            duration: nil, publishedAt: nil, viewCount: nil, thumbnails: [])
    }
}

enum TVRoute: Hashable {
    case channel(ChannelID, String)
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
                    setSubscribed: { channel, subscribed in try await environment.setSubscribed(channel, subscribed) }),
                    actions: actions)
            }
        }
    }
}
