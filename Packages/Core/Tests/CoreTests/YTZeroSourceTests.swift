import Foundation
import Testing
@testable import Core

/// YT Zero payloads here are written from its server source (no recorded fixtures yet);
/// `ContractTests` confirms them against a real instance.
struct YTZeroSourceTests {
    private static let video = #"""
    {"video_id":"abc123def45","channel_id":"UCxyz","title":"A video","description":"Hello",
     "thumbnail":"https://i.ytimg.com/vi/abc123def45/hqdefault.jpg","published_at":"2026-10-01 18:30:00",
     "live_status":"none","is_short":0,"views":1200,"likes":30,"duration":"1:02:03",
     "watch_position":120.5,"watch_duration":3723,"watched":null,"channel_title":"A channel"}
    """#

    private func source(_ setup: (FixtureClient) -> Void) -> (YTZeroSource, FixtureClient) {
        let client = FixtureClient()
        setup(client)
        return (YTZeroSource(instance: instance(.ytZero), token: "token-123", client: client), client)
    }

    @Test func parsesDisplayDurationsAndMixedDates() {
        #expect(YTZeroDTO.seconds("12:34") == 754)
        #expect(YTZeroDTO.seconds("1:02:03") == 3723)
        #expect(YTZeroDTO.seconds("75:03") == 4503)
        #expect(YTZeroDTO.seconds("live") == nil)
        #expect(YTZeroDTO.date("2026-10-01 18:30:00") == Date(timeIntervalSince1970: 1_790_879_400))
        #expect(YTZeroDTO.date("2026-10-01T18:30:00+00:00") == Date(timeIntervalSince1970: 1_790_879_400))
        #expect(YTZeroDTO.date("2026-10-01") == Date(timeIntervalSince1970: 1_790_812_800))
    }

    @Test func accountFeedCarriesResumePositionsAndSendsTheToken() async throws {
        let (zero, client) = source { $0.on("/api/feed", body: Data(#"{"videos":[\#(Self.video)],"page":0,"limit":100}"#.utf8)) }
        let page = try await zero.accountFeed(page: 0)
        let entry = try #require(page.items.first)
        #expect(entry.video.duration == .seconds(3723))
        #expect(entry.video.channelName == "A channel")
        #expect(entry.resumePosition == .milliseconds(120_500))
        #expect(!entry.isWatched)
        #expect(page.nextCursor == nil)
        #expect(client.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")
        // Thumbnails go through the instance's image cache, never YouTube directly.
        #expect(entry.video.thumbnails.first?.url.host() == "instance.example")
    }

    @Test func watchPageUsesThePlaybackTicket() async throws {
        let (zero, _) = source {
            $0.on("/api/videos/abc123def45", body: Data(#"{"video":\#(Self.video),"related":[]}"#.utf8))
            $0.on("/playback-ticket", body: Data(#"""
            {"ticket":"t","url":"/api/videos/abc123def45/direct-hls/index.m3u8?media_ticket=t","content_type":"hls","expires_in":900}
            """#.utf8))
        }
        let page = try await zero.watchPage(for: VideoID(rawValue: "abc123def45"))
        #expect(page.manifest.hlsURL?.absoluteString
            == "https://instance.example/api/videos/abc123def45/direct-hls/index.m3u8?media_ticket=t")
        #expect(page.manifest.muxedURL == nil)
        #expect(page.manifest.videoStreams.isEmpty)
        #expect((page.manifest.expiresAt?.timeIntervalSinceNow ?? 0) > 800)
    }

    @Test func deviceAuthMapsPendingAndExpiry() async throws {
        let client = FixtureClient()
        client.on("/api/auth/device/code", body: Data(#"""
        {"device_code":"d","user_code":"ABCD-EFGH","verification_uri":"https://instance.example/tv/pair","verification_uri_complete":"https://instance.example/tv/pair#code=ABCDEFGH","expires_in":600,"interval":3}
        """#.utf8))
        client.on("/api/auth/device/token", status: 428, body: Data(#"{"error":"authorization_pending"}"#.utf8))
        let auth = YTZeroDeviceAuth(instanceURL: URL(string: "https://instance.example")!, client: client)
        let code = try await auth.start(deviceName: "iPhone")
        #expect(code.userCode == "ABCD-EFGH" && code.interval == .seconds(3))
        #expect(try await auth.poll(code) == .pending)

        let expired = FixtureClient()
        expired.on("/api/auth/device/token", status: 400, body: Data(#"{"error":"expired_token"}"#.utf8))
        #expect(try await YTZeroDeviceAuth(instanceURL: URL(string: "https://instance.example")!, client: expired)
            .poll(code) == .expired)
    }

    @Test func resumeRuleIgnoresTheEdges() throws {
        let decode = { (position: Double, duration: Double) in
            try JSONDecoder().decode(YTZeroDTO.Video.self, from: Data(
                #"{"video_id":"v","watch_position":\#(position),"watch_duration":\#(duration)}"#.utf8)).accountVideoState
        }
        #expect(try decode(3, 600).resume == nil)
        #expect(try decode(597, 600).resume == nil)
        #expect(try decode(300, 600).resume == .seconds(300))
    }
}

struct InstanceDetectorTests {
    @Test func normalisesPastedText() {
        #expect(InstanceDetector.normalise("  pipedapi.example.com/  ")?.absoluteString == "https://pipedapi.example.com")
        #expect(InstanceDetector.normalise("http://192.168.1.10:3000/")?.absoluteString == "http://192.168.1.10:3000")
        #expect(InstanceDetector.normalise("ftp://x") == nil)
        #expect(InstanceDetector.normalise("") == nil)
    }

    @Test func recognisesEachKind() async throws {
        let piped = FixtureClient()
        piped.on("/healthcheck", body: Data("OK".utf8))
        piped.on("/config", fixture: "piped/config.json")
        #expect(try await InstanceDetector(client: piped).detect("instance.example").kind == .piped)

        let invidious = FixtureClient()
        invidious.on("/api/v1/stats", fixture: "invidious/stats.json")
        let found = try await InstanceDetector(client: invidious).detect("instance.example")
        #expect(found.kind == .invidious && found.version?.hasPrefix("2026") == true)

        let ytZero = FixtureClient()
        ytZero.on("/api/health", body: Data(#"{"status":"ok","app":"ytzero","version":"2026.09.9"}"#.utf8))
        #expect(try await InstanceDetector(client: ytZero).detect("instance.example").kind == .ytZero)
    }

    @Test func unreachableAndUnrecognisedAreDistinct() async {
        await #expect(throws: InstanceDetector.Failure.unreachable) {
            try await InstanceDetector(client: FixtureClient()).detect("nothing.example")
        }
        let frontend = FixtureClient()
        frontend.on("/", body: Data("<html>".utf8))
        await #expect(throws: InstanceDetector.Failure.unrecognised) {
            try await InstanceDetector(client: frontend).detect("piped-frontend.example")
        }
    }
}

struct HTMLTextTests {
    @Test func stripsTagsAndDecodesEntities() {
        #expect(HTMLText.plain("Line one<br>Line two") == "Line one\nLine two")
        #expect(HTMLText.plain("<a href=\"x\">link</a> &amp; &quot;quoted&quot; &#8212; done") == "link & \"quoted\" — done")
        #expect(HTMLText.plain("plain") == "plain")
        // A shortened address keeps its full href; other link text stays as written.
        #expect(HTMLText.plain(#"More: <a href="https://studio.blender.org/projects/big-buck-bunny/">https://studio.blender.org/projects/b...</a>"#)
                == "More: https://studio.blender.org/projects/big-buck-bunny/")
        #expect(HTMLText.plain(#"<a href="https://www.youtube.com/watch?v=aqz-KE-bpKQ&amp;t=120s">2:00</a> Chorus"#) == "2:00 Chorus")
    }
}
