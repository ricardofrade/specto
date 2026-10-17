import SwiftUI
import Core
import Library
import Playback
import DesignSystem
import PlaybackUI
import InstancesFeature
import SearchFeature
#if os(iOS)
import Cast
#endif

/// The composition root: builds sources from saved instances, routes between them, and owns
/// the one `PlaybackSession` every scene shares.
@MainActor
@Observable
final class AppEnvironment {
    let database: AppDatabase
    let secrets: any SecretStore
    let session: PlaybackSession
    /// Pauses after a while or at the end of the video (the player's Playback Settings menu).
    let sleepTimer: SleepTimer
    private(set) var instances: [InstanceConfig] = []
    private(set) var hasSubscriptions = false
    /// A video to open from outside the app (widget, Shortcuts, notification, Handoff); the root
    /// view plays it and clears this.
    var pendingVideo: VideoSummary?
    /// Subtitle tracks of the video now playing, and the one showing (set by the playback extensions).
    var captionTracks: [CaptionTrack] = []
    var selectedCaption: CaptionTrack?
    @ObservationIgnored private(set) var router = InstanceRouter(sources: [])
    @ObservationIgnored private(set) var refresher: FeedRefresher
    @ObservationIgnored private(set) var account: (any SubscriptionAccount)?
    @ObservationIgnored private let manifests: ManifestCache
    @ObservationIgnored private let resumeStore: LibraryResumeStore
    @ObservationIgnored private var prefetching: Set<VideoID> = []
    @ObservationIgnored private var lastRecovery: (id: VideoID, at: ContinuousClock.Instant)?
    @ObservationIgnored var surfaceHeight = 1080
    /// The page now playing; audio mode, PiP, AirPlay and casting re-plan from it.
    @ObservationIgnored var currentPage: WatchPage? {
        didSet {
            availableQualities = currentPage.map {
                VideoQuality.heights(in: $0.manifest.videoStreams, capabilities: DecodeCapabilities(), allowHDR: false)
            } ?? []
            availableAudioTracks = currentPage.map { AudioTracks.options(in: $0.manifest.audioStreams) } ?? []
        }
    }
    /// The heights the player's Quality picker offers for this video, tallest first.
    private(set) var availableQualities: [Int] = []
    /// The audio tracks the player's Audio picker offers (empty: nothing to choose).
    private(set) var availableAudioTracks: [AudioTrackOption] = []
    /// The track playing: the remembered language when this video has it, else the original (nil).
    var selectedAudioLanguage: String? {
        AudioTracks.selected(AppSettings.shared.audioLanguage, in: availableAudioTracks)
    }
    var selectedAudioTrack: AudioTrackOption? {
        let language = selectedAudioLanguage
        return availableAudioTracks.first { $0.language == language }
    }

    /// Picked in the player for this video; nil plans automatically (ADR 0007).
    private(set) var manualQuality: Int?
    /// Autoplay's countdown while it runs (the Watch screen's card, the TV's Up Next panel).
    var upNext: UpNextCountdown?
    @ObservationIgnored var upNextTask: Task<Void, Never>?
    /// The playlist being played through (Play All); auto-advance continues in it after the queue.
    @ObservationIgnored var playlistContext: [VideoSummary] = []
    @ObservationIgnored var nowPlaying: NowPlayingController?
    @ObservationIgnored let community = CommunityServices()
    /// CloudKit sync, when configured: instances always (so the TV gets the phone's), the
    /// library too unless a YT Zero account owns it (ADR 0002, ADR 0004, ADR 0006).
    @ObservationIgnored private(set) var cloudSync: CloudSync?
    @ObservationIgnored private var instanceObservation: Task<Void, Never>?
    #if os(iOS)
    // iPhone and iPad only: PiP handoff, Cast sender, AirPlay switching, MetricKit (none on tvOS).
    @ObservationIgnored let pictureInPicture = PictureInPictureHandoff()
    @ObservationIgnored let systemPictureInPicture = SystemPictureInPicture()
    let castDiscovery = CastDiscovery()
    let castSession = CastSession()
    @ObservationIgnored var routeObserver: (any NSObjectProtocol)?
    @ObservationIgnored let diagnostics = DiagnosticsCollector()
    #endif
    #if OFFLINE_DOWNLOADS
    @ObservationIgnored let offlineAudio: OfflineAudio
    #endif

    init(database: AppDatabase, secrets: any SecretStore = KeychainSecretStore()) {
        self.database = database
        self.secrets = secrets
        manifests = ManifestCache(database)
        #if OFFLINE_DOWNLOADS
        offlineAudio = OfflineAudio(database: database)
        #endif
        refresher = FeedRefresher(mode: .local(InstanceRouter(sources: [])), database: database)
        let resume = LibraryResumeStore(store: WatchStateStore(database))
        resumeStore = resume
        session = PlaybackSession(resumeStore: resume) { kind in
            switch kind {
            case .mpv: MPVEngine()
            case .avPlayer: AVPlayerEngine()
            }
        }
        sleepTimer = SleepTimer(session: session)
        reloadSources()
        watchForExpiredStreams()
        startSystemIntegration()
        #if os(iOS)
        diagnostics.start()
        #endif
        watchForEndOfPlayback()
    }

    /// One per app: the window scenes (and CarPlay on iOS) share it and its session.
    static let shared = live()

    static func live() -> AppEnvironment {
        if let testing = forUITests() { return testing }
        do {
            return AppEnvironment(database: try .onDisk(at: AppDatabase.defaultURL()))
        } catch {
            // A broken database must not stop launch; run from memory and rebuild next time.
            return AppEnvironment(database: try! .inMemory())
        }
    }

    /// Launch-argument hooks for UI and performance tests (in-memory only, never the user's data;
    /// kept in Release because the performance gates run there).
    /// `-UITestFreshStart`: empty in-memory state. `-SeedSubscriptions UC…,UC…`: subscribe
    /// without the file picker, which UI tests can't drive. `-SeedDemoFeed N`: N cached videos
    /// (`-SeedHistory N` marks the first N watched).
    /// `-SeedInstance <Piped API URL>`: an instance without typing (the TV keyboard).
    private static func forUITests() -> AppEnvironment? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UITestFreshStart"), let database = try? AppDatabase.inMemory() else { return nil }
        if let index = arguments.firstIndex(of: "-SeedSubscriptions"), arguments.indices.contains(index + 1) {
            let channels = arguments[index + 1].split(separator: ",").map {
                ChannelSummary(id: ChannelID(rawValue: String($0)), name: "", avatar: nil)
            }
            try? SubscriptionStore(database).subscribe(channels)
        }
        if let index = arguments.firstIndex(of: "-SeedInstance"), arguments.indices.contains(index + 1),
           let url = URL(string: arguments[index + 1]) {
            try? InstanceStore(database).add(InstanceConfig(kind: .piped, displayName: url.host() ?? "Piped", apiURL: url))
        }
        // `-SeedPeerTube <server URL>`: a PeerTube server.
        if let index = arguments.firstIndex(of: "-SeedPeerTube"), arguments.indices.contains(index + 1),
           let url = URL(string: arguments[index + 1]) {
            try? InstanceStore(database).add(InstanceConfig(kind: .peerTube, displayName: url.host() ?? "PeerTube", apiURL: url))
        }
        // `-SeedInvidious <API URL>`: an Invidious instance (Explore's categories).
        if let index = arguments.firstIndex(of: "-SeedInvidious"), arguments.indices.contains(index + 1),
           let url = URL(string: arguments[index + 1]) {
            try? InstanceStore(database).add(InstanceConfig(kind: .invidious, displayName: url.host() ?? "Invidious", apiURL: url))
        }
        if let index = arguments.firstIndex(of: "-SeedDemoFeed"), arguments.indices.contains(index + 1),
           let count = Int(arguments[index + 1]) {
            let channel = ChannelSummary(id: ChannelID(rawValue: "UCdemo000000000000000000"), name: "Demo", avatar: nil)
            try? SubscriptionStore(database).subscribe([channel])
            try? FeedStore(database).save((0..<count).map { index in
                VideoSummary(id: VideoID(rawValue: "demo\(index)"),
                             title: "Demo video \(index + 1) with a title long enough to wrap onto two lines",
                             channelID: channel.id, channelName: "Demo channel \(index % 37)",
                             duration: .seconds(60 + index * 37 % 3600),
                             publishedAt: Date.now.addingTimeInterval(-Double(index) * 3600),
                             viewCount: index * 1_311 % 900_000, thumbnails: [])
            })
        }
        // `-SeedHistory N`: the first N demo videos, watched for a minute each.
        if let index = arguments.firstIndex(of: "-SeedHistory"), arguments.indices.contains(index + 1),
           let count = Int(arguments[index + 1]) {
            let watch = WatchStateStore(database)
            for video in 0..<count {
                try? watch.save(.seconds(60), duration: .seconds(600), for: VideoID(rawValue: "demo\(video)"))
            }
        }
        return AppEnvironment(database: database, secrets: InMemorySecretStore())
    }

    /// Rebuild sources after instances change. Piped and Invidious first (AV1/VP9, higher
    /// resolutions); YT Zero last for streams. A linked YT Zero owns subscriptions (ADR 0002).
    func reloadSources() {
        instances = (try? InstanceStore(database).all()) ?? []
        hasSubscriptions = !((try? SubscriptionStore(database).channels()) ?? []).isEmpty
        var sources: [any VideoSource] = []
        var linkedAccount: YTZeroSource?
        var imageTokens: [String: String] = [:]
        // PeerTube answers search and Explore's main list only when nothing fronts YouTube;
        // YouTube's front-ends decline PeerTube content (ADR 0016).
        let hasYouTube = instances.contains { $0.kind.isYouTube }
        for instance in instances {
            switch instance.kind {
            case .piped:
                sources.append(YouTubeOnly(PipedSource(instance: instance)))
            case .invidious:
                sources.append(YouTubeOnly(InvidiousSource(instance: instance)))
            case .peerTube:
                sources.append(PeerTubeSource(instance: instance, servesGeneralQueries: !hasYouTube))
            case .ytZero:
                guard let token = secrets.secret(for: AddInstanceModel.tokenKey(for: instance.id)) else { continue }
                let source = YTZeroSource(instance: instance, token: token)
                // The account is the YT Zero source itself (subscriptions); routing goes
                // through the wrapper below.
                if let host = instance.apiURL.host() { imageTokens[host] = token }
                linkedAccount = linkedAccount ?? source
            }
        }
        if let linkedAccount { sources.append(YouTubeOnly(linkedAccount)) }

        let router = InstanceRouter(sources: sources)
        self.router = router
        account = linkedAccount
        resumeStore.account = linkedAccount
        refresher = FeedRefresher(mode: linkedAccount.map { .account($0, router: router) } ?? .local(router), database: database)
        updateCloudSync()

        // YT Zero serves thumbnails from its own image cache, which needs the Bearer token.
        let tokens = imageTokens
        Task {
            await ImagePipeline.shared.setRequestDecorator { url in
                var request = URLRequest(url: url)
                if let host = url.host(), let token = tokens[host] {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
                return request
            }
        }
    }

    /// Runs sync only with a container in Info.plist (`CloudKitContainer`, set with the iCloud
    /// entitlement; CloudKit traps without it). A linked account narrows it to instances.
    private func updateCloudSync() {
        let container = Bundle.main.object(forInfoDictionaryKey: "CloudKitContainer") as? String ?? ""
        guard !container.isEmpty, !ProcessInfo.processInfo.arguments.contains("-UITestFreshStart") else { return }
        // A linked account owns subscriptions and watch state (ADR 0002), not instances or playlists.
        // A linked account owns YouTube subscriptions and watch state; PeerTube subscriptions
        // still sync here (ADR 0016).
        let types: Set<SyncStore.RecordType> = account == nil ? Set(SyncStore.RecordType.allCases)
                                                                    : [.instance, .playlist, .userPlaylist, .subscription]
        guard cloudSync?.types != types else { return }
        let previous = cloudSync
        let sync = CloudSync(containerIdentifier: container, database: database, types: types,
                             peerTubeSubscriptionsOnly: account != nil, secrets: secrets)
        cloudSync = sync
        Task {
            await previous?.stop()
            await sync.start()
        }
        observeInstances()
    }

    /// Instances added or removed on another device arrive through sync: rebuild the sources.
    private func observeInstances() {
        guard instanceObservation == nil else { return }
        let changes = InstanceStore(database).observe()
        instanceObservation = Task { [weak self] in
            do {
                for try await list in changes where list != self?.instances {
                    self?.instancesChanged()
                }
            } catch {}
        }
    }

    /// Foreground: pull other devices' changes, then fill channels that arrived without videos.
    func syncNow() async {
        guard let cloudSync else { return }
        await cloudSync.syncNow()
        hasSubscriptions = !((try? SubscriptionStore(database).channels()) ?? []).isEmpty
        await backfillEmptyChannels()
    }

    /// `<scheme>://watch?v=<id>` from a widget or Top Shelf.
    func open(_ url: URL) {
        guard let raw = HomeSnapshot.videoID(in: url) else { return }
        openVideo(VideoID(rawValue: raw))
    }

    /// Handoff from another device: the video and where it was, so playback resumes there.
    static let watchActivityType = "dev.placeholder.specto.watch"

    func continueWatching(_ userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo["videoID"] as? String, !raw.isEmpty else { return }
        let id = VideoID(rawValue: raw)
        if let seconds = userInfo["position"] as? Double, seconds > 0 {
            try? WatchStateStore(database).save(.milliseconds(Int64(seconds * 1000)),
                                                duration: (userInfo["duration"] as? Double).map { .milliseconds(Int64($0 * 1000)) },
                                                for: id)
        }
        openVideo(id)
    }

    /// What this device is watching, for Handoff.
    func describeWatching(_ activity: NSUserActivity) {
        guard let item = session.item else { return }
        activity.title = item.title
        activity.isEligibleForHandoff = true
        activity.userInfo = ["videoID": item.videoID.rawValue, "position": Self.seconds(session.position),
                             "duration": session.duration.map(Self.seconds) ?? 0]
        activity.needsSave = true
    }

    /// Plays a video known only by its ID: from the cache when it's there, else fetched on play.
    func openVideo(_ id: VideoID) {
        pendingVideo = (try? FeedStore(database).video(id))
            ?? VideoSummary(id: id, title: "", channelID: ChannelID(rawValue: ""), channelName: "",
                            duration: nil, publishedAt: nil, viewCount: nil, thumbnails: [])
    }

    /// After the first frame: start mpv's core and open connections to the instances, so the
    /// first tap pays for neither (tap-to-first-frame budget).
    func warmUp() {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            session.prewarm()
            _ = await router.checkHealth()
            await ImagePipeline.shared.trimDiskCache()
        }
    }

    /// Every instance's reachability and latency, for Settings → Instances. Unreachable ones
    /// also cool down in the router, as with the launch probe.
    func checkInstanceHealth() async -> [HealthSample] {
        await router.checkHealth()
    }

    // MARK: Browsing

    func search(_ query: String, filter: SearchFilter, cursor: String?) async throws -> Page<SearchResult> {
        let router = self.router
        return try await router.perform(.search) { try await $0.search(query, filter: filter, cursor: cursor) }
    }

    /// Completions from the first instance that answers; none when turned off in Settings.
    func suggestions(for query: String) async -> [String] {
        guard AppSettings.shared.searchSuggestions else { return [] }
        let router = self.router
        return (try? await router.perform(.search) { try await $0.suggestions(for: query) }) ?? []
    }

    #if os(tvOS)
    static let isTV = true
    #else
    static let isTV = false
    #endif

    /// The search model both apps use: filters, suggestions, and this device's recent searches.
    func makeSearchModel() -> SearchModel {
        SearchModel(search: { [weak self] query, filter, cursor in
            guard let self else { return Page(items: [], nextCursor: nil) }
            return try await self.search(query, filter: filter, cursor: cursor)
        }, suggest: { [weak self] query in
            await self?.suggestions(for: query) ?? []
        }, recent: RecentSearchStore(database), searchesAsYouType: Self.isTV,
           subscriptions: SubscriptionStore(database), trending: TrendingStore(database))
    }

    func channel(_ id: ChannelID, cursor: String?) async throws -> ChannelPage {
        let router = self.router
        let page = try await router.perform(.channel) { try await $0.channel(id, cursor: cursor) }
        try? FeedStore(database).save(page.videos.items)
        return page
    }

    /// The person's region as they'd read it ("Portugal"), for Explore's heading.
    static var regionName: String? {
        Locale.current.region.flatMap { Locale.current.localizedString(forRegionCode: $0.identifier) }
    }

    /// Explore: fetch a category's trending list and cache it; Shorts stay in their own player.
    func refreshTrending(_ category: TrendingCategory = .all) async throws {
        let router = self.router
        let region = Locale.current.region?.identifier
        let capability: SourceCapabilities = category == .gaming ? .trendingCategories : .trending
        let videos = try await router.perform(capability) { try await $0.trending(region: region, category: category) }
        try TrendingStore(database).replace(with: videos.filter { !$0.isShort }, category: category)
    }

    /// Gaming: Invidious, or a PeerTube server on its own (its Gaming category).
    var supportsTrendingCategories: Bool {
        instances.contains { $0.kind == .invidious } || (hasPeerTube && !hasYouTube)
    }

    var hasPeerTube: Bool { instances.contains { $0.kind == .peerTube } }
    var hasYouTube: Bool { instances.contains { $0.kind.isYouTube } }

    /// The instances' trending list for the person's region (Home before subscriptions).
    func trending() async throws -> [VideoSummary] {
        let router = self.router
        let region = Locale.current.region?.identifier
        return try await router.perform(.trending) { try await $0.trending(region: region) }
    }

    /// Nil when no instance lists playlists (YT Zero alone): the channel shows no Playlists tab.
    var channelPlaylistsLoader: (@Sendable (ChannelID, String?) async throws -> Page<PlaylistSummary>)? {
        guard instances.contains(where: { $0.kind != .ytZero }) else { return nil }
        let router = self.router
        return { id, cursor in try await router.perform(.playlists) { try await $0.channelPlaylists(id, cursor: cursor) } }
    }

    func playlist(_ id: PlaylistID, cursor: String?) async throws -> PlaylistPage {
        let router = self.router
        let page = try await router.perform(.playlists) { try await $0.playlist(id, cursor: cursor) }
        try? FeedStore(database).save(page.videos.items)
        return page
    }

    var canLoadComments: Bool { !instances.isEmpty }

    func comments(_ id: VideoID, cursor: String?) async throws -> Page<Comment> {
        let router = self.router
        return try await router.perform(.comments) { try await $0.comments(for: id, cursor: cursor) }
    }

    func isSubscribed(_ id: ChannelID) -> Bool {
        ((try? SubscriptionStore(database).channels()) ?? []).contains { $0.id == id }
    }

    /// Writes through to a linked account (the source of truth), else the local store.
    func setSubscribed(_ channel: ChannelSummary, _ subscribed: Bool) async throws {
        // The account follows YouTube channels; PeerTube subscriptions stay local (ADR 0016).
        if let account, !channel.id.isPeerTube {
            if subscribed { try await account.follow(channel.id) } else { try await account.unfollow(channel.id) }
        }
        let store = SubscriptionStore(database)
        if subscribed { try store.subscribe([channel]) } else { try store.unsubscribe(channel.id) }
        hasSubscriptions = !((try? store.channels()) ?? []).isEmpty
        if subscribed { subscriptionsChanged([channel]) }
    }

    /// After instances change: refresh, and fill channels the cache has nothing for yet
    /// (batched feeds only carry recent uploads, and a channel new to the instance starts empty).
    func instancesChanged() {
        reloadSources()
        let refresher = self.refresher
        Task {
            try? await refresher.refresh()
            await backfillEmptyChannels()
        }
    }

    /// Batched feeds only carry recent uploads, and a channel new to the instance starts empty.
    /// Also fills channels still missing their avatar (imports carry none); once saved, they stay.
    private func backfillEmptyChannels() async {
        let refresher = self.refresher, database = self.database
        let channels = (try? SubscriptionStore(database).channels()) ?? []
        let needing = channels.filter { channel in
            channel.avatar == nil || ((try? FeedStore(database).videos(channel: channel.id, limit: 1)) ?? []).isEmpty
        }
        for channel in needing.prefix(50) {
            try? await refresher.backfill(channel.id)
        }
    }

    func refreshFeed(force: Bool) async throws {
        let refresher = self.refresher
        if force { try await refresher.refresh() } else { try await refresher.refreshIfStale() }
        refreshBranding()
        HomeSnapshotPublisher.publish(database)
        // Home's Shorts shelf (iPhone and iPad): a few channels' Shorts tabs per refresh.
        #if os(iOS)
        if !AppSettings.shared.hideShorts { Task { await refresher.refreshShorts() } }
        #endif
        Task { await refresher.refreshMissingAvatars() }
    }

    /// A channel's Shorts tab; cached, so they also reach Home's shelf.
    func channelShorts(_ id: ChannelID, cursor: String?) async throws -> Page<VideoSummary> {
        let router = self.router
        let page = try await router.perform(.channel) { try await $0.channelShorts(id, cursor: cursor) }
        if cursor == nil { try? FeedStore(database).saveNewestFirst(page.items) }
        return page
    }

    func subscriptionsChanged(_ added: [ChannelSummary]) {
        hasSubscriptions = !((try? SubscriptionStore(database).channels()) ?? []).isEmpty
        let refresher = self.refresher
        Task {
            try? await refresher.refresh()
            for channel in added.prefix(50) { try? await refresher.backfill(channel.id) }
        }
    }

    // MARK: Playback

    /// Home's muted preview of the featured video: Wi-Fi only (never cellular, a hotspot or Low
    /// Data Mode). The manifest it loads also makes tapping the video instant.
    func previewManifest(for id: VideoID) async -> StreamManifest? {
        let network = NetworkMonitor.shared.status
        guard !network.isExpensive, !network.isConstrained else { return nil }
        if let page = try? manifests.page(for: id) { return page.manifest }
        let router = self.router
        guard let page = try? await router.perform(.streams, { try await $0.watchPage(for: id) }) else { return nil }
        try? manifests.store(page)
        return page.manifest
    }

    /// Warm the manifest so a tap can start playing without a network round-trip.
    func prefetch(_ video: VideoSummary) {
        guard !prefetching.contains(video.id), (try? manifests.page(for: video.id)) == nil else { return }
        prefetching.insert(video.id)
        let router = self.router, manifests = self.manifests
        Task {
            defer { prefetching.remove(video.id) }
            let interval = Signpost.begin(.playbackManifest)
            defer { Signpost.end(interval) }
            if let page = try? await router.perform(.streams, { try await $0.watchPage(for: video.id) }) {
                try? manifests.store(page)
            }
        }
    }

    /// Cache, else the network; then plan and play. Returns the page for the Watch screen.
    /// - Parameter startAt: where to begin (Home's preview, continued); zero resumes as usual.
    func play(_ video: VideoSummary, mode: PlaybackMode = .video, surfaceHeight: Int,
              startAt: Duration = .zero) async throws -> WatchPage {
        let tap = Signpost.begin(.playbackTapToFirstFrame)
        prepareForPlayback()
        if upNext?.video.id != video.id { cancelUpNext() }   // Something else was picked.
        #if OFFLINE_DOWNLOADS
        // Downloaded audio plays without the network (the car, a flight).
        if mode == .audioOnly, let file = offlineAudio.localFile(for: video.id) {
            return await playOffline(video, file: file, tap: tap)
        }
        #endif
        let page: WatchPage
        if let cached = try? manifests.page(for: video.id) {
            page = cached
        } else {
            let interval = Signpost.begin(.playbackManifest)
            do {
                page = try await router.perform(.streams) { try await $0.watchPage(for: video.id) }
            } catch {
                #if OFFLINE_DOWNLOADS
                if let file = offlineAudio.localFile(for: video.id) { return await playOffline(video, file: file, tap: tap) }
                #endif
                throw error
            }
            Signpost.end(interval)
            try? manifests.store(page)
        }
        self.surfaceHeight = surfaceHeight
        manualQuality = nil
        let request = try plan(page, mode: mode, startAt: startAt)
        let item = NowPlayingItem(videoID: video.id, title: video.title, channelName: video.channelName,
                                  artworkURL: video.thumbnails.first?.url, chapters: page.manifest.chapters)
        currentPage = page
        await session.play(item, request)
        endWhenPlaying(tap)
        loadSkipSegments(for: video.id)
        applyCaptions(page.manifest.captions, for: video.id)
        return page
    }

    /// The surface, the data-saver limit for this network (or a manual pick) and the measured
    /// speed decide the stream (ADR 0007).
    func plan(_ page: WatchPage, mode: PlaybackMode, startAt: Duration) throws -> PlaybackRequest {
        let planner = PlaybackPlanner(selector: FormatSelector(capabilities: DecodeCapabilities()),
                                      preferredAudioLanguage: AppSettings.shared.audioLanguage)
        let network = NetworkMonitor.shared.status
        let maxHeight = VideoQuality.maxHeight(surface: surfaceHeight, manual: manualQuality,
                                               limit: AppSettings.shared.qualityLimit(onExpensiveNetwork: network.isExpensive),
                                               isConstrained: network.isConstrained)
        // A manual pick is what the person asked for, even if the connection seems slow.
        var request = try planner.request(for: page, mode: mode, maxDisplayHeight: maxHeight,
                                          throughputBitsPerSecond: manualQuality == nil ? session.stats?.throughputBitsPerSecond : nil,
                                          allowHDR: false, startAt: startAt)
        request.maxVideoHeight = maxHeight
        return request
    }

    /// From the player's Quality picker: nil goes back to automatic. Reloads at the same position.
    func selectQuality(_ height: Int?) async {
        guard height != manualQuality else { return }
        manualQuality = height
        guard session.mode == .video else { return }
        await replan()
    }

    /// From the player's Audio picker; remembered for the next videos (nil: the original).
    func selectAudio(_ language: String?) async {
        guard language != selectedAudioLanguage else { return }
        AppSettings.shared.audioLanguage = language
        await replan()
    }

    /// Plans the current video again and reloads it at the same position, in the same mode.
    private func replan() async {
        guard let page = currentPage, let item = session.item,
              let request = try? plan(page, mode: session.mode, startAt: session.position) else { return }
        await session.play(item, request)
        loadSkipSegments(for: item.videoID)
        loadSelectedCaption(for: item.videoID)
    }

    /// Stream URLs expire (YouTube's ~6 h, YT Zero's 15-minute tickets). When the engine reports
    /// `.streamExpired`, fetch fresh URLs and resume where playback stopped, at most once a minute.
    private func watchForExpiredStreams() {
        withObservationTracking { _ = session.state } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.session.state == .failed(.streamExpired) { await self.recoverExpiredStream() }
                self.watchForExpiredStreams()
            }
        }
    }

    private func recoverExpiredStream() async {
        guard let item = session.item else { return }
        let now = ContinuousClock.now
        if let last = lastRecovery, last.id == item.videoID, now - last.at < .seconds(60) { return }
        lastRecovery = (item.videoID, now)
        let position = session.position, mode = session.mode
        do {
            let page = try await router.perform(.streams) { try await $0.watchPage(for: item.videoID) }
            try? manifests.store(page)
            await session.play(item, try plan(page, mode: mode, startAt: position))
            loadSelectedCaption(for: item.videoID)
        } catch {
            // Leave the failure visible; the user can retry.
        }
    }

    /// Ends the tap-to-first-frame interval when playback starts (or fails).
    private func endWhenPlaying(_ interval: Signpost.Interval) {
        switch session.state {
        case .playing, .failed, .idle, .ended:
            Signpost.end(interval)
        default:
            withObservationTracking { _ = session.state } onChange: { [weak self] in
                Task { @MainActor in self?.endWhenPlaying(interval) }
            }
        }
    }
}

/// Resume positions in GRDB, mirrored to a linked YT Zero account so other devices see them.
final class LibraryResumeStore: ResumeStore, @unchecked Sendable {
    private let store: WatchStateStore
    // Written on the main actor when sources reload; read from save tasks. Guarded by `lock`.
    private var linkedAccount: (any SubscriptionAccount)?
    private let lock = NSLock()

    init(store: WatchStateStore) {
        self.store = store
    }

    var account: (any SubscriptionAccount)? {
        get { lock.withLock { linkedAccount } }
        set { lock.withLock { linkedAccount = newValue } }
    }

    func position(for id: VideoID) async -> Duration? {
        try? store.position(for: id)
    }

    func save(_ position: Duration, duration: Duration?, for id: VideoID) async {
        try? store.save(position, duration: duration, for: id)
        if let duration, let account {
            try? await account.saveProgress(position, duration: duration, for: id)
        }
    }
}
