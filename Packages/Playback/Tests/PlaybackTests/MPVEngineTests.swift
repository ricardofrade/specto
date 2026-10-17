import AVFoundation
import Foundation
import Testing
import Core
@testable import Playback

@MainActor
struct MPVEngineTests {
    @Test func playsALocalH264FileHeadless() async throws {
        let file = try await TestMedia.h264(seconds: 3)
        defer { try? FileManager.default.removeItem(at: file) }
        let engine = MPVEngine(configuration: .init(rendersVideo: false, playsAudio: false))
        let recorder = EventRecorder(engine.events)

        try await engine.load(PlaybackRequest(videoID: VideoID(rawValue: "local"),
                                              source: .progressive(file), mode: .video))
        engine.play()

        let decoder = try await recorder.first { if case .decoder(let info) = $0 { info } else { nil } }
        #expect(decoder.codec == .h264)
        #expect(decoder.width == 320 && decoder.height == 240)

        _ = try await recorder.first { if case .state(.playing) = $0 { true } else { nil } }
        let position = try await recorder.first { event -> Duration? in
            if case .position(let p, _) = event, p > .milliseconds(300) { p } else { nil }
        }
        #expect(position > .zero)
        engine.stop()
    }

    @Test func missingFileFailsTheLoad() async {
        let engine = MPVEngine(configuration: .init(rendersVideo: false, playsAudio: false))
        let missing = URL.temporaryDirectory.appending(path: "\(UUID()).mp4")
        await #expect(throws: PlaybackError.self) {
            try await engine.load(PlaybackRequest(videoID: VideoID(rawValue: "missing"),
                                                  source: .progressive(missing), mode: .video))
        }
    }

    @Test func readsHTTPStatusFromMPVLogLines() {
        #expect(MPVCore.httpStatus(in: "https: HTTP error 403 Forbidden\n") == 403)
        #expect(MPVCore.httpStatus(in: "tcp: Connection refused") == nil)
        #expect(MPVEngine.error(code: -13, httpStatus: 403) == .streamExpired)
        #expect(MPVEngine.error(code: -13, httpStatus: 410) == .streamExpired)
        #expect(MPVEngine.error(code: -13, httpStatus: 401) == .streamExpired)
        #expect(MPVEngine.error(code: -13, httpStatus: 500) == .network)
    }

    @Test func escapesURLsInLoadOptions() {
        let video = VideoStream(url: URL(string: "https://p.example/v?a=1,b=2")!, codec: .h264,
                                container: .mp4, width: 1920, height: 1080, fps: 30, bitrate: nil, isHDR: false)
        let audio = AudioStream(url: URL(string: "https://p.example/a?x=1,y=2")!, codec: .aac,
                                container: .mp4, bitrate: nil, language: nil)
        let request = PlaybackRequest(videoID: VideoID(rawValue: "v"), source: .adaptive(video: video, audio: audio),
                                      startAt: .seconds(12), mode: .video)
        let (url, options) = MPVEngine.loadArguments(for: request)
        #expect(url == "https://p.example/v?a=1,b=2")
        #expect(options == "start=12.000,audio-file=%27%https://p.example/a?x=1,y=2")
    }

    @Test func liveHasNoStartSoItOpensAtTheLiveEdge() {
        var request = PlaybackRequest(videoID: VideoID(rawValue: "v"), source: .hls(URL(string: "https://p.example/l.m3u8")!),
                                      mode: .video)
        request.isLive = true
        #expect(MPVEngine.loadArguments(for: request).options == "")
    }
}

/// Collects an engine's events so tests can wait for the first matching one.
@MainActor
final class EventRecorder {
    private var events: [PlaybackEvent] = []
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<PlaybackEvent>) {
        task = Task { [weak self] in
            for await event in stream { self?.events.append(event) }
        }
    }

    func first<T>(timeout: Duration = .seconds(10), _ match: (PlaybackEvent) -> T?) async throws -> T {
        let deadline = ContinuousClock.now + timeout
        var seen = 0
        while ContinuousClock.now < deadline {
            while seen < events.count {
                if let value = match(events[seen]) { return value }
                seen += 1
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("No matching event within \(timeout); saw \(events)")
        throw CancellationError()
    }
}

enum TestMedia {
    /// A small 320×240 H.264 MP4 of solid colour frames at 30 fps.
    static func h264(seconds: Int) async throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(UUID()).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 240,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320,
            kCVPixelBufferHeightKey as String: 240,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<(seconds * 30) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { throw CancellationError() }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw CancellationError() }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(frame * 4 % 255),
                   CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CancellationError() }
        return url
    }
}
