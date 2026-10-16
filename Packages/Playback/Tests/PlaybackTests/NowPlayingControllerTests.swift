import MediaPlayer
import Testing
import Core
@testable import Playback
@testable import PlaybackUI

@MainActor
struct NowPlayingControllerTests {
    @Test func publishesTheCurrentItem() async throws {
        let engine = FakeEngine(kind: .mpv)
        let session = PlaybackSession(resumeStore: MemoryResumeStore()) { _ in engine }
        let controller = NowPlayingController(session: session) { _ in nil }
        let id = VideoID(rawValue: "now")
        let audio = AudioStream(url: URL(string: "https://p.example/a")!, codec: .aac, container: .mp4,
                                bitrate: nil, language: nil)
        await session.play(NowPlayingItem(videoID: id, title: "A title", channelName: "A channel", artworkURL: nil),
                           PlaybackRequest(videoID: id, source: .adaptive(video: nil, audio: audio), mode: .video))
        engine.emit(.position(.seconds(3), duration: .seconds(60)))
        engine.emit(.state(.playing))
        for _ in 0..<100 {
            if MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] != nil { break }
            await Task.yield()
        }
        let info = try #require(MPNowPlayingInfoCenter.default().nowPlayingInfo)
        #expect(info[MPMediaItemPropertyTitle] as? String == "A title")
        #expect(info[MPMediaItemPropertyArtist] as? String == "A channel")
        withExtendedLifetime(controller) {}
    }

    /// Regression: the handler used to inherit main-actor isolation and trap when MediaPlayer
    /// called it from a background queue.
    @Test func artworkHandlerIsSafeOffTheMainThread() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        let artwork = NowPlayingController.artwork(image)
        let rendered = DispatchQueue.global().sync { artwork.image(at: CGSize(width: 8, height: 8)) }
        #expect(rendered != nil)
    }
}
