import AVFoundation
import Foundation
import Testing
import Core
@testable import Playback

/// Spike 6 against a real instance: AVPlayer plays separate H.264 + AAC streams through
/// playlists written on device. Runs only with `PIPED_URL` set (passed as TEST_RUNNER_PIPED_URL).
private let pipedURL = ProcessInfo.processInfo.environment["PIPED_URL"].flatMap(URL.init(string:))

@MainActor
struct LocalHLSIntegrationTests {
    @Test(.enabled(if: pipedURL != nil), .timeLimit(.minutes(1)))
    func avPlayerPlaysAdaptiveStreamsThroughLocalPlaylists() async throws {
        let (video, audio) = try await Self.streams(videoID: "aqz-KE-bpKQ")
        let prepared = try await LocalHLS.prepare(video: video, audio: audio)
        let item = AVPlayerItem(asset: prepared.asset)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.play()

        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline, player.currentTime().seconds < 2, item.status != .failed {
            try await Task.sleep(for: .milliseconds(200))
        }
        #expect(item.status == .readyToPlay, "\(String(describing: item.error))")
        #expect(player.currentTime().seconds >= 2, "Playback didn't advance")
        #expect(item.presentationSize == CGSize(width: video.width, height: video.height))
        withExtendedLifetime(prepared) {}
    }

    /// 720p H.264 (any frame rate) and AAC from Piped's `/streams`, with their byte ranges.
    private static func streams(videoID: String) async throws -> (VideoStream, AudioStream) {
        let url = try #require(pipedURL).appending(path: "streams/\(videoID)")
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        func streams(_ key: String) -> [[String: Any]] { json[key] as? [[String: Any]] ?? [] }
        func range(_ s: [String: Any], _ start: String, _ end: String) -> ByteRange? {
            guard let a = s[start] as? Int, let b = s[end] as? Int, b > a else { return nil }
            return ByteRange(start: Int64(a), end: Int64(b))
        }
        let v = try #require(streams("videoStreams").first {
            ($0["videoOnly"] as? Bool) == true && ($0["height"] as? Int) == 720
                && (($0["codec"] as? String)?.hasPrefix("avc1") ?? false)
        })
        let a = try #require(streams("audioStreams").first { ($0["itag"] as? Int) == 140 })
        let video = VideoStream(url: URL(string: v["url"] as! String)!, codec: .h264, codecs: v["codec"] as? String,
                                container: .mp4, itag: v["itag"] as? Int, width: v["width"] as? Int ?? 0,
                                height: v["height"] as? Int ?? 0, fps: v["fps"] as? Int ?? 0,
                                bitrate: v["bitrate"] as? Int, isHDR: false,
                                initRange: range(v, "initStart", "initEnd"),
                                indexRange: range(v, "indexStart", "indexEnd"))
        let audio = AudioStream(url: URL(string: a["url"] as! String)!, codec: .aac, codecs: a["codec"] as? String,
                                container: .mp4, itag: 140, bitrate: a["bitrate"] as? Int, language: nil,
                                initRange: range(a, "initStart", "initEnd"),
                                indexRange: range(a, "indexStart", "indexEnd"))
        return (video, audio)
    }
}
