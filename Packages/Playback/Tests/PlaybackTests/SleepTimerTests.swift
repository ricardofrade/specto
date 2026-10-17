import Foundation
import Testing
import Core
@testable import Playback

@MainActor
struct SleepTimerTests {
    private func session() -> (PlaybackSession, FakeEngine) {
        let engine = FakeEngine(kind: .mpv)
        return (PlaybackSession(resumeStore: MemoryResumeStore()) { _ in engine }, engine)
    }

    @Test func pausesWhenTheTimeIsUp() async {
        let (session, engine) = session()
        let id = VideoID(rawValue: "aaaaaaaaaaa")
        let audio = AudioStream(url: URL(string: "https://proxy.example/a")!, codec: .aac, container: .mp4,
                                bitrate: 128_000, language: nil)
        await session.play(NowPlayingItem(videoID: id, title: "", channelName: "", artworkURL: nil),
                           PlaybackRequest(videoID: id, source: .adaptive(video: nil, audio: audio), mode: .video))
        let minutes = MinuteCounter()
        let timer = SleepTimer(session: session) { _ in await minutes.tick() }
        timer.set(.minutes(15))
        #expect(timer.status != nil)
        for _ in 0..<500 where timer.choice != nil { await Task.yield() }
        #expect(await minutes.count == 15)
        #expect(engine.pauseCount == 1)
        #expect(timer.choice == nil && timer.status == nil)
    }

    @Test func turningItOffCancelsTheCountdown() async {
        let (session, engine) = session()
        let timer = SleepTimer(session: session) { _ in try await Task.sleep(for: .seconds(3600)) }
        timer.set(.minutes(30))
        timer.set(nil)
        for _ in 0..<50 { await Task.yield() }
        #expect(engine.pauseCount == 0)
        #expect(timer.status == nil)
    }

    @Test func endOfVideoStopsOnceThenTurnsOff() {
        let (session, _) = session()
        let timer = SleepTimer(session: session)
        #expect(!timer.stopsAtEndOfVideo())
        timer.set(.endOfVideo)
        #expect(timer.stopsAtEndOfVideo())
        #expect(!timer.stopsAtEndOfVideo())
        #expect(timer.choice == nil)
    }

    @Test func labels() {
        #expect(SleepTimer.label(for: .minutes(15)).contains("15"))
        #expect(SleepTimer.label(for: .minutes(60)).contains("1"))
    }
}

private actor MinuteCounter {
    private(set) var count = 0
    func tick() { count += 1 }
}
