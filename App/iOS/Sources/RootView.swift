import SwiftUI
import Core
import Library
import Playback
import FeedFeature
import InstancesFeature
import WatchFeature
import SearchFeature
import ChannelFeature

struct RootView: View {
    let environment: AppEnvironment
    let onFirstFeedFrame: () -> Void
    @State private var router = SceneRouter()
    @State private var settings = AppSettings.shared
    @State private var feed: FeedModel
    @State private var search: SearchModel
    @State private var channels: [ChannelSummary] = []
    @State private var shortSidePixels = 1080
    @State private var queuedIDs: Set<VideoID> = []
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Namespace private var zoom
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment, onFirstFeedFrame: @escaping () -> Void) {
        self.environment = environment
        self.onFirstFeedFrame = onFirstFeedFrame
        let settings = AppSettings.shared
        _feed = State(initialValue: FeedModel(store: FeedStore(environment.database),
                                              options: settings.feedOptions) { force in
            try await environment.refreshFeed(force: force)
        })
        _search = State(initialValue: SearchModel { query, cursor in
            try await environment.search(query, cursor: cursor)
        })
    }

    var body: some View {
        TabView(selection: $router.section) {
            Tab(value: SceneRouter.Section.feed) {
                NavigationStack(path: $router.feedPath) {
                    FeedScreen(model: feed, emptyReason: emptyReason, transition: zoom,
                               onEmptyAction: { router.openInstances() },
                               onSelect: { play($0.video) }, onPrefetch: { environment.prefetch($0.video) },
                               onOpenChannel: { router.openChannel($0, name: $1) },
                               onAddToQueue: { environment.addToQueue($0.video) })
                        .routes()
                        .onAppear {
                            onFirstFeedFrame()
                            environment.warmUp()
                        }
                }
            } label: {
                Label { Text("Subscriptions") } icon: { Image(systemName: "play.square.stack") }
            }
            Tab(value: SceneRouter.Section.settings) {
                NavigationStack(path: $router.settingsPath) { settingsScreen }
            } label: {
                Label { Text("Settings") } icon: { Image(systemName: "gearshape") }
            }
            Tab(value: SceneRouter.Section.search, role: .search) {
                NavigationStack(path: $router.searchPath) {
                    SearchScreen(model: search) { play($0) }.routes()
                }
            } label: {
                Label { Text("Search") } icon: { Image(systemName: "magnifyingglass") }
            }
            // Regular width (iPad) gets a sidebar that lists subscriptions as channels. Compact
            // width has only a tab bar, where `.defaultVisibility(.hidden, for: .tabBar)` alone
            // didn't hide them (seen in the iPhone tab bar), so they aren't added there at all.
            if horizontalSizeClass == .regular {
                TabSection {
                    ForEach(channels) { channel in
                        Tab(value: SceneRouter.Section.channel(channel.id)) {
                            NavigationStack {
                                ChannelScreen(model: channelModel(channel.id, name: channel.name)) { play($0) }
                            }
                        } label: {
                            Label { Text(channel.name) } icon: { Image(systemName: "person.crop.circle") }
                        }
                        .defaultVisibility(.hidden, for: .tabBar)
                    }
                } header: {
                    Text("Channels")
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .miniPlayer(isEnabled: environment.session.item != nil && router.watching == nil) {
            MiniPlayerBar(session: environment.session) { reopenPlayer() }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            shortSidePixels = Int(min(size.width, size.height) * displayScale)
        }
        .onChange(of: settings.feedOptions) { _, options in
            feed.setOptions(options)
            environment.refreshBranding()
        }
        .onChange(of: scenePhase) { _, phase in environment.scenePhaseChanged(phase) }
        .onChange(of: horizontalSizeClass) { _, sizeClass in
            // Channel tabs exist only at regular width: keep the open channel when they go away.
            if sizeClass == .compact, case .channel(let id) = router.section {
                router.section = .feed
                router.feedPath.append(.channel(id, name: channels.first { $0.id == id }?.name ?? ""))
            }
        }
        .task(id: environment.hasSubscriptions) {
            channels = (try? SubscriptionStore(environment.database).channels()) ?? []
        }
        // Full screen on every device: a sheet on iPad is a compact form sheet, which would
        // hide the band and side-panel layouts. The zoom transition makes it swipe-dismissible.
        .fullScreenCover(item: $router.watching) { content in
            NavigationStack(path: $router.watchPath) {
                WatchScreen(session: environment.session, content: content,
                            comments: environment.canLoadComments ? { commentsModel(content.video.id) } : nil,
                            showsRelated: settings.showsRelated, actions: playerActions,
                            onSelectRelated: { play($0) },
                            onOpenChannel: { router.openChannel($0, name: $1) })
                    .toolbar(.hidden, for: .navigationBar)
                    .routes()
                    .onAppear { environment.castDiscovery.start() }
                    .onDisappear { environment.castDiscovery.stop() }
            }
            .navigationTransition(.zoom(sourceID: content.video.id, in: zoom))
        }
        .environment(\.routeDestination, RouteDestination { route in
            switch route {
            case .channel(let id, let name):
                ChannelScreen(model: channelModel(id, name: name)) { play($0) }
            }
        })
    }

    private var settingsScreen: some View {
        SettingsView(environment: environment, settings: settings)
    }

    private var playerActions: PlayerActions {
        var actions = PlayerActions(switchMode: { mode in Task { await environment.switchMode(to: mode) } },
                                    startPictureInPicture: environment.canStartPictureInPicture
                                        ? { environment.startPictureInPicture() } : nil,
                                    castTargets: environment.castTargets,
                                    cast: { environment.cast(to: $0) },
                                    casting: environment.casting)
        if let video = router.watching?.video {
            actions.isQueued = queuedIDs.contains(video.id)
            actions.toggleQueue = {
                if queuedIDs.contains(video.id) {
                    environment.removeFromQueue(video.id)
                    queuedIDs.remove(video.id)
                } else {
                    environment.addToQueue(video)
                    queuedIDs.insert(video.id)
                }
            }
        }
        return actions
    }

    private var emptyReason: FeedScreen.EmptyReason? {
        if environment.instances.isEmpty { return .noInstance }
        if !environment.hasSubscriptions && environment.account == nil { return .noSubscriptions }
        return nil
    }

    private func channelModel(_ id: ChannelID, name: String) -> ChannelModel {
        ChannelModel(channelID: id, name: name,
                     cached: (try? FeedStore(environment.database).videos(channel: id)) ?? [],
                     isSubscribed: environment.isSubscribed(id),
                     load: { id, cursor in try await environment.channel(id, cursor: cursor) },
                     setSubscribed: { channel, subscribed in try await environment.setSubscribed(channel, subscribed) })
    }

    private func commentsModel(_ id: VideoID) -> CommentsModel {
        CommentsModel(videoID: id) { id, cursor in try await environment.comments(id, cursor: cursor) }
    }

    private func reopenPlayer() {
        guard let item = environment.session.item else { return }
        var content = WatchContent(video: VideoSummary(
            id: item.videoID, title: item.title, channelID: ChannelID(rawValue: ""), channelName: item.channelName,
            duration: nil, publishedAt: nil, viewCount: nil,
            thumbnails: item.artworkURL.map { [Thumbnail(url: $0, width: 0, height: 0)] } ?? []))
        content.setChapters(item.chapters)
        router.watchPath = []
        router.watching = content
    }

    private func play(_ video: VideoSummary) {
        if environment.isQueued(video.id) { queuedIDs.insert(video.id) }
        router.watchPath = []
        router.watching = WatchContent(video: video)
        Task {
            do {
                let page = try await environment.play(video, surfaceHeight: shortSidePixels)
                guard router.watching?.video.id == video.id else { return }
                router.watching?.details = page.details
                router.watching?.setChapters(page.manifest.chapters)
            } catch {
                if router.watching?.video.id == video.id { router.watching?.error = AppEnvironment.message(for: error) }
            }
        }
    }
}

// MARK: - Typed routes

/// Builds the screen for a route; set once at the root so every stack resolves routes alike.
struct RouteDestination {
    let build: @MainActor (SceneRouter.Route) -> ChannelScreen

    init(_ build: @escaping @MainActor (SceneRouter.Route) -> ChannelScreen) {
        self.build = build
    }
}

extension EnvironmentValues {
    @Entry var routeDestination: RouteDestination?
}

private struct RoutesModifier: ViewModifier {
    @Environment(\.routeDestination) private var destination

    func body(content: Content) -> some View {
        content.navigationDestination(for: SceneRouter.Route.self) { route in
            destination?.build(route)
        }
    }
}

private extension View {
    func routes() -> some View {
        modifier(RoutesModifier())
    }

    /// The tab bar's bottom accessory (iOS 26.1+). On 26.0 there's no mini-player; closing the
    /// Watch screen still keeps playback going.
    @ViewBuilder
    func miniPlayer(isEnabled: Bool, @ViewBuilder content: () -> some View) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: isEnabled, content: content)
        } else {
            self
        }
    }
}

extension WatchContent: @retroactive Identifiable {
    public var id: VideoID { video.id }
}
