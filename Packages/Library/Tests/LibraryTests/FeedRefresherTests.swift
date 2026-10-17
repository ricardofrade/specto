import Foundation
import Testing
import Core
@testable import Library

private struct StubRouter: SourceRouting {
    let videos: [VideoSummary]
    let requested: LockedBox<[[ChannelID]]>

    func perform<T: Sendable>(_ capability: SourceCapabilities,
                              _ operation: @Sendable (any VideoSource) async throws -> T) async throws -> T {
        try await operation(StubSource(videos: videos, requested: requested))
    }
}

private struct StubSource: VideoSource {
    let instance = InstanceConfig(kind: .piped, displayName: "stub", apiURL: URL(string: "https://stub.example")!)
    let capabilities: SourceCapabilities = [.subscriptions]
    let videos: [VideoSummary]
    let requested: LockedBox<[[ChannelID]]>

    func feed(for channels: [ChannelID]) async throws -> [VideoSummary] {
        requested.mutate { $0.append(channels) }
        return videos
    }

    func healthCheck() async -> HealthSample { HealthSample(instanceID: instance.id, isHealthy: true, latency: nil) }

    /// Two Shorts per channel, newest first, undated like the real tabs.
    func channelShorts(_ id: ChannelID, cursor: String?) async throws -> Page<VideoSummary> {
        requested.mutate { $0.append([id]) }
        return Page(items: (1...2).map { n in
            VideoSummary(id: VideoID(rawValue: "\(id.rawValue.suffix(3))-short\(n)"), title: "Short \(n)", channelID: id,
                         channelName: "C", duration: nil, publishedAt: nil, viewCount: nil, thumbnails: [], isShort: true)
        }, nextCursor: nil)
    }

    func channel(_ id: ChannelID, cursor: String?) async throws -> ChannelPage {
        ChannelPage(id: id, name: "Blender", avatar: Thumbnail(url: URL(string: "https://stub.example/avatar.jpg")!, width: 88, height: 88),
                    videos: Page(items: videos, nextCursor: nil))
    }
}

@Suite struct BackfillTests {
    @Test func backfillFillsTheChannelsNameAndAvatar() async throws {
        let db = try AppDatabase.inMemory()
        let channel = ChannelID(rawValue: "UCaaaaaaaaaaaaaaaaaaaaaa")
        try SubscriptionStore(db).subscribe([ChannelSummary(id: channel, name: "", avatar: nil)])   // As a CSV import leaves it.
        let refresher = FeedRefresher(mode: .local(StubRouter(videos: [], requested: LockedBox([]))), database: db)
        try await refresher.backfill(channel)
        let saved = try #require(try SubscriptionStore(db).channels().first)
        #expect(saved.name == "Blender")
        #expect(saved.avatar?.url.absoluteString == "https://stub.example/avatar.jpg")
    }

    @Test func missingAvatarsFillAFewChannelsPerPass() async throws {
        let db = try AppDatabase.inMemory()
        let channels = (0..<5).map { ChannelSummary(id: ChannelID(rawValue: "UC\($0)aaaaaaaaaaaaaaaaaaaaa"), name: "", avatar: nil) }
        try SubscriptionStore(db).subscribe(channels)
        let refresher = FeedRefresher(mode: .local(StubRouter(videos: [], requested: LockedBox([]))), database: db)
        func withAvatar() throws -> Int { try SubscriptionStore(db).channels().filter { $0.avatar != nil }.count }

        await refresher.refreshMissingAvatars(channelsPerPass: 3)
        #expect(try withAvatar() == 3)
        await refresher.refreshMissingAvatars(channelsPerPass: 3)
        #expect(try withAvatar() == 5)
    }
}

private struct StubAccount: SubscriptionAccount {
    let channels: [ChannelSummary]
    let entries: [AccountVideo]

    func subscriptions() async throws -> [ChannelSummary] { channels }
    func follow(_ channel: ChannelID) async throws {}
    func unfollow(_ channel: ChannelID) async throws {}
    func accountFeed(page: Int) async throws -> Page<AccountVideo> { Page(items: page == 0 ? entries : [], nextCursor: nil) }
    func saveProgress(_ position: Duration, duration: Duration, for id: VideoID) async throws {}
    func setWatched(_ watched: Bool, for id: VideoID) async throws {}
}

final class LockedBox<Value: Sendable>: @unchecked Sendable {
    // Guarded by `lock`.
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func mutate(_ change: (inout Value) -> Void) { lock.withLock { change(&value) } }
    var current: Value { lock.withLock { value } }
}

private let channel = ChannelSummary(id: ChannelID(rawValue: "UCaaaaaaaaaaaaaaaaaaaaaa"), name: "A", avatar: nil)

private func video(_ id: String) -> VideoSummary {
    VideoSummary(id: VideoID(rawValue: id), title: id, channelID: channel.id, channelName: "A",
                 duration: .seconds(300), publishedAt: .now, viewCount: 1, thumbnails: [])
}

struct FeedRefresherTests {
    @Test func localModeFetchesTheSubscribedChannelsAndCachesTheFeed() async throws {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([channel])
        let requested = LockedBox<[[ChannelID]]>([])
        let refresher = FeedRefresher(mode: .local(StubRouter(videos: [video("v1")], requested: requested)), database: db)

        try await refresher.refresh()

        #expect(requested.current == [[channel.id]])
        #expect(try FeedStore(db).rows().map(\.id.rawValue) == ["v1"])
        #expect(try RefreshLog(db).isStale(FeedRefresher.feedResource, after: 60) == false)
    }

    @Test func refreshIfStaleSkipsARecentRefresh() async throws {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([channel])
        let requested = LockedBox<[[ChannelID]]>([])
        let refresher = FeedRefresher(mode: .local(StubRouter(videos: [], requested: requested)), database: db)
        try await refresher.refresh()
        try await refresher.refreshIfStale(maxAge: 600)
        #expect(requested.current.count == 1)
    }

    @Test func accountModeMirrorsSubscriptionsFeedAndPositions() async throws {
        let db = try AppDatabase.inMemory()
        let stale = ChannelSummary(id: ChannelID(rawValue: "UCbbbbbbbbbbbbbbbbbbbbbb"), name: "Gone", avatar: nil)
        try SubscriptionStore(db).subscribe([stale])
        let account = StubAccount(channels: [channel],
                                  entries: [AccountVideo(video: video("v1"), resumePosition: .seconds(60), isWatched: false)])
        try await FeedRefresher(mode: .account(account), database: db).refresh()

        #expect(try SubscriptionStore(db).channels() == [channel])
        #expect(try FeedStore(db).rows().map(\.id.rawValue) == ["v1"])
        #expect(try WatchStateStore(db).position(for: VideoID(rawValue: "v1")) == .seconds(60))
    }
}

@Suite struct ShortsRotationTests {
    @Test func visitsAFewChannelsPerPassSkippingHiddenOnes() async throws {
        let db = try AppDatabase.inMemory()
        let channels = (0..<5).map { ChannelSummary(id: ChannelID(rawValue: "UCchannel\($0)"), name: "C\($0)", avatar: nil) }
        try SubscriptionStore(db).subscribe(channels)
        try SubscriptionStore(db).setHiddenFromHome(channels[4].id, true)
        let requested = LockedBox<[[ChannelID]]>([])
        let refresher = FeedRefresher(mode: .local(StubRouter(videos: [], requested: requested)), database: db)

        await refresher.refreshShorts(channelsPerPass: 3)
        #expect(requested.current.count == 3)
        await refresher.refreshShorts(channelsPerPass: 3)
        #expect(requested.current.count == 4)        // Only one channel was still due.
        await refresher.refreshShorts(channelsPerPass: 3)
        #expect(requested.current.count == 4)        // Everything is fresh.
        #expect(!requested.current.flatMap { $0 }.contains(channels[4].id))

        var shorts = FeedStore.Options()
        shorts.onlyShorts = true
        let rows = try FeedStore(db).rows(shorts)
        #expect(rows.count == 8 && rows.allSatisfy(\.isShort))
        // Newest first within a channel, though undated.
        let first = try #require(rows.firstIndex { $0.title == "Short 1" && $0.channelID == rows[0].channelID })
        let second = try #require(rows.firstIndex { $0.title == "Short 2" && $0.channelID == rows[0].channelID })
        #expect(first < second)
        // And never in the main feed.
        #expect(try FeedStore(db).rows().isEmpty)
    }
}
