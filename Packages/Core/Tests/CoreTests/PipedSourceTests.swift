import Foundation
import Testing
@testable import Core

/// Decoding against responses recorded from a real Piped instance (hosts sanitised).
struct PipedSourceTests {
    private func source(_ setup: (FixtureClient) -> Void) -> PipedSource {
        let client = FixtureClient()
        setup(client)
        return PipedSource(instance: instance(.piped), client: client)
    }

    @Test func searchFindsChannelsAndPlaylists() async throws {
        let piped = source {
            $0.on("filter=channels", fixture: "piped/search_channels.json")
            $0.on("filter=playlists", fixture: "piped/search_playlists.json")
        }
        let channels = try await piped.search("rick", filter: .channels, cursor: nil)
        guard case .channel(let channel) = try #require(channels.items.first) else {
            Issue.record("Not a channel")
            return
        }
        #expect(channel.name == "Rick Astley" && channel.id.rawValue == "UCuAXFkgsw1L7xaCfnd5JJOw")
        #expect(channel.avatar?.url.host() == "proxy.instance.example")

        let playlists = try await piped.search("rick", filter: .playlists, cursor: nil)
        guard case .playlist(let playlist) = try #require(playlists.items.first) else {
            Issue.record("Not a playlist")
            return
        }
        #expect(playlist.id.rawValue == "PL2MI040U_GXobmpXtTwBF7oHBGT5BETSD" && playlist.videoCount == 10)
        #expect(playlist.channelName == "RickAstleyVEVO")
    }

    @Test func channelShortsComeFromTheShortsTab() async throws {
        let client = FixtureClient()
        client.on("/channel/UCBJycsmduvYEL83R_U4JriQ", fixture: "piped/channel_shorts_tabs.json")
        client.on("/channels/tabs", fixture: "piped/channel_tab_shorts.json")
        let piped = PipedSource(instance: instance(.piped), client: client)
        let page = try await piped.channelShorts(ChannelID(rawValue: "UCBJycsmduvYEL83R_U4JriQ"), cursor: nil)
        #expect(page.items.count == 3)
        // The tab's uploaderUrl is "/channel/UC…/shorts"; the channel still comes through.
        #expect(page.items.allSatisfy { $0.isShort && $0.channelID.rawValue == "UCBJycsmduvYEL83R_U4JriQ" })
        #expect(page.items.allSatisfy { $0.publishedAt == nil })
        #expect(page.nextCursor != nil)
    }

    @Test func suggestions() async throws {
        let piped = source { $0.on("/suggestions", fixture: "piped/suggestions.json") }
        let suggestions = try await piped.suggestions(for: "blend")
        #expect(suggestions.contains("blender"))
    }

    @Test func channelPlaylistsGoThroughThePlaylistsTabAndPage() async throws {
        let client = FixtureClient()
        client.on("/channel/UCSMOQeBJ2RAnuFungnQOxLg", fixture: "piped/channel_playlists_tabs.json")
        client.on("/channels/tabs", fixture: "piped/channel_tab_playlists.json")
        let piped = PipedSource(instance: instance(.piped), client: client)
        let channel = ChannelID(rawValue: "UCSMOQeBJ2RAnuFungnQOxLg")
        let page = try await piped.channelPlaylists(channel, cursor: nil)
        #expect(page.items.count == 3)
        let first = try #require(page.items.first)
        #expect(first.id.rawValue == "PLa1F2ddGya_-I9y1nXALrBqrZNdlUE012")
        #expect(first.title == "Blender Conference 2026" && first.videoCount == 94 && first.channelName == "Blender")
        #expect(first.thumbnails.first?.url.host() == "proxy.instance.example")

        // The next page sends the tab's data again, with Piped's nextpage, and skips the channel.
        let cursor = try #require(page.nextCursor)
        _ = try await piped.channelPlaylists(channel, cursor: cursor)
        let last = try #require(client.requests.last?.url)
        let items = URLComponents(url: last, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(last.path().hasSuffix("/channels/tabs"))
        #expect(items.contains { $0.name == "data" } && items.contains { $0.name == "nextpage" })
        #expect(client.requestedPaths.filter { $0.contains("/channel/") }.count == 1)
    }

    @Test func watchPageMapsAdaptiveStreamsAndSkipsMuxed() async throws {
        let piped = source { $0.on("/streams/dQw4w9WgXcQ", fixture: "piped/streams.json") }
        let page = try await piped.watchPage(for: VideoID(rawValue: "dQw4w9WgXcQ"))
        let manifest = page.manifest

        // itag 18 is muxed progressive and is dropped; 137 (H.264 mp4) and 248 (VP9 webm) remain.
        #expect(manifest.videoStreams.map(\.itag) == [137, 248])
        let h264 = try #require(manifest.videoStreams.first)
        #expect(h264.codec == .h264 && h264.codecs == "avc1.640028" && h264.container == .mp4)
        #expect(h264.width == 1920 && h264.height == 1080)
        #expect(h264.initRange == ByteRange(start: 0, end: 741))
        #expect(h264.indexRange?.end == 1229)
        #expect(manifest.videoStreams[1].codec == .vp9 && manifest.videoStreams[1].container == .webm)

        #expect(manifest.audioStreams.map(\.codec) == [.aac, .aac, .opus])
        #expect(manifest.audioStreams.allSatisfy { $0.isOriginal })
        #expect(manifest.expiresAt != nil)

        // Captions are rewritten to request WebVTT.
        #expect(manifest.captions.count == 3)
        #expect(manifest.captions.allSatisfy { $0.url.query?.contains("fmt=vtt") == true })

        // Scrubbing previews come through the instance's proxy.
        #expect(manifest.storyboards.map(\.frameWidth) == [80, 160])
        #expect(manifest.storyboards.allSatisfy { $0.pages.allSatisfy { $0.host() == "proxy.instance.example" } })

        #expect(page.details.summary.duration == .seconds(213))
        #expect(page.details.summary.channelID.rawValue.hasPrefix("UC"))
        #expect(page.details.summary.publishedAt == Date(timeIntervalSince1970: 1_256_453_853))
        #expect(!page.details.description.contains("<br>"))
    }

    @Test func liveStreamHasNoAdaptiveStreamsButHLS() async throws {
        let piped = source { $0.on("/streams/live", fixture: "piped/streams_live.json") }
        let page = try await piped.watchPage(for: VideoID(rawValue: "live"))
        #expect(page.details.summary.isLive)
        #expect(page.manifest.videoStreams.isEmpty)
        #expect(page.manifest.hlsURL != nil)
    }

    @Test func searchReturnsVideosAndAnOpaqueCursor() async throws {
        let piped = source { $0.on("/search", fixture: "piped/search.json") }
        let page = try await piped.search("rick", cursor: nil)
        #expect(page.items.map(\.id.rawValue) == ["6t6y88njdH4", "C2xel6q0yao", "eYuUAGXN0KM"])
        #expect(page.nextCursor?.hasPrefix("{") == true)
    }

    @Test func searchTreatsTheStringNullAsTheEnd() {
        #expect(PipedSource.cursor("null") == nil)
        #expect(PipedSource.cursor(nil) == nil)
        #expect(PipedSource.cursor("{\"url\":1}") == "{\"url\":1}")
    }

    @Test func feedIsNewestFirstWithExactDates() async throws {
        let piped = source { $0.on("/feed/unauthenticated", fixture: "piped/feed.json") }
        let feed = try await piped.feed(for: [ChannelID(rawValue: "UCuAXFkgsw1L7xaCfnd5JJOw")])
        #expect(feed.count == 3)
        #expect(feed.first?.publishedAt == Date(timeIntervalSince1970: 1_792_152_409.632))
        let dates = feed.compactMap(\.publishedAt)
        #expect(dates == dates.sorted(by: >))
    }

    @Test func feedChunksLongChannelLists() async throws {
        let client = FixtureClient()
        client.on("/feed/unauthenticated", body: Data("[]".utf8))
        let piped = PipedSource(instance: instance(.piped), client: client)
        let channels = (0..<120).map { ChannelID(rawValue: "UC\($0)") }
        _ = try await piped.feed(for: channels)
        #expect(client.requestedPaths.count == 3)
    }

    @Test func commentsAreDecodedAsPlainText() async throws {
        let piped = source { $0.on("/comments/x", fixture: "piped/comments.json") }
        let page = try await piped.comments(for: VideoID(rawValue: "x"), cursor: nil)
        #expect(page.items.count == 3)
        #expect(page.items[1].text == "Today it's the day, we Rickroll ourselves.")
        #expect(page.items.allSatisfy { $0.repliesCursor != nil })
    }

    @Test(arguments: [
        ("piped/errors/streams_private.json", "unavailable"),
        ("piped/errors/streams_badid.json", "unavailable"),
    ])
    func classifiesJavaExceptionsFromErrorBodies(_ fixture: String, _ expected: String) {
        let error = PipedSource.mapError(status: 500, body: FixtureClient.fixture(fixture))
        if case .unavailable = error { #expect(expected == "unavailable") } else { Issue.record("Got \(error)") }
    }

    @Test func upstreamBlockingIsRetryableElsewhere() {
        let body = Data(#"{"error":"org.schabi.newpipe.extractor.exceptions.SignInConfirmNotBotException: Sign in","message":null}"#.utf8)
        let error = PipedSource.mapError(status: 500, body: body)
        guard case .blockedUpstream = error else { Issue.record("Got \(error)"); return }
        #expect(error.isRetryableElsewhere)
    }
}
