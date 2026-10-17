import Foundation
import Testing
import Core
@testable import Playback

struct AudioTracksTests {
    private func audio(_ language: String?, original: Bool, codec: AudioCodec = .aac) -> AudioStream {
        AudioStream(url: URL(string: "https://proxy.example/a")!, codec: codec, container: codec == .opus ? .webm : .mp4,
                    bitrate: 128_000, language: language, isOriginal: original)
    }

    @Test func originalFirstThenDubsByNameOncePerLanguage() {
        let streams = [audio("en-US", original: true), audio("en-US", original: true, codec: .opus),
                       audio("es-US", original: false), audio("es-US", original: false, codec: .opus),
                       audio("de-DE", original: false)]
        let options = AudioTracks.options(in: streams, locale: Locale(identifier: "en"))
        #expect(options.map(\.language) == [nil, "de", "es"])
        #expect(options.map(\.label) == ["English (original)", "German", "Spanish"])
    }

    @Test func nothingToPickWithOneLanguage() {
        #expect(AudioTracks.options(in: [audio("en", original: true), audio(nil, original: true)]).isEmpty)
        #expect(AudioTracks.options(in: [audio(nil, original: true)]).isEmpty)
    }

    @Test func aRememberedLanguageAppliesOnlyWhereOffered() {
        let options = AudioTracks.options(in: [audio("en", original: true), audio("es", original: false)],
                                          locale: Locale(identifier: "en"))
        #expect(AudioTracks.selected("es-ES", in: options) == "es")
        #expect(AudioTracks.selected("fr", in: options) == nil)   // Plays the original.
        #expect(AudioTracks.selected(nil, in: options) == nil)
    }

    @Test func thePlannerPlaysThePickedDub() throws {
        let video = VideoStream(url: URL(string: "https://proxy.example/v")!, codec: .h264, container: .mp4,
                                width: 1280, height: 720, fps: 30, bitrate: nil, isHDR: false)
        let original = audio("en", original: true), dub = audio("es", original: false)
        let page = WatchPage(details: VideoDetails(summary: VideoSummary(id: VideoID(rawValue: "a"), title: "", channelID: ChannelID(rawValue: "c"),
                                                                         channelName: "", duration: nil, publishedAt: nil,
                                                                         viewCount: nil, thumbnails: []),
                                                   description: "", likeCount: nil, related: []),
                             manifest: StreamManifest(videoID: VideoID(rawValue: "a"), videoStreams: [video],
                                                      audioStreams: [original, dub], hlsURL: nil, muxedURL: nil,
                                                      chapters: [], expiresAt: nil))
        let capabilities = DecodeCapabilities(av1Hardware: false, vp9Hardware: false, vp9SoftwareMaxHeight: 1440)
        let planner = PlaybackPlanner(selector: FormatSelector(capabilities: capabilities), preferredAudioLanguage: "es")
        let request = try planner.request(for: page, mode: .video, maxDisplayHeight: 1080,
                                          throughputBitsPerSecond: nil, allowHDR: false)
        guard case .adaptive(_, let audio) = request.source else { Issue.record("Not adaptive"); return }
        #expect(audio.language == "es")
    }
}
