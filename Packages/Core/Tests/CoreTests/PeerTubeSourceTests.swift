import Foundation
import Testing
@testable import Core

/// Decoding against responses recorded from a public PeerTube server (host sanitised), and the
/// routing that keeps PeerTube and YouTube content apart (ADR 0016).
struct PeerTubeSourceTests {
    private let uuid = "7ad3cbee-fe5f-41c2-93ea-b108986939f4"
    private let handle = "blender_open_movies@instance.example"

    private func source(general: Bool = true, _ setup: (FixtureClient) -> Void) -> PeerTubeSource {
        let client = FixtureClient()
        setup(client)
        return PeerTubeSource(instance: instance(.peerTube), servesGeneralQueries: general, client: client)
    }

    @Test func idsCarryTheServer() {
        let id = VideoID.peerTube(host: "instance.example", uuid: uuid)
        #expect(id.rawValue == "pt:instance.example:\(uuid)")
        #expect(id.peerTube?.host == "instance.example" && id.peerTube?.uuid == uuid)
        #expect(VideoID(rawValue: "dQw4w9WgXcQ").peerTube == nil)
        #expect(ChannelID.peerTube(host: "instance.example", handle: handle).peerTube?.handle == handle)
        #expect(id.webURL?.absoluteString == "https://instance.example/w/\(uuid)")
        #expect(VideoID(rawValue: "dQw4w9WgXcQ").webURL?.host() == "www.youtube.com")
    }

    @Test func trendingListsTheServersVideos() async throws {
        let pt = source { $0.on("/api/v1/videos", fixture: "peertube/videos.json") }
        let videos = try await pt.trending(region: "PT", category: .all)
        #expect(videos.count == 5)
        let first = try #require(videos.first)
        #expect(first.id.peerTube?.uuid == uuid)
        #expect(first.channelID.peerTube?.handle == handle)
        #expect(first.thumbnails.allSatisfy { $0.url.host() == "instance.example" })
        #expect(first.publishedAt != nil && first.duration != nil)
    }

    @Test func watchPageHasHLSAFileStoryboardsAndMoreFromTheChannel() async throws {
        let pt = source {
            $0.on("/api/v1/videos/\(uuid)", fixture: "peertube/video.json")
            $0.on("/api/v1/videos/\(uuid)/captions", fixture: "peertube/captions.json")
            $0.on("/api/v1/videos/\(uuid)/storyboards", fixture: "peertube/storyboards.json")
            $0.on("/videos", fixture: "peertube/channel-videos.json")
        }
        let id = VideoID.peerTube(host: "instance.example", uuid: uuid)
        let page = try await pt.watchPage(for: id)
        #expect(page.manifest.hlsURL?.pathExtension == "m3u8")
        #expect(page.manifest.muxedURL?.pathExtension == "mp4")
        #expect(page.manifest.videoStreams.isEmpty && page.manifest.audioStreams.isEmpty)
        let board = try #require(page.manifest.storyboards.first)
        #expect(board.columns == 11 && board.frameWidth == 192 && board.intervalMilliseconds == 1000)
        #expect(board.frameCount <= 81)
        #expect(!page.details.related.isEmpty && !page.details.related.contains { $0.id == id })
        #expect(page.details.summary.title.contains("OVERGROWN"))
    }

    @Test func channelHasItsBannerAndVideos() async throws {
        let pt = source {
            $0.on("/api/v1/video-channels/\(handle)/videos", fixture: "peertube/channel-videos.json")
            $0.on("/api/v1/video-channels/\(handle)", fixture: "peertube/channel.json")
        }
        let page = try await pt.channel(.peerTube(host: "instance.example", handle: handle), cursor: nil)
        #expect(page.name == "Blender Open Movies")
        #expect(page.banner?.url.host() == "instance.example" && page.avatar != nil)
        #expect(page.videos.items.count == 5)
    }

    @Test func commentsComeAsThreads() async throws {
        let pt = source { $0.on("/comment-threads", fixture: "peertube/comments.json") }
        let page = try await pt.comments(for: .peerTube(host: "instance.example", uuid: uuid), cursor: nil)
        #expect(page.items.first?.text == "Video not playing")
    }

    @Test func searchAcrossServersShowsAFederatedVideoOnce() async throws {
        func server(_ host: String, fails: Bool = false) -> PeerTubeSource {
            let client = FixtureClient()
            if fails { client.on("/api/v1/search/videos", status: 500, body: Data()) }
            else { client.on("/api/v1/search/videos", fixture: "peertube/search.json") }
            return PeerTubeSource(instance: instance(.peerTube, "https://\(host)"), client: client)
        }
        let one = try await server("a.example").search("blender", filter: .videos, cursor: nil)
        // Both servers index the same videos: each appears once, from the first server.
        let both = try await PeerTubeSearch.search([server("a.example"), server("b.example"), server("c.example", fails: true)],
                                                   query: "blender", filter: .videos, cursor: nil)
        #expect(both.items.count == one.items.count && !both.items.isEmpty)
        #expect(both.items.allSatisfy { if case .video(let v) = $0 { v.id.peerTube?.host == "a.example" } else { false } })
        #expect(both.nextCursor == one.nextCursor)
        await #expect(throws: SourceError.self) {
            try await PeerTubeSearch.search([server("c.example", fails: true)], query: "x", filter: .videos, cursor: nil)
        }
    }

    @Test func searchFindsVideosAndChannels() async throws {
        let pt = source {
            $0.on("/api/v1/search/videos", fixture: "peertube/search.json")
            $0.on("/api/v1/search/video-channels", fixture: "peertube/search-channels.json")
        }
        let videos = try await pt.search("blender", filter: .videos, cursor: nil)
        #expect(videos.items.count == 5 && videos.nextCursor == "5")
        let channels = try await pt.search("blender", filter: .channels, cursor: nil)
        #expect(channels.items.allSatisfy { if case .channel(let channel) = $0 { channel.id.isPeerTube } else { false } })
    }

    @Test func declinesOtherContentAndGeneralQueriesBesideYouTube() async throws {
        let pt = source(general: false) { _ in }
        await #expect(throws: SourceError.self) { try await pt.watchPage(for: VideoID(rawValue: "dQw4w9WgXcQ")) }
        await #expect(throws: SourceError.self) { try await pt.watchPage(for: .peerTube(host: "other.example", uuid: uuid)) }
        await #expect(throws: SourceError.self) { try await pt.search("x", filter: .videos, cursor: nil) }
        await #expect(throws: SourceError.self) { try await pt.trending(region: nil, category: .all) }
        // No suggestions of its own: it steps aside so YouTube's come through.
        await #expect(throws: SourceError.self) { try await pt.suggestions(for: "blen") }
    }

    @Test func youTubeFrontEndsDeclinePeerTubeContent() async throws {
        let client = FixtureClient()
        let piped = YouTubeOnly(PipedSource(instance: instance(.piped), client: client))
        await #expect(throws: SourceError.self) { try await piped.watchPage(for: .peerTube(host: "instance.example", uuid: uuid)) }
        await #expect(throws: SourceError.self) { try await piped.feed(for: [.peerTube(host: "instance.example", handle: handle)]) }
        #expect(client.requests.isEmpty)
    }

    @Test func detectorRecognisesPeerTube() async throws {
        let client = FixtureClient()
        client.on("/api/v1/config", fixture: "peertube/config.json")
        let found = try await InstanceDetector(client: client).detect("instance.example")
        #expect(found.kind == .peerTube && found.version != nil)
    }

    @Test func routerPassesForeignContentOnWithoutMarkingTheInstance() async throws {
        let client = FixtureClient()
        client.on("/api/v1/videos/\(uuid)", fixture: "peertube/video.json")
        let piped = YouTubeOnly(PipedSource(instance: instance(.piped), client: FixtureClient()))
        let pt = PeerTubeSource(instance: instance(.peerTube), client: client)
        let router = InstanceRouter(sources: [piped, pt])
        let id = VideoID.peerTube(host: "instance.example", uuid: uuid)
        for _ in 0..<4 {
            let page = try await router.perform(.streams) { try await $0.watchPage(for: id) }
            #expect(page.details.summary.id == id)
        }
        // Piped was asked and declined four times, yet still ranks as healthy for streams.
        #expect(await router.rankedSources(for: .streams).count == 2)
    }

    @Test func directoryLeavesOutNSFWAndPutsTheLanguageFirst() async throws {
        let client = FixtureClient()
        client.on("/api/v1/instances", fixture: "peertube/index.json")
        let (servers, total) = try await PeerTubeDirectory(client: client).servers(sort: .mostUsers, search: "tube",
                                                                                    start: 40, language: "en")
        #expect(total > 0)
        let query = try #require(client.requests.first?.url?.query)
        #expect(query.contains("sort=-totalUsers") && query.contains("search=tube") && query.contains("start=40"))
        #expect(!servers.contains { $0.host == "nsfw.example" })
        #expect(servers.first?.languages.contains("en") == true)
        #expect(servers.contains { $0.host == "videos.example" })
    }
}
