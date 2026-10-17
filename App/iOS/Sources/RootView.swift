import SwiftUI
import DesignSystem
import Core
import Library
import Playback
import FeedFeature
import LibraryFeature
import InstancesFeature
import WatchFeature
import SearchFeature
import ChannelFeature
import PlaylistFeature

struct RootView: View {
    let environment: AppEnvironment
    let onFirstFeedFrame: () -> Void
    @State private var router = SceneRouter()
    @State private var settings = AppSettings.shared
    @State private var feed: FeedModel
    @State private var search: SearchModel
    @State private var library: LibraryModel
    @State private var explore: ExploreModel
    @State private var channels: [ChannelSummary] = []
    /// The tallest a 16:9 video can be drawn in this window, in either orientation: no point
    /// decoding more (and less means AVPlayer can play it, with system PiP; ADR 0005).
    @State private var maxVideoPixels = 1080
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Shorts are portrait: their long side runs along the screen's.
    @State private var shortsPixels = 1920
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
                                              options: settings.feedOptions,
                                              watchState: WatchStateStore(environment.database),
                                              queue: QueueStore(environment.database),
                                              loadTrending: { [environment] in try await environment.trending() }) { force in
            try await environment.refreshFeed(force: force)
        })
        _library = State(initialValue: LibraryModel(watchState: WatchStateStore(environment.database),
                                                    queue: QueueStore(environment.database),
                                                    subscriptions: SubscriptionStore(environment.database),
                                                    playlists: PlaylistStore(environment.database),
                                                    userPlaylists: UserPlaylistStore(environment.database)))
        _search = State(initialValue: environment.makeSearchModel())
        _explore = State(initialValue: ExploreModel(store: TrendingStore(environment.database),
                                                    regionName: AppEnvironment.regionName) { category in
            try await environment.refreshTrending(category)
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
                               onAddToQueue: { environment.addToQueue($0.video) },
                               onSetWatched: { environment.setWatched($0.video, $1) },
                               onHideChannel: { environment.setHiddenFromHome($0.channelID, true) },
                               onOpenShorts: { rows, start in router.openShorts(rows.map(\.video), start: start) },
                               onSaveToWatchLater: { environment.saveToWatchLater($0.video) },
                               onSaveToPlaylist: { router.savingToPlaylist = $0.video })
                        .routes()
                        .settingsButton { router.openSettings() }
                        .onAppear {
                            onFirstFeedFrame()
                            environment.warmUp()
                            // Explore's list also fills Search's starting screen.
                            Task { await explore.refresh(force: false) }
                        }
                }
            } label: {
                Label { Text("Home") } icon: { Image(systemName: "house") }
            }
            Tab(value: SceneRouter.Section.explore) {
                NavigationStack(path: $router.explorePath) {
                    ExploreScreen(model: explore, transition: zoom,
                                  onSelect: { play($0.video) }, onPrefetch: { environment.prefetch($0.video) },
                                  onOpenChannel: { router.openChannel($0, name: $1) },
                                  onAddToQueue: { environment.addToQueue($0.video) },
                                  onSetWatched: { environment.setWatched($0.video, $1) },
                                  onSaveToWatchLater: { environment.saveToWatchLater($0.video) },
                                  onSaveToPlaylist: { router.savingToPlaylist = $0.video })
                        .routes()
                        .settingsButton { router.openSettings() }
                }
            } label: {
                Label { Text("Explore") } icon: { Image(systemName: "safari") }
            }
            Tab(value: SceneRouter.Section.library) {
                NavigationStack(path: $router.libraryPath) {
                    LibraryScreen(model: library, onSelect: { play($0.video) },
                                  onOpenChannel: { router.openChannel($0, name: $1) },
                                  onOpenChannels: { router.libraryPath.append(.channels) },
                                  onOpenPlaylists: { router.libraryPath.append(.savedPlaylists) },
                                  onOpenPlaylist: { target in
                                      switch target {
                                      case .own(let id): router.libraryPath.append(.userPlaylist(id))
                                      case .saved(let playlist): router.libraryPath.append(.playlist(playlist))
                                      }
                                  },
                                  onExplore: { router.section = .explore })
                        .routes()
                        .settingsButton { router.openSettings() }
                }
            } label: {
                Label { Text("Library") } icon: { Image(systemName: "books.vertical") }
            }
            Tab(value: SceneRouter.Section.search, role: .search) {
                NavigationStack(path: $router.searchPath) {
                    SearchScreen(model: search, onSelect: { play($0) },
                                 onOpenChannel: { router.openChannel($0.id, name: $0.name) },
                                 onOpenPlaylist: { router.push(.playlist($0)) },
                                 onOpenExplore: { router.section = .explore })
                        .routes()
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
                            NavigationStack(path: $router.channelPath) {
                                ChannelScreen(model: channelModel(channel.id, name: channel.name), onSelect: { play($0) },
                                              onOpenPlaylist: { router.push(.playlist($0)) },
                                              onOpenShorts: { router.openShorts($0, start: $1) })
                                    .routes()
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
        .tabBarMinimizeBehavior(.onScrollDown)
        .miniPlayer(isEnabled: environment.session.item != nil && router.watching == nil) {
            MiniPlayerBar(session: environment.session) { reopenPlayer() }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            let short = min(size.width, size.height), long = max(size.width, size.height)
            maxVideoPixels = Int(min(short, long * 9 / 16) * displayScale)
            shortsPixels = Int(long * displayScale)
        }
        .onChange(of: settings.feedOptions) { _, options in
            feed.setOptions(options)
            environment.refreshBranding()
        }
        .onChange(of: scenePhase) { _, phase in
            environment.scenePhaseChanged(phase)
            switch phase {
            case .active: NewUploadNotifier.markSeen()
            case .background: BackgroundRefresh.schedule()
            default: break
            }
        }
        // The Playback menu and keyboard shortcuts act on the player only while it's open.
        .focusedSceneValue(\.player, router.watching == nil ? nil : PlayerCommandsTarget(
            session: environment.session,
            toggleCaptions: { environment.toggleCaptions() },
            toggleAudioOnly: {
                let mode: PlaybackMode = environment.session.mode == .audioOnly ? .video : .audioOnly
                Task { await environment.switchMode(to: mode) }
            }))
        .onOpenURL { environment.open($0) }
        .userActivity(AppEnvironment.watchActivityType, isActive: environment.session.item != nil) { activity in
            environment.describeWatching(activity)
        }
        .onContinueUserActivity(AppEnvironment.watchActivityType) { activity in
            environment.continueWatching(activity.userInfo ?? [:])
        }
        .task {
            // Set before this view existed (Siri or a notification launched the app).
            if let video = environment.pendingVideo {
                environment.pendingVideo = nil
                play(video)
            }
        }
        .onChange(of: environment.pendingVideo) { _, video in
            guard let video else { return }
            environment.pendingVideo = nil
            play(video)
        }
        .onChange(of: environment.session.item?.videoID) { _, id in followAutoAdvance(to: id) }
        .onChange(of: horizontalSizeClass) { _, sizeClass in
            // Channel tabs exist only at regular width: keep the open channel when they go away.
            if sizeClass == .compact, case .channel(let id) = router.section {
                router.section = .feed
                router.feedPath.append(.channel(id, name: channels.first { $0.id == id }?.name ?? ""))
            }
        }
        .onChange(of: environment.instances, initial: true) {
            explore.setCategoriesAvailable(environment.supportsTrendingCategories)
        }
        .task(id: environment.hasSubscriptions) {
            channels = (try? SubscriptionStore(environment.database).channels()) ?? []
        }
        // Full screen on every device: a sheet on iPad is a compact form sheet, which would
        // hide the band and side-panel layouts. The zoom transition makes it swipe-dismissible.
        .sheet(item: saving(inPlayer: false)) { video in
            SaveToPlaylistSheet(model: UserPlaylistsModel(store: UserPlaylistStore(environment.database)), video: video)
        }
        .sheet(isPresented: $router.showsSettings) {
            NavigationStack(path: $router.settingsPath) {
                settingsScreen
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button { router.showsSettings = false } label: { Text("Done") }
                                .accessibilityIdentifier("settings.done")
                        }
                    }
            }
        }
        .fullScreenCover(item: $router.shorts) { content in
            ShortsScreen(session: environment.session, content: content, onShow: { video in
                // Auto-advance continues through the shelf's Shorts.
                _ = environment.startPlaylist(content.videos, at: content.videos.firstIndex { $0.id == video.id } ?? 0)
                Task { _ = try? await environment.play(video, surfaceHeight: shortsPixels) }
            }, onClose: {
                environment.session.stop()
                router.shorts = nil
            }, onSave: { environment.saveToWatchLater($0) },
            onOpenChannel: { video in
                environment.session.stop()
                router.shorts = nil
                router.openChannel(video.channelID, name: video.channelName)
            })
        }
        .fullScreenCover(item: $router.watching) { content in
            NavigationStack(path: $router.watchPath) {
                WatchScreen(session: environment.session, content: content,
                            comments: environment.canLoadComments ? { commentsModel(content.video.id) } : nil,
                            showsRelated: settings.showsRelated, actions: playerActions,
                            onSelectRelated: { play($0) },
                            onOpenChannel: { router.openChannel($0, name: $1) })
                    .toolbar(.hidden, for: .navigationBar)
                    .routes()
                    .sheet(item: saving(inPlayer: true)) { video in
                        SaveToPlaylistSheet(model: UserPlaylistsModel(store: UserPlaylistStore(environment.database)),
                                            video: video)
                    }
                    .onAppear { environment.castDiscovery.start() }
                    .onDisappear { environment.castDiscovery.stop() }
            }
            .zoomTransition(sourceID: content.video.id, in: zoom, reduceMotion: reduceMotion)
        }
        .environment(\.routeDestination, RouteDestination { route in
            switch route {
            case .channel(let id, let name):
                .channel(ChannelScreen(model: channelModel(id, name: name), onSelect: { play($0) },
                                       onOpenPlaylist: { router.push(.playlist($0)) },
                                       onOpenShorts: { router.openShorts($0, start: $1) }))
            case .playlist(let summary):
                .playlist(PlaylistScreen(model: PlaylistModel(summary: summary, store: PlaylistStore(environment.database),
                                                              load: { id, cursor in try await environment.playlist(id, cursor: cursor) }),
                                         onPlay: { videos, start in
                                             if let video = environment.startPlaylist(videos, at: start) { play(video) }
                                         }))
            case .savedPlaylists:
                .savedPlaylists(PlaylistsScreen(saved: SavedPlaylistsModel(store: PlaylistStore(environment.database)),
                                                own: UserPlaylistsModel(store: UserPlaylistStore(environment.database)),
                                                onOpenSaved: { router.push(.playlist($0)) },
                                                onOpenOwn: { router.push(.userPlaylist($0)) }))
            case .userPlaylist(let id):
                .userPlaylist(UserPlaylistScreen(model: UserPlaylistsModel(store: UserPlaylistStore(environment.database)),
                                                 id: id, onPlay: { videos, start in
                                                     if let video = environment.startPlaylist(videos, at: start) { play(video) }
                                                 }))
            case .channels:
                .channels(ChannelsScreen(model: ChannelsModel(subscriptions: SubscriptionStore(environment.database)),
                                         onOpen: { router.openChannel($0.id, name: $0.name) },
                                         onUnsubscribe: { channel in
                                             Task { try? await environment.setSubscribed(channel, false) }
                                         }))
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
        actions.captions = environment.captionTracks
        actions.selectedCaption = environment.selectedCaption
        actions.selectCaption = { environment.selectCaption($0) }
        actions.toggleCaptions = { environment.toggleCaptions() }
        actions.qualities = environment.availableQualities
        actions.selectedQuality = environment.manualQuality
        actions.selectQuality = { height in Task { await environment.selectQuality(height) } }
        actions.audioTracks = environment.availableAudioTracks
        actions.selectedAudio = environment.selectedAudioLanguage
        actions.selectAudio = { language in Task { await environment.selectAudio(language) } }
        if let video = router.watching?.video {
            actions.saveToPlaylist = { router.savingToPlaylist = video }
            // YouTube's own address: it opens in any app, this one included (descriptions,
            // Handoff), and says nothing about the instance.
            actions.shareURL = URL(string: "https://www.youtube.com/watch?v=\(video.id.rawValue)")
            let session = environment.session
            actions.shareURLAtCurrentTime = {
                let seconds = Int(session.position.components.seconds)
                return URL(string: "https://www.youtube.com/watch?v=\(video.id.rawValue)&t=\(seconds)s")
            }
        }
        actions.upNext = environment.upNext
        actions.cancelUpNext = { environment.cancelUpNext() }
        actions.playUpNextNow = { environment.playUpNextNow() }
        actions.sleepChoice = environment.sleepTimer.choice
        actions.sleepStatus = environment.sleepTimer.status
        actions.setSleep = { environment.sleepTimer.set($0) }
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
                     loadPlaylists: environment.channelPlaylistsLoader,
                     loadShorts: { id, cursor in try await environment.channelShorts(id, cursor: cursor) },
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

    /// Auto-advance (the queue, a playlist) plays from the environment: the open player follows.
    /// "Save to Playlist" presents from the player when it's open (a sheet can't show over a
    /// full-screen cover from below it), else from the root.
    private func saving(inPlayer: Bool) -> Binding<VideoSummary?> {
        Binding(get: { (router.watching != nil) == inPlayer ? router.savingToPlaylist : nil },
                set: { router.savingToPlaylist = $0 })
    }

    private func followAutoAdvance(to id: VideoID?) {
        guard let id, let watching = router.watching, watching.video.id != id,
              let page = environment.currentPage, page.details.summary.id == id else { return }
        var content = WatchContent(video: page.details.summary, details: page.details)
        content.setChapters(page.manifest.chapters)
        content.storyboard = page.manifest.storyboards.best(forFrameWidth: 160)
        router.watchPath = []
        router.watching = content
    }

    private func play(_ video: VideoSummary) {
        if environment.isQueued(video.id) { queuedIDs.insert(video.id) }
        router.watchPath = []
        router.watching = WatchContent(video: video)
        Task {
            do {
                let page = try await environment.play(video, surfaceHeight: maxVideoPixels)
                guard router.watching?.video.id == video.id else { return }
                router.watching?.details = page.details
                router.watching?.setChapters(page.manifest.chapters)
                router.watching?.storyboard = page.manifest.storyboards.best(forFrameWidth: 160)
            } catch {
                if router.watching?.video.id == video.id { router.watching?.error = AppEnvironment.message(for: error) }
            }
        }
    }
}

// MARK: - Typed routes

/// Builds the screen for a route; set once at the root so every stack resolves routes alike.
struct RouteDestination {
    let build: @MainActor (SceneRouter.Route) -> RouteView

    init(_ build: @escaping @MainActor (SceneRouter.Route) -> RouteView) {
        self.build = build
    }
}

/// A pushed screen; an enum rather than `AnyView`, so SwiftUI keeps each screen's identity.
enum RouteView: View {
    case channel(ChannelScreen)
    case channels(ChannelsScreen)
    case playlist(PlaylistScreen)
    case savedPlaylists(PlaylistsScreen)
    case userPlaylist(UserPlaylistScreen)

    var body: some View {
        switch self {
        case .channel(let screen): screen
        case .channels(let screen): screen
        case .playlist(let screen): screen
        case .savedPlaylists(let screen): screen
        case .userPlaylist(let screen): screen
        }
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

    /// The gear at the top trailing corner that opens Settings (⌘, on a keyboard or a Mac).
    func settingsButton(_ open: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: open) {
                    Label { Text("Settings") } icon: { Image(systemName: "gearshape") }
                }
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityIdentifier("settings.open")
            }
        }
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
