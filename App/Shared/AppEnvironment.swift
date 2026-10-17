import SwiftUI
import Core
import Library
import Playback
import DesignSystem
import PlaybackUI
import InstancesFeature
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
    private(set) var instances: [InstanceConfig] = []
    private(set) var hasSubscriptions = false
    @ObservationIgnored private(set) var router = InstanceRouter(sources: [])
    @ObservationIgnored private(set) var refresher: FeedRefresher
    @ObservationIgnored private(set) var account: (any SubscriptionAccount)?
    @ObservationIgnored private let manifests: ManifestCache
    @ObservationIgnored private let resumeStore: LibraryResumeStore
    @ObservationIgnored private var prefetching: Set<VideoID> = []
    @ObservationIgnored private var lastRecovery: (id: VideoID, at: ContinuousClock.Instant)?
    @ObservationIgnored var surfaceHeight = 1080
    /// The page now playing; audio mode, PiP, AirPlay and casting re-plan from it.
    @ObservationIgnored var currentPage: WatchPage?
    @ObservationIgnored var nowPlaying: NowPlayingController?
    @ObservationIgnored let community = CommunityServices()
    /// CloudKit sync of subscriptions and watch state, when configured and no YT Zero account
    /// owns them (ADR 0002, ADR 0004).
    @ObservationIgnored private(set) var cloudSync: CloudSync?
    #if os(iOS)
    // iPhone and iPad only: PiP handoff, Cast sender, AirPlay switching, MetricKit (none on tvOS).
    @ObservationIgnored let pictureInPicture = PictureInPictureHandoff()
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
    /// without the file picker, which UI tests can't drive. `-SeedDemoFeed N`: N cached videos.
    private static func forUITests() -> AppEnvironment? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UITestFreshStart"), let database = try? AppDatabase.inMemory() else { return nil }
        if let index = arguments.firstIndex(of: "-SeedSubscriptions"), arguments.indices.contains(index + 1) {
            let channels = arguments[index + 1].split(separator: ",").map {
                ChannelSummary(id: ChannelID(rawValue: String($0)), name: "", avatar: nil)
            }
            try? SubscriptionStore(database).subscribe(channels)
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
        for instance in instances {
            switch instance.kind {
            case .piped:
                sources.append(PipedSource(instance: instance))
            case .invidious:
                sources.append(InvidiousSource(instance: instance))
            case .ytZero:
                guard let token = secrets.secret(for: AddInstanceModel.tokenKey(for: instance.id)) else { continue }
                let source = YTZeroSource(instance: instance, token: token)
                if let host = instance.apiURL.host() { imageTokens[host] = token }
                linkedAccount = linkedAccount ?? source
            }
        }
        if let linkedAccount { sources.append(linkedAccount) }

        let router = InstanceRouter(sources: sources)
        self.router = router
        account = linkedAccount
        resumeStore.account = linkedAccount
        refresher = FeedRefresher(mode: linkedAccount.map { .account($0) } ?? .local(router), database: database)
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
    /// entitlement; CloudKit traps without it) and no linked account.
    private func updateCloudSync() {
        let container = Bundle.main.object(forInfoDictionaryKey: "CloudKitContainer") as? String ?? ""
        if account == nil, !container.isEmpty, !ProcessInfo.processInfo.arguments.contains("-UITestFreshStart") {
            guard cloudSync == nil else { return }
            let sync = CloudSync(containerIdentifier: container, database: database)
            cloudSync = sync
            Task { await sync.start() }
        } else if let sync = cloudSync {
            cloudSync = nil
            Task { await sync.stop() }
        }
    }

    /// Foreground: pull other devices' changes, then fill channels that arrived without videos.
    func syncNow() async {
        guard let cloudSync else { return }
        await cloudSync.syncNow()
        hasSubscriptions = !((try? SubscriptionStore(database).channels()) ?? []).isEmpty
        await backfillEmptyChannels()
    }

    /// After the first frame: start mpv's core and open connections to the instances, so the
    /// first tap pays for neither (tap-to-first-frame budget).
    func warmUp() {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            session.prewarm()
            _ = await router.checkHealth()
        }
    }

    // MARK: Browsing

    func search(_ query: String, cursor: String?) async throws -> Page<VideoSummary> {
        let router = self.router
        return try await router.perform(.search) { try await $0.search(query, cursor: cursor) }
    }

    func channel(_ id: ChannelID, cursor: String?) async throws -> ChannelPage {
        let router = self.router
        let page = try await router.perform(.channel) { try await $0.channel(id, cursor: cursor) }
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
        if let account {
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
    private func backfillEmptyChannels() async {
        let refresher = self.refresher, database = self.database
        let channels = (try? SubscriptionStore(database).channels()) ?? []
        for channel in channels.prefix(50) where ((try? FeedStore(database).videos(channel: channel.id, limit: 1)) ?? []).isEmpty {
            try? await refresher.backfill(channel.id)
        }
    }

    func refreshFeed(force: Bool) async throws {
        let refresher = self.refresher
        if force { try await refresher.refresh() } else { try await refresher.refreshIfStale() }
        refreshBranding()
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
    func play(_ video: VideoSummary, mode: PlaybackMode = .video, surfaceHeight: Int) async throws -> WatchPage {
        let tap = Signpost.begin(.playbackTapToFirstFrame)
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
        let request = try plan(page, mode: mode, startAt: .zero)
        let item = NowPlayingItem(videoID: video.id, title: video.title, channelName: video.channelName,
                                  artworkURL: video.thumbnails.first?.url, chapters: page.manifest.chapters)
        currentPage = page
        await session.play(item, request)
        endWhenPlaying(tap)
        loadSkipSegments(for: video.id)
        return page
    }

    func plan(_ page: WatchPage, mode: PlaybackMode, startAt: Duration) throws -> PlaybackRequest {
        let planner = PlaybackPlanner(selector: FormatSelector(capabilities: DecodeCapabilities()),
                                      preferredAudioLanguage: nil)
        return try planner.request(for: page, mode: mode, maxDisplayHeight: surfaceHeight,
                                   throughputBitsPerSecond: session.stats?.throughputBitsPerSecond,
                                   allowHDR: false, startAt: startAt)
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
