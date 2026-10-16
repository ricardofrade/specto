import Foundation
import Testing
@testable import Core

/// Adapters against real instances. Run with the URLs from `.env.local` (never committed):
///   scripts/contract-tests.sh
/// Each suite is skipped when its URL is missing.
private let environment = ProcessInfo.processInfo.environment
private let pipedURL = environment["PIPED_URL"].flatMap(URL.init(string:))
private let invidiousURL = environment["INVIDIOUS_URL"].flatMap(URL.init(string:))
private let ytZeroURL = environment["YTZERO_URL"].flatMap(URL.init(string:))
private let ytZeroToken = environment["YTZERO_TOKEN"]

/// Big Buck Bunny (Blender Foundation, CC BY): stable, long-lived, H.264/VP9/AV1 renditions.
private let knownVideo = VideoID(rawValue: "aqz-KE-bpKQ")
/// Blender's own channel.
private let knownChannel = ChannelID(rawValue: "UCSMOQeBJ2RAnuFungnQOxLg")

@Suite(.enabled(if: pipedURL != nil), .timeLimit(.minutes(2)))
struct PipedContractTests {
    let source = PipedSource(instance: InstanceConfig(kind: .piped, displayName: "Piped", apiURL: pipedURL!))

    @Test func detectsAsPiped() async throws {
        #expect(try await InstanceDetector().detect(pipedURL!.absoluteString).kind == .piped)
    }

    @Test func healthCheckPasses() async {
        #expect(await source.healthCheck().isHealthy)
    }

    @Test func watchPageHasProxiedIndexedStreams() async throws {
        let page = try await source.watchPage(for: knownVideo)
        #expect(!page.details.summary.title.isEmpty)
        #expect(page.details.summary.duration != nil)
        let mp4 = page.manifest.videoStreams.filter { $0.container == .mp4 }
        #expect(!mp4.isEmpty)
        #expect(mp4.allSatisfy { $0.initRange != nil && $0.indexRange != nil && $0.codecs != nil })
        #expect(page.manifest.audioStreams.contains { $0.codec == .aac })
        // Streams must come through the instance's proxy, never googlevideo directly.
        #expect(page.manifest.videoStreams.allSatisfy { !($0.url.host() ?? "").hasSuffix("googlevideo.com") })
        #expect(page.manifest.expiresAt.map { $0 > .now } == true)
    }

    @Test func searchAndChannelPage() async throws {
        let results = try await source.search("big buck bunny", cursor: nil)
        #expect(!results.items.isEmpty)
        let channel = try await source.channel(knownChannel, cursor: nil)
        #expect(!channel.name.isEmpty && !channel.videos.items.isEmpty)
    }

    @Test func commentsLoad() async throws {
        let page = try await source.comments(for: knownVideo, cursor: nil)
        #expect(!page.items.isEmpty)
    }
}

@Suite(.enabled(if: invidiousURL != nil), .timeLimit(.minutes(2)))
struct InvidiousContractTests {
    let source = InvidiousSource(instance: InstanceConfig(kind: .invidious, displayName: "Invidious", apiURL: invidiousURL!))

    @Test func detectsAsInvidious() async throws {
        #expect(try await InstanceDetector().detect(invidiousURL!.absoluteString).kind == .invidious)
    }

    @Test func healthCheckPasses() async {
        #expect(await source.healthCheck().isHealthy)
    }

    @Test func watchPageHasProxiedIndexedStreams() async throws {
        let page = try await source.watchPage(for: knownVideo)
        #expect(!page.details.summary.title.isEmpty)
        let mp4 = page.manifest.videoStreams.filter { $0.container == .mp4 }
        #expect(!mp4.isEmpty)
        #expect(mp4.allSatisfy { $0.initRange != nil && $0.indexRange != nil })
        #expect(page.manifest.audioStreams.contains { $0.codec == .aac && $0.isOriginal })
        #expect(page.manifest.videoStreams.allSatisfy { $0.url.host() == invidiousURL!.host() })
    }

    @Test func atomFeedForAChannel() async throws {
        let feed = try await source.feed(for: [knownChannel])
        #expect(!feed.isEmpty)
        #expect(feed.allSatisfy { $0.publishedAt != nil })
    }

    @Test func searchAndCommentsLoad() async throws {
        #expect(!(try await source.search("big buck bunny", cursor: nil)).items.isEmpty)
        #expect(!(try await source.comments(for: knownVideo, cursor: nil)).items.isEmpty)
    }
}

@Suite(.enabled(if: ytZeroURL != nil), .timeLimit(.minutes(2)))
struct YTZeroContractTests {
    @Test func detectsAsYTZero() async throws {
        let found = try await InstanceDetector().detect(ytZeroURL!.absoluteString)
        #expect(found.kind == .ytZero)
        #expect(found.version != nil)
    }

    @Test func deviceCodeFlowStarts() async throws {
        let code = try await YTZeroDeviceAuth(instanceURL: ytZeroURL!).start(deviceName: "Contract test")
        #expect(code.userCode.count == 9)                       // "XXXX-XXXX"
        #expect(code.verificationURL.path().hasSuffix("/tv/pair"))
        #expect(try await YTZeroDeviceAuth(instanceURL: ytZeroURL!).poll(code) == .pending)
    }

    /// Needs a token (`YTZERO_TOKEN`), which `scripts/contract-tests.sh` obtains by pairing.
    @Test(.enabled(if: ytZeroToken != nil))
    func accountFeedAndSubscriptions() async throws {
        let source = YTZeroSource(instance: InstanceConfig(kind: .ytZero, displayName: "YT Zero", apiURL: ytZeroURL!),
                                  token: ytZeroToken!)
        #expect(await source.healthCheck().isHealthy)
        let channels = try await source.subscriptions()
        let feed = try await source.accountFeed(page: 0)
        #expect(channels.isEmpty == feed.items.isEmpty || !channels.isEmpty)
        if let first = feed.items.first {
            #expect(!first.video.title.isEmpty)
            #expect(first.video.thumbnails.first?.url.host() == ytZeroURL!.host())
        }
    }

    @Test(.enabled(if: ytZeroToken != nil))
    func watchPageIssuesAPlaybackTicket() async throws {
        let source = YTZeroSource(instance: InstanceConfig(kind: .ytZero, displayName: "YT Zero", apiURL: ytZeroURL!),
                                  token: ytZeroToken!)
        let feed = try await source.accountFeed(page: 0)
        let id = try #require(feed.items.first?.video.id, "The account's feed is empty")
        let page = try await source.watchPage(for: id)
        #expect(page.manifest.hlsURL != nil || page.manifest.muxedURL != nil)
    }
}
