import Foundation
import Core

/// Refreshes the cached feed: screens observe `FeedStore` and render immediately; this brings
/// it up to date from the network (stale-while-revalidate). Concurrent requests share one refresh.
public actor FeedRefresher {
    /// Where subscriptions live (ADR 0002).
    public enum Mode: Sendable {
        /// Subscriptions in GRDB (synced via CloudKit later); videos from the instances.
        case local(any SourceRouting)
        /// A linked account (YT Zero) owns YouTube subscriptions, feed and watch state; we mirror
        /// it. PeerTube channels stay local and come from the instances (`router`, ADR 0016).
        case account(any SubscriptionAccount, router: (any SourceRouting)? = nil)
    }

    /// The instances, in either mode: PeerTube content always comes from them.
    private var router: (any SourceRouting)? {
        switch mode {
        case .local(let router): router
        case .account(_, let router): router
        }
    }

    public static let feedResource = "feed"

    private let mode: Mode
    private let subscriptions: SubscriptionStore
    private let feed: FeedStore
    private let watchState: WatchStateStore
    private let log: RefreshLog
    private var inFlight: Task<Void, Error>?

    public init(mode: Mode, database: AppDatabase) {
        self.mode = mode
        subscriptions = SubscriptionStore(database)
        feed = FeedStore(database)
        watchState = WatchStateStore(database)
        log = RefreshLog(database)
    }

    /// Refresh unless the last one is recent. Call on launch, foreground and tab return.
    public func refreshIfStale(maxAge: TimeInterval = 15 * 60) async throws {
        guard try log.isStale(Self.feedResource, after: maxAge) else { return }
        try await refresh()
    }

    /// Pull-to-refresh and post-mutation re-fetch.
    public func refresh() async throws {
        if let inFlight { return try await inFlight.value }
        let task = Task { try await performRefresh() }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }

    /// Fills a newly subscribed channel's history, since batched feeds only carry recent uploads.
    public func backfill(_ channel: ChannelID) async throws {
        // With an account linked, it fills YouTube channels itself; PeerTube's are still ours.
        if case .account = mode, !channel.isPeerTube { return }
        guard let router else { return }
        let page = try await router.perform(.channel) { try await $0.channel(channel, cursor: nil) }
        try feed.save(page.videos.items)
        // Imports (Takeout CSV) carry no avatar or proper name; the channel page has both.
        if try subscriptions.channels().contains(where: { $0.id == channel }) {
            try subscriptions.subscribe([ChannelSummary(id: channel, name: page.name, avatar: page.avatar)])
        }
    }

    /// Subscription feeds leave Shorts out, so Home's Shorts shelf is filled from channels'
    /// Shorts tabs: a few channels per call, each at most every `maxAge`, the longest-waiting
    /// first. Bounded on purpose: each channel costs the instance one or two requests.
    public func refreshShorts(channelsPerPass: Int = 3, maxAge: TimeInterval = 12 * 3600) async {
        guard case .local(let router) = mode, let channels = try? subscriptions.channels() else { return }
        let hidden = (try? subscriptions.hiddenFromHome()) ?? []
        let due = channels.filter { !hidden.contains($0.id) && !$0.id.isPeerTube }   // PeerTube has no Shorts.
            .map { ($0.id, (try? log.lastRefresh(Self.shortsResource($0.id))) ?? nil) }
            .filter { _, last in last.map { $0 < Date.now.addingTimeInterval(-maxAge) } ?? true }
            .sorted { ($0.1 ?? .distantPast) < ($1.1 ?? .distantPast) }
            .prefix(channelsPerPass)
        for (channel, _) in due {
            // Marked even on failure, so a channel without Shorts isn't retried every refresh.
            try? log.markRefreshed(Self.shortsResource(channel))
            guard let page = try? await router.perform(.channel, { try await $0.channelShorts(channel, cursor: nil) })
            else { continue }
            try? feed.saveNewestFirst(Array(page.items.prefix(12)))
        }
    }

    static func shortsResource(_ channel: ChannelID) -> String { "shorts/\(channel.rawValue)" }

    /// Channels still without an avatar (an import whose backfill failed or never ran) get
    /// theirs from the channel page: a few per call, each tried at most every `retryAfter`.
    public func refreshMissingAvatars(channelsPerPass: Int = 4, retryAfter: TimeInterval = 86_400) async {
        guard router != nil, let channels = try? subscriptions.channels() else { return }
        let due = channels.filter { channel in
            if case .account = mode, !channel.id.isPeerTube { return false }   // The account's to fill.
            guard channel.avatar == nil else { return false }
            let last = (try? log.lastRefresh(Self.avatarResource(channel.id))) ?? nil
            return last.map { $0 < Date.now.addingTimeInterval(-retryAfter) } ?? true
        }.prefix(channelsPerPass)
        for channel in due {
            try? log.markRefreshed(Self.avatarResource(channel.id))
            try? await backfill(channel.id)
        }
    }

    static func avatarResource(_ channel: ChannelID) -> String { "avatar/\(channel.rawValue)" }

    private func performRefresh() async throws {
        switch mode {
        case .local(let router):
            let channels = try subscriptions.channels().map(\.id)
            guard !channels.isEmpty else { break }
            // YouTube's channels in one batch; PeerTube's per server (ADR 0016).
            let youTube = channels.filter { !$0.isPeerTube }
            var videos: [VideoSummary] = []
            if !youTube.isEmpty {
                videos += try await router.perform(.subscriptions) { try await $0.feed(for: youTube) }
            }
            videos += try await peerTubeFeed(channels, router: router, strict: youTube.isEmpty)
            try feed.save(videos)
        case .account(let account, let router):
            async let channels = account.subscriptions()
            async let entries = accountFeed(account, pages: 3)
            let (list, videos) = try await (channels, entries)
            try subscriptions.replaceAll(with: list)   // YouTube's only: PeerTube channels stay.
            try feed.save(videos.map(\.video))
            try watchState.merge(videos)
            if let router {
                try feed.save(await peerTubeFeed(try subscriptions.channels().map(\.id), router: router, strict: false))
            }
        }
        try log.markRefreshed(Self.feedResource)
        try feed.prune()
    }

    /// PeerTube channels' latest, per server. `strict`: the only feed there is, so a lone
    /// server's failure is the refresh's; otherwise one unreachable server is skipped.
    private func peerTubeFeed(_ channels: [ChannelID], router: any SourceRouting, strict: Bool) async throws -> [VideoSummary] {
        let servers = Dictionary(grouping: channels.filter(\.isPeerTube)) { $0.peerTube?.host ?? "" }
        var videos: [VideoSummary] = []
        for group in servers.values {
            if strict, servers.count == 1 {
                videos += try await router.perform(.subscriptions) { try await $0.feed(for: group) }
            } else if let more = try? await router.perform(.subscriptions, { try await $0.feed(for: group) }) {
                videos += more
            }
        }
        return videos
    }

    private func accountFeed(_ account: any SubscriptionAccount, pages: Int) async throws -> [AccountVideo] {
        var all: [AccountVideo] = []
        for page in 0..<pages {
            let result = try await account.accountFeed(page: page)
            all += result.items
            if result.nextCursor == nil { break }
        }
        return all
    }
}
