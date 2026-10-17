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

struct BrandingStoreTests {
    @Test func brandedTitlesApplyOnlyWhenEnabled() throws {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([channelA])
        try FeedStore(db).save([video("v")])
        try BrandingStore(db).save([VideoID(rawValue: "v"): Branding(title: "Clearer title", thumbnailTime: 12)],
                                   lookedUp: [VideoID(rawValue: "v")])
        #expect(try FeedStore(db).rows().first?.title == "Video v")
        let branded = try FeedStore(db).rows(.init(brandedTitles: true, brandedThumbnails: true)).first
        #expect(branded?.title == "Clearer title")
        #expect(branded?.thumbnails.first?.url.host() == "dearrow-thumb.ajay.app")
    }

    @Test func lookupsAreRememberedIncludingMisses() throws {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([channelA])
        try FeedStore(db).save([video("hit"), video("miss")])
        let store = BrandingStore(db)
        #expect(Set(try store.videosNeedingLookup()) == [VideoID(rawValue: "hit"), VideoID(rawValue: "miss")])
        try store.save([VideoID(rawValue: "hit"): Branding(title: "T", thumbnailTime: nil)],
                       lookedUp: [VideoID(rawValue: "hit"), VideoID(rawValue: "miss")])
        #expect(try store.videosNeedingLookup().isEmpty)
    }
}

struct ListeningStoresTests {
    @Test func queueKeepsOrderAndFindsTheNext() throws {
        let db = try AppDatabase.inMemory()
        let queue = QueueStore(db)
        try queue.add(video("one"))
        try queue.add(video("two"))
        try queue.add(video("one"))     // Already queued: ignored.
        #expect(try queue.rows().map(\.id.rawValue) == ["one", "two"])
        #expect(try queue.next(after: VideoID(rawValue: "one"))?.id.rawValue == "two")
        #expect(try queue.next(after: VideoID(rawValue: "two")) == nil)
    }

    @Test func continueListeningShowsStartedUnfinishedVideos() throws {
        let db = try AppDatabase.inMemory()
        try FeedStore(db).save([video("started", duration: .seconds(600)), video("done", duration: .seconds(600))])
        try WatchStateStore(db).save(.seconds(120), duration: .seconds(600), for: VideoID(rawValue: "started"))
        try WatchStateStore(db).save(.seconds(599), duration: .seconds(600), for: VideoID(rawValue: "done"))
        #expect(try WatchStateStore(db).inProgress().map(\.id.rawValue) == ["started"])
    }

    @Test func evictionDropsWatchedThenLeastRecentlyPlayedButKeepsQueuedLast() throws {
        let db = try AppDatabase.inMemory()
        let downloads = DownloadStore(db)
        for id in ["watched", "old", "queued"] {
            try FeedStore(db).save([video(id, duration: .seconds(600))])
            try downloads.setState(.done, for: VideoID(rawValue: id), fileName: "\(id).m4a", bytes: 100)
        }
        try WatchStateStore(db).save(.seconds(599), duration: .seconds(600), for: VideoID(rawValue: "watched"))
        try QueueStore(db).add(video("queued"))
        let victims = try downloads.evictionCandidates(limitBytes: 150).map(\.videoID.rawValue)
        #expect(victims == ["watched", "old"])
        #expect(try downloads.watched().map(\.videoID.rawValue) == ["watched"])
    }
}

@Suite struct HistoryAndQueueOrderTests {
    private func video(_ id: String) -> VideoSummary {
        VideoSummary(id: VideoID(rawValue: id), title: id, channelID: ChannelID(rawValue: "UCaaaaaaaaaaaaaaaaaaaaaa"),
                     channelName: "A", duration: .seconds(600), publishedAt: .now, viewCount: 1, thumbnails: [])
    }

    @Test func historyIsMostRecentFirstAndRemovalsSync() throws {
        let db = try AppDatabase.inMemory()
        try FeedStore(db).save([video("a"), video("b")])
        let watch = WatchStateStore(db)
        try watch.save(.seconds(30), duration: .seconds(600), for: VideoID(rawValue: "a"))
        Thread.sleep(forTimeInterval: 0.05)     // Distinct save times: the order is "most recent first".
        try watch.save(.seconds(600), duration: .seconds(600), for: VideoID(rawValue: "b"))   // Finished, still history.
        #expect(try watch.history().map(\.id.rawValue) == ["b", "a"])

        try watch.removeFromHistory(VideoID(rawValue: "b"))
        #expect(try watch.history().map(\.id.rawValue) == ["a"])
        #expect(try SyncStore(db).pendingKeys().contains(SyncStore.Key(.watchState, "b")))   // The tombstone uploads.

        try watch.clearHistory()
        #expect(try watch.history().isEmpty)
    }

    @Test func historySearchMatchesEveryWordIgnoringCaseAndAccents() throws {
        let db = try AppDatabase.inMemory()
        func titled(_ id: String, _ title: String, channel: String) -> VideoSummary {
            VideoSummary(id: VideoID(rawValue: id), title: title, channelID: ChannelID(rawValue: "UCaaaaaaaaaaaaaaaaaaaaaa"),
                         channelName: channel, duration: .seconds(600), publishedAt: .now, viewCount: 1, thumbnails: [])
        }
        try FeedStore(db).save([titled("a", "Café da manhã", channel: "Cozinha"),
                                titled("b", "Blender Conference", channel: "Blender"),
                                titled("c", "Unwatched café", channel: "Cozinha")])
        let watch = WatchStateStore(db)
        try watch.save(.seconds(30), duration: .seconds(600), for: VideoID(rawValue: "a"))
        Thread.sleep(forTimeInterval: 0.05)
        try watch.save(.seconds(30), duration: .seconds(600), for: VideoID(rawValue: "b"))

        #expect(try watch.searchHistory("CAFE").map(\.id.rawValue) == ["a"])        // Not "c": never watched.
        #expect(try watch.searchHistory("cafe cozinha").map(\.id.rawValue) == ["a"])  // Title and channel words.
        #expect(try watch.searchHistory("blender").map(\.id.rawValue) == ["b"])
        #expect(try watch.searchHistory("cafe blender").isEmpty)
        #expect(try watch.searchHistory("  ").isEmpty)
        try watch.removeFromHistory(VideoID(rawValue: "a"))
        #expect(try watch.searchHistory("cafe").isEmpty)
    }

    @Test func queueKeepsTheDraggedOrder() throws {
        let db = try AppDatabase.inMemory()
        let queue = QueueStore(db)
        for id in ["a", "b", "c"] { try queue.add(video(id)) }
        try queue.reorder(["c", "a", "b"].map { VideoID(rawValue: $0) })
        #expect(try queue.rows().map(\.id.rawValue) == ["c", "a", "b"])
    }
}

@Suite struct NewUploadsTests {
    @Test func onlyVideosPublishedSinceTheLastLook() {
        let now = Date.now
        func row(_ id: String, hoursAgo: Double?, live: Bool = false) -> FeedRow {
            RowFormatter().row(VideoSummary(id: VideoID(rawValue: id), title: id,
                                            channelID: ChannelID(rawValue: "UCaaaaaaaaaaaaaaaaaaaaaa"), channelName: "A",
                                            duration: .seconds(60), publishedAt: hoursAgo.map { now.addingTimeInterval(-$0 * 3600) },
                                            viewCount: 1, thumbnails: [], isLive: live),
                               positionSeconds: nil, durationSeconds: nil)
        }
        let rows = [row("old", hoursAgo: 10), row("new", hoursAgo: 1), row("newer", hoursAgo: 0.5),
                    row("live", hoursAgo: 0.2, live: true), row("undated", hoursAgo: nil)]
        let picked = NewUploads.select(from: rows, since: now.addingTimeInterval(-2 * 3600))
        #expect(picked.map(\.id.rawValue) == ["newer", "new"])
    }
}

@Suite struct RecentSearchStoreTests {
    @Test func newestFirstDeduplicatedAndCapped() throws {
        let store = RecentSearchStore(try AppDatabase.inMemory())
        // No pauses: searches in the same millisecond still keep their order.
        try store.record("blender")
        try store.record("  swift  ")
        try store.record("Blender")
        #expect(try store.all() == ["Blender", "swift"])
        try store.record("   ")
        #expect(try store.all().count == 2)

        for index in 0..<30 { try store.record("query \(index)") }
        #expect(try store.all().count == RecentSearchStore.limit)

        try store.remove("query 29")
        #expect(try !store.all().contains("query 29"))
        try store.clear()
        #expect(try store.all().isEmpty)
    }
}

@Suite struct FeedHousekeepingTests {
    private let channel = ChannelSummary(id: ChannelID(rawValue: "UCaaaaaaaaaaaaaaaaaaaaaa"), name: "A", avatar: nil)
    private let other = ChannelSummary(id: ChannelID(rawValue: "UCbbbbbbbbbbbbbbbbbbbbbb"), name: "B", avatar: nil)

    @Test func aHiddenChannelLeavesHomeButStaysSubscribed() throws {
        let db = try AppDatabase.inMemory()
        let subscriptions = SubscriptionStore(db)
        try subscriptions.subscribe([channel, other])
        try FeedStore(db).save([video("a1", channel: channel.id.rawValue), video("b1", channel: other.id.rawValue)])
        try subscriptions.setHiddenFromHome(channel.id, true)
        #expect(try FeedStore(db).rows().map(\.id.rawValue) == ["b1"])
        #expect(try subscriptions.channels().count == 2)
        #expect(try subscriptions.hiddenFromHome() == [channel.id])
        // Synced: the pending change carries the flag.
        #expect(try SyncStore(db).change(for: SyncStore.Key(.subscription, channel.id.rawValue))?.values.isHiddenFromHome == true)

        try subscriptions.setHiddenFromHome(channel.id, false)
        #expect(try FeedStore(db).rows().count == 2)
    }

    @Test func subscribingAgainShowsTheChannelAgain() throws {
        let db = try AppDatabase.inMemory()
        let subscriptions = SubscriptionStore(db)
        try subscriptions.subscribe([channel])
        try subscriptions.setHiddenFromHome(channel.id, true)
        try subscriptions.unsubscribe(channel.id)
        try subscriptions.subscribe([channel])
        #expect(try subscriptions.hiddenFromHome().isEmpty)
    }

    @Test func markWatchedAndUnwatched() throws {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([channel])
        try FeedStore(db).save([video("a1", channel: channel.id.rawValue)])
        let store = WatchStateStore(db)
        try store.markWatched(VideoID(rawValue: "a1"), duration: .seconds(754))
        let row = try #require(try FeedStore(db).rows().first)
        #expect(row.isWatched && row.progress == 1)
        #expect(try store.position(for: VideoID(rawValue: "a1")) == nil)   // Plays from the start.
        #expect(try store.inProgress().isEmpty)

        try store.markUnwatched(VideoID(rawValue: "a1"))
        let again = try #require(try FeedStore(db).rows().first)
        #expect(!again.isWatched && again.progress == nil)
    }
}

private extension SyncStore.Values {
    var isHiddenFromHome: Bool {
        if case let .subscription(_, _, _, _, hidden) = self { return hidden }
        return false
    }
}
