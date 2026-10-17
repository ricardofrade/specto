import Foundation
import QuartzCore
import Testing
import Core
@testable import Playback

// MARK: - Fakes

@MainActor
final class FakeEngine: PlaybackEngine {
    let kind: EngineKind
    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    private(set) var loaded: [PlaybackRequest] = []
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var stopCount = 0
    private(set) var detachCount = 0
    private(set) var attachedHost: (any RenderSurfaceHost)?
    /// Loads for these videos suspend until `release` is called.
    var gated: Set<VideoID> = []
    var failing: [VideoID: PlaybackError] = [:]
    private var pending: [VideoID: CheckedContinuation<Void, Never>] = [:]

    init(kind: EngineKind) {
        self.kind = kind
        (events, continuation) = AsyncStream.makeStream()
    }

    func emit(_ event: PlaybackEvent) { continuation.yield(event) }
    func isLoading(_ id: VideoID) -> Bool { pending[id] != nil }
    func release(_ id: VideoID) { pending.removeValue(forKey: id)?.resume() }

    func prewarm() {}
    func load(_ request: PlaybackRequest) async throws {
        loaded.append(request)
        if gated.contains(request.videoID) {
            await withCheckedContinuation { pending[request.videoID] = $0 }
        }
        if let error = failing[request.videoID] { throw error }
    }
    func play() { playCount += 1 }
    func pause() { pauseCount += 1 }
    func seek(to position: Duration, precise: Bool) async { seeks.append(position) }
    private(set) var rates: [Float] = []
    func setRate(_ rate: Float) { rates.append(rate) }
    func stop() { stopCount += 1 }
    func attach(_ host: any RenderSurfaceHost) { attachedHost = host }
    func detach() { detachCount += 1; attachedHost = nil }
    func layoutSurface() {}
    private(set) var seeks: [Duration] = []
    func setVideoEnabled(_ enabled: Bool) {}
}

@MainActor
final class FakeHost: RenderSurfaceHost {
    let containerLayer = CALayer()
}

actor MemoryResumeStore: ResumeStore {
    struct Save: Equatable { let id: VideoID; let position: Duration }

    private(set) var positions: [VideoID: Duration]
    private(set) var saves: [Save] = []

    init(_ positions: [VideoID: Duration] = [:]) { self.positions = positions }

    func position(for id: VideoID) -> Duration? { positions[id] }
    func save(_ position: Duration, duration: Duration?, for id: VideoID) {
        positions[id] = position
        saves.append(Save(id: id, position: position))
    }
}

// MARK: - Helpers

private let a = VideoID(rawValue: "aaaaaaaaaaa")
private let b = VideoID(rawValue: "bbbbbbbbbbb")

private func item(_ id: VideoID) -> NowPlayingItem {
    NowPlayingItem(videoID: id, title: id.rawValue, channelName: "Channel", artworkURL: nil)
}

private func request(_ id: VideoID, startAt: Duration = .zero, mode: PlaybackMode = .video) -> PlaybackRequest {
    let audio = AudioStream(url: URL(string: "https://proxy.example/a")!, codec: .aac, container: .mp4,
                            bitrate: 128_000, language: nil)
    return PlaybackRequest(videoID: id, source: .adaptive(video: nil, audio: audio),
                           startAt: startAt, mode: mode)
}

/// Lets the session's event loop and queued tasks run.
@MainActor
private func settle() async {
    for _ in 0..<50 { await Task.yield() }
}

@MainActor
private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
    for _ in 0..<500 {
        if condition() { return }
        await Task.yield()
    }
    Issue.record("Condition never became true", sourceLocation: sourceLocation)
}

@MainActor
private func makeSession(_ store: MemoryResumeStore) -> (PlaybackSession, mpv: FakeEngine, av: FakeEngine) {
    let mpv = FakeEngine(kind: .mpv)
    let av = FakeEngine(kind: .avPlayer)
    let session = PlaybackSession(resumeStore: store) { $0 == .mpv ? mpv : av }
    return (session, mpv, av)
}

// MARK: - Tests

@MainActor
struct PlaybackSessionTests {
    @Test func resumesFromSavedPosition() async {
        let (session, mpv, _) = makeSession(MemoryResumeStore([a: .seconds(90)]))
        await session.play(item(a), request(a))
        #expect(mpv.loaded.last?.startAt == .seconds(90))
        #expect(session.position == .seconds(90))
        #expect(mpv.playCount == 1)
    }

    @Test func explicitStartOverridesSavedPosition() async {
        let (session, mpv, _) = makeSession(MemoryResumeStore([a: .seconds(90)]))
        await session.play(item(a), request(a, startAt: .seconds(10)))
        #expect(mpv.loaded.last?.startAt == .seconds(10))
    }

    @Test func switchingVideosSavesTheOutgoingPosition() async {
        let store = MemoryResumeStore()
        let (session, mpv, _) = makeSession(store)
        await session.play(item(a), request(a))
        mpv.emit(.position(.seconds(42), duration: .seconds(600)))
        mpv.emit(.position(.seconds(44), duration: .seconds(600)))
        await settle()

        await session.play(item(b), request(b))
        await session.flushSaves()

        #expect(await store.positions[a] == .seconds(44))
        #expect(await store.positions[b] == nil)
    }

    @Test func stalePositionWhileLoadingIsNotSavedAgainstTheNewVideo() async {
        let store = MemoryResumeStore()
        let (session, mpv, _) = makeSession(store)
        await session.play(item(a), request(a))
        mpv.emit(.position(.seconds(300), duration: nil))
        await settle()

        mpv.gated = [b]
        let playB = Task { await session.play(item(b), request(b)) }
        await waitUntil { mpv.isLoading(b) }
        mpv.emit(.position(.seconds(301), duration: nil))
        mpv.emit(.state(.paused))
        await settle()
        mpv.release(b)
        await playB.value
        await session.flushSaves()

        #expect(await store.positions[b] == nil)
        #expect(session.position == .zero)
    }

    @Test func tappingAgainBeforeResumeLoadsDoesNotZeroTheSavedPosition() async {
        let store = MemoryResumeStore([a: .seconds(120)])
        let (session, mpv, _) = makeSession(store)
        mpv.gated = [a]
        let playA = Task { await session.play(item(a), request(a)) }
        await waitUntil { mpv.isLoading(a) }

        await session.play(item(b), request(b))
        mpv.release(a)
        await playA.value
        await session.flushSaves()

        #expect(await store.positions[a] == .seconds(120))
    }

    @Test func aSlowEarlierLoadDoesNotOverrideALaterOne() async {
        let (session, mpv, _) = makeSession(MemoryResumeStore())
        mpv.gated = [a, b]
        mpv.failing = [a: .network]

        let playA = Task { await session.play(item(a), request(a)) }
        await waitUntil { mpv.isLoading(a) }
        let playB = Task { await session.play(item(b), request(b)) }
        await waitUntil { mpv.isLoading(b) }

        mpv.release(b)
        await playB.value
        mpv.release(a)
        await playA.value

        #expect(session.item?.videoID == b)
        #expect(mpv.playCount == 1)
        #expect(session.state == .loading)
    }

    @Test func savesLandInOrderAndStopSavesTheFinalPosition() async {
        let store = MemoryResumeStore()
        let (session, mpv, _) = makeSession(store)
        await session.play(item(a), request(a))
        for second in [6, 8, 12, 13] {
            mpv.emit(.position(.seconds(second), duration: nil))
        }
        await settle()
        session.stop()
        await session.flushSaves()

        #expect(await store.saves.map(\.position) == [.seconds(6), .seconds(12), .seconds(13)])
        #expect(session.state == .idle)
    }

    @Test func failedLoadReportsATypedError() async {
        let (session, mpv, _) = makeSession(MemoryResumeStore())
        mpv.failing = [a: .streamExpired]
        await session.play(item(a), request(a))
        #expect(session.state == .failed(.streamExpired))
    }

    @Test func switchingToAudioOnlyMovesEnginesAndKeepsPosition() async {
        let (session, mpv, av) = makeSession(MemoryResumeStore())
        await session.play(item(a), request(a))
        mpv.emit(.position(.seconds(30), duration: nil))
        await settle()

        await session.switchMode(to: .audioOnly, using: request(a))

        #expect(mpv.stopCount == 1)
        #expect(av.loaded.last?.startAt == .seconds(30))
        #expect(session.mode == .audioOnly)
    }

    @Test func staleDetachIsANoOp() async {
        let (session, mpv, _) = makeSession(MemoryResumeStore())
        let oldHost = FakeHost()
        let newHost = FakeHost()
        session.attach(oldHost)
        await session.play(item(a), request(a))

        session.attach(newHost)
        session.detach(oldHost)

        #expect(mpv.detachCount == 0)
        #expect(mpv.attachedHost === newHost)
    }

    @Test func skipsSponsorSegmentsOnceEach() async {
        let (session, mpv, _) = makeSession(MemoryResumeStore())
        await session.play(item(a), request(a))
        let sponsor = SkipSegment(category: .sponsor, start: .seconds(30), end: .seconds(60))
        session.setSkipSegments([sponsor], for: a)
        mpv.emit(.position(.seconds(31), duration: .seconds(600)))
        await settle()
        #expect(mpv.seeks == [.seconds(60)])
        #expect(session.lastSkipped == sponsor)

        // Seeking back into the segment plays it: no second skip.
        mpv.emit(.position(.seconds(35), duration: .seconds(600)))
        await settle()
        #expect(mpv.seeks == [.seconds(60)])
    }

    @Test func offersManualSegmentsInsteadOfSkipping() async {
        let (session, mpv, _) = makeSession(MemoryResumeStore())
        await session.play(item(a), request(a))
        let intro = SkipSegment(category: .intro, start: .seconds(5), end: .seconds(20))
        let sponsor = SkipSegment(category: .sponsor, start: .seconds(30), end: .seconds(60))
        session.setSkipSegments([intro, sponsor], for: a, manual: [.intro])
        mpv.emit(.position(.seconds(6), duration: .seconds(600)))
        await settle()
        #expect(mpv.seeks.isEmpty)
        #expect(session.skippable == intro)

        session.skipOffered()
        await settle()
        #expect(mpv.seeks == [.seconds(20)])
        #expect(session.skippable == nil)

        // Back in the intro after skipping it: no second offer. Past it: none either.
        mpv.emit(.position(.seconds(10), duration: .seconds(600)))
        await settle()
        #expect(session.skippable == nil)
        // Automatic categories still skip.
        mpv.emit(.position(.seconds(31), duration: .seconds(600)))
        await settle()
        #expect(mpv.seeks == [.seconds(20), .seconds(60)])
    }

    @Test func shownOnlySegmentsAreNeitherSkippedNorOffered() async {
        let (session, mpv, _) = makeSession(MemoryResumeStore())
        await session.play(item(a), request(a))
        let filler = SkipSegment(category: .filler, start: .seconds(5), end: .seconds(20))
        session.setSkipSegments([filler], for: a, shownOnly: [.filler])
        mpv.emit(.position(.seconds(6), duration: .seconds(600)))
        await settle()
        #expect(mpv.seeks.isEmpty)
        #expect(session.skippable == nil)
        #expect(session.skipSegments == [filler])   // Still there, for the timeline.
    }

    @Test func theOfferEndsWhenPlaybackLeavesTheSegment() async {
        let (session, mpv, _) = makeSession(MemoryResumeStore())
        await session.play(item(a), request(a))
        let intro = SkipSegment(category: .intro, start: .seconds(5), end: .seconds(20))
        session.setSkipSegments([intro], for: a, manual: [.intro])
        mpv.emit(.position(.seconds(6), duration: .seconds(600)))
        await settle()
        #expect(session.skippable == intro)
        mpv.emit(.position(.seconds(25), duration: .seconds(600)))
        await settle()
        #expect(session.skippable == nil)
        #expect(mpv.seeks.isEmpty)
    }

    @Test func skipsSponsorSegmentsInAudioMode() async {
        let (session, mpv, av) = makeSession(MemoryResumeStore())
        await session.play(item(a), request(a, mode: .audioOnly))
        let sponsor = SkipSegment(category: .sponsor, start: .seconds(30), end: .seconds(60))
        session.setSkipSegments([sponsor], for: a)
        av.emit(.position(.seconds(31), duration: .seconds(600)))
        await settle()
        #expect(av.seeks == [.seconds(60)])
        #expect(mpv.seeks.isEmpty)
    }

    @Test func speedCarriesOverToTheNextVideoAndEngine() async {
        let (session, mpv, av) = makeSession(MemoryResumeStore())
        await session.play(item(a), request(a))
        session.setRate(1.5)
        #expect(mpv.rates == [1.5])
        await session.play(item(b), request(b, mode: .audioOnly))
        #expect(av.rates == [1.5])
        #expect(session.rate == 1.5)
    }

    @Test func showsTheSubtitleForThePosition() async {
        let (session, mpv, _) = makeSession(MemoryResumeStore())
        await session.play(item(a), request(a))
        session.setSubtitles([SubtitleCue(start: .seconds(10), end: .seconds(12), text: "Hello")], for: a)
        session.setSubtitles([SubtitleCue(start: .zero, end: .seconds(100), text: "Other video")], for: b)
        mpv.emit(.position(.seconds(11), duration: .seconds(60)))
        await settle()
        #expect(session.subtitle == "Hello")
        mpv.emit(.position(.seconds(13), duration: .seconds(60)))
        await settle()
        #expect(session.subtitle == nil)
        session.setSubtitles([], for: a)
        #expect(session.subtitle == nil)
    }

    @Test func segmentsForAnotherVideoAreIgnored() async {
        let (session, mpv, _) = makeSession(MemoryResumeStore())
        await session.play(item(a), request(a))
        session.setSkipSegments([SkipSegment(category: .sponsor, start: .zero, end: .seconds(30))], for: b)
        mpv.emit(.position(.seconds(5), duration: nil))
        await settle()
        #expect(mpv.seeks.isEmpty)
    }

    @Test func reportsThePlannedVideoHeight() async {
        let (session, _, _) = makeSession(MemoryResumeStore())
        let stream = VideoStream(url: URL(string: "https://proxy.example/v")!, codec: .h264, container: .mp4,
                                 width: 1280, height: 720, fps: 30, bitrate: nil, isHDR: false)
        var video = request(a)
        if case .adaptive(_, let audio) = video.source { video.source = .adaptive(video: stream, audio: audio) }
        await session.play(item(a), video)
        #expect(session.videoHeight == 720)
        await session.play(item(b), request(b, mode: .audioOnly))
        #expect(session.videoHeight == nil)
    }

    @Test func requestEngineOverridesTheModesEngine() async {
        let (session, mpv, av) = makeSession(MemoryResumeStore())
        var airplay = request(a)
        airplay.engine = .avPlayer
        await session.play(item(a), airplay)
        #expect(av.loaded.count == 1 && mpv.loaded.isEmpty)
    }
}
