import Foundation
import Testing
import Core
@testable import Library

private func video(_ id: String, channel: String = "UCaaaaaaaaaaaaaaaaaaaaaa", daysAgo: Double = 1,
                   duration: Duration? = .seconds(754), views: Int? = 1_200_000, short: Bool = false) -> VideoSummary {
    VideoSummary(id: VideoID(rawValue: id), title: "Video \(id)", channelID: ChannelID(rawValue: channel),
                 channelName: "Channel", duration: duration,
                 publishedAt: Date.now.addingTimeInterval(-daysAgo * 86_400), viewCount: views,
                 thumbnails: [], isShort: short)
}

private let channelA = ChannelSummary(id: ChannelID(rawValue: "UCaaaaaaaaaaaaaaaaaaaaaa"), name: "A", avatar: nil)
private let channelB = ChannelSummary(id: ChannelID(rawValue: "UCbbbbbbbbbbbbbbbbbbbbbb"), name: "B", avatar: nil)

struct FeedStoreTests {
    @Test func feedOnlyShowsSubscribedChannelsNewestFirst() throws {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([channelA])
        try FeedStore(db).save([video("old", daysAgo: 5), video("new", daysAgo: 1),
                                video("other", channel: channelB.id.rawValue)])
        let rows = try FeedStore(db).rows()
        #expect(rows.map(\.id.rawValue) == ["new", "old"])
    }

    @Test func rowsArePreformatted() throws {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([channelA])
        try FeedStore(db).save([video("v", duration: .seconds(3723))])
        let row = try #require(try FeedStore(db).rows().first)
        #expect(row.durationText == "1:02:03")
        #expect(row.detail.contains("·"))
        #expect(row.progress == nil)
    }

    @Test func shortsAreHiddenByDefault() throws {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([channelA])
        try FeedStore(db).save([video("short", short: true), video("long")])
        #expect(try FeedStore(db).rows().map(\.id.rawValue) == ["long"])
        #expect(try FeedStore(db).rows(.init(hideShorts: false)).count == 2)
    }

    @Test func aMissingDurationNeverErasesAKnownOne() throws {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([channelA])
        try FeedStore(db).save([video("v", duration: .seconds(600))])
        try FeedStore(db).save([video("v", duration: nil)])
        #expect(try FeedStore(db).rows().first?.durationText == "10:00")
    }

    @Test func unsubscribingLeavesATombstoneAndHidesTheChannel() throws {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([channelA])
        try FeedStore(db).save([video("v")])
        try SubscriptionStore(db).unsubscribe(channelA.id)
        #expect(try FeedStore(db).rows().isEmpty)
        let tombstones = try db.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM subscription WHERE isDeleted = 1") }
        #expect(tombstones == 1)
    }

    @Test func observationEmitsTheCachedFeedThenUpdates() async throws {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([channelA])
        try FeedStore(db).save([video("first")])
        var iterator = FeedStore(db).observe().makeAsyncIterator()
        #expect(try await iterator.next()?.map(\.id.rawValue) == ["first"])
        try FeedStore(db).save([video("second", daysAgo: 0.1)])
        #expect(try await iterator.next()?.map(\.id.rawValue) == ["second", "first"])
    }
}

struct WatchStateStoreTests {
    @Test func resumesFromTheSavedPosition() throws {
        let db = try AppDatabase.inMemory()
        let store = WatchStateStore(db)
        try store.save(.seconds(90), duration: .seconds(600), for: VideoID(rawValue: "v"))
        #expect(try store.position(for: VideoID(rawValue: "v")) == .seconds(90))
    }

    @Test func nearTheEndCountsAsFinishedAndStartsOver() throws {
        let db = try AppDatabase.inMemory()
        let store = WatchStateStore(db)
        try store.save(.seconds(590), duration: .seconds(600), for: VideoID(rawValue: "v"))
        #expect(try store.position(for: VideoID(rawValue: "v")) == nil)
    }

    @Test func progressShowsInTheFeed() throws {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([channelA])
        try FeedStore(db).save([video("v", duration: .seconds(600))])
        try WatchStateStore(db).save(.seconds(150), duration: .seconds(600), for: VideoID(rawValue: "v"))
        #expect(try FeedStore(db).rows().first?.progress == 0.25)
    }
}

struct ManifestCacheTests {
    private func page(_ id: String, expires: Date?) -> WatchPage {
        let summary = video(id)
        return WatchPage(details: VideoDetails(summary: summary, description: "", likeCount: nil, related: []),
                         manifest: StreamManifest(videoID: summary.id, videoStreams: [], audioStreams: [],
                                                  hlsURL: URL(string: "https://x.example/master.m3u8"),
                                                  chapters: [], expiresAt: expires))
    }

    @Test func returnsFreshEntriesOnly() throws {
        let cache = ManifestCache(try AppDatabase.inMemory())
        try cache.store(page("fresh", expires: .now.addingTimeInterval(3600)))
        try cache.store(page("stale", expires: .now.addingTimeInterval(60)))
        #expect(try cache.page(for: VideoID(rawValue: "fresh"))?.manifest.hlsURL != nil)
        #expect(try cache.page(for: VideoID(rawValue: "stale")) == nil)
    }
}

struct SubscriptionImportTests {
    @Test func readsGoogleTakeoutCSV() throws {
        let csv = """
        Channel Id,Channel Url,Channel Title
        UCaaaaaaaaaaaaaaaaaaaaaa,http://www.youtube.com/channel/UCaaaaaaaaaaaaaaaaaaaaaa,"Cooking, Mostly"
        UCbbbbbbbbbbbbbbbbbbbbbb,http://www.youtube.com/channel/UCbbbbbbbbbbbbbbbbbbbbbb,"The ""Best"" Channel"
        """
        let channels = try SubscriptionImport.parse(Data(csv.utf8))
        #expect(channels.map(\.name) == ["Cooking, Mostly", "The \"Best\" Channel"])
    }

    @Test func readsNewPipeJSON() throws {
        let json = #"{"app_version":"0.27","subscriptions":[{"service_id":0,"url":"https://www.youtube.com/channel/UCaaaaaaaaaaaaaaaaaaaaaa","name":"A"}]}"#
        #expect(try SubscriptionImport.parse(Data(json.utf8)) == [channelA])
    }

    @Test func readsPipedAndFreeTubeShapes() throws {
        let piped = #"{"format":"Piped","subscriptions":["UCaaaaaaaaaaaaaaaaaaaaaa","UCbbbbbbbbbbbbbbbbbbbbbb"]}"#
        #expect(try SubscriptionImport.parse(Data(piped.utf8)).count == 2)
        let freeTube = #"[{"name":"All","subscriptions":[{"id":"UCbbbbbbbbbbbbbbbbbbbbbb","name":"B"}]}]"#
        #expect(try SubscriptionImport.parse(Data(freeTube.utf8)) == [channelB])
    }

    @Test func readsOPMLAndRejectsGarbage() throws {
        let opml = """
        <opml version="1.1"><body><outline text="YouTube Subscriptions">
        <outline text="A" title="A" type="rss" xmlUrl="https://www.youtube.com/feeds/videos.xml?channel_id=UCaaaaaaaaaaaaaaaaaaaaaa"/>
        </outline></body></opml>
        """
        #expect(try SubscriptionImport.parse(Data(opml.utf8)) == [channelA])
        #expect(throws: SubscriptionImport.Failure.unrecognisedFormat) { try SubscriptionImport.parse(Data("hello".utf8)) }
    }
}
