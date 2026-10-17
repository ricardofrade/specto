import Foundation
import Core

/// Refreshes the cached feed: screens observe `FeedStore` and render immediately; this brings
/// it up to date from the network (stale-while-revalidate). Concurrent requests share one refresh.
public actor FeedRefresher {
    /// Where subscriptions live (ADR 0002).
    public enum Mode: Sendable {
        /// Subscriptions in GRDB (synced via CloudKit later); videos from the instances.
        case local(any SourceRouting)
        /// A linked account (YT Zero) owns subscriptions, feed and watch state; we mirror it.
        case account(any SubscriptionAccount)
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
        guard case .local(let router) = mode else { return }
        let page = try await router.perform(.channel) { try await $0.channel(channel, cursor: nil) }
        try feed.save(page.videos.items)
        // Imports (Takeout CSV) carry no avatar or proper name; the channel page has both.
        if try subscriptions.channels().contains(where: { $0.id == channel }) {
            try subscriptions.subscribe([ChannelSummary(id: channel, name: page.name, avatar: page.avatar)])
        }
    }

    private func performRefresh() async throws {
        switch mode {
        case .local(let router):
            let channels = try subscriptions.channels().map(\.id)
            guard !channels.isEmpty else { break }
            let videos = try await router.perform(.subscriptions) { try await $0.feed(for: channels) }
            try feed.save(videos)
        case .account(let account):
            async let channels = account.subscriptions()
            async let entries = accountFeed(account, pages: 3)
            let (list, videos) = try await (channels, entries)
            try subscriptions.replaceAll(with: list)
            try feed.save(videos.map(\.video))
            try watchState.merge(videos)
        }
        try log.markRefreshed(Self.feedResource)
        try feed.prune()
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
