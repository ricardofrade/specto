import Foundation
import Testing
import Core
@testable import Playback

private let url = URL(string: "https://proxy.example/videoplayback")!

private func video(_ codec: VideoCodec, _ height: Int, container: MediaContainer? = nil,
                   fps: Int = 30, bitrate: Int? = nil, hdr: Bool = false) -> VideoStream {
    VideoStream(url: url, codec: codec, container: container ?? (codec == .vp9 ? .webm : .mp4),
                width: height * 16 / 9, height: height, fps: fps, bitrate: bitrate, isHDR: hdr)
}

private func audio(_ codec: AudioCodec, bitrate: Int, language: String? = nil) -> AudioStream {
    AudioStream(url: url, codec: codec, container: codec == .opus ? .webm : .mp4,
                bitrate: bitrate, language: language)
}

private let av1Device = FormatSelector(capabilities: .init(av1Hardware: true, vp9Hardware: false,
                                                            vp9SoftwareMaxHeight: 1440))
private let olderDevice = FormatSelector(capabilities: .init(av1Hardware: false, vp9Hardware: false,
                                                              vp9SoftwareMaxHeight: 1080))

struct FormatSelectorTests {
    @Test func picksHighestResolutionThatFitsTheDisplay() {
        let streams = [video(.h264, 720), video(.h264, 1080), video(.av1, 2160)]
        let pick = av1Device.select(from: streams, for: .mpv, maxDisplayHeight: 1200,
                                    throughputBitsPerSecond: nil, allowHDR: false)
        #expect(pick?.height == 1080)
    }

    @Test func prefersAV1AtTheSameHeightWhenHardwareDecodes() {
        let streams = [video(.h264, 1080), video(.vp9, 1080), video(.av1, 1080)]
        let pick = av1Device.select(from: streams, for: .mpv, maxDisplayHeight: 2160,
                                    throughputBitsPerSecond: nil, allowHDR: false)
        #expect(pick?.codec == .av1)
    }

    @Test func skipsAV1WithoutHardwareAndCapsSoftwareVP9() {
        let streams = [video(.av1, 2160), video(.vp9, 1440), video(.vp9, 1080), video(.h264, 720)]
        let pick = olderDevice.select(from: streams, for: .mpv, maxDisplayHeight: 2160,
                                      throughputBitsPerSecond: nil, allowHDR: false)
        #expect(pick?.codec == .vp9)
        #expect(pick?.height == 1080)
    }

    @Test func staysWithinTheThroughputBudget() {
        let streams = [video(.av1, 2160, bitrate: 20_000_000), video(.av1, 1080, bitrate: 4_000_000)]
        let pick = av1Device.select(from: streams, for: .mpv, maxDisplayHeight: 2160,
                                    throughputBitsPerSecond: 10_000_000, allowHDR: false)
        #expect(pick?.height == 1080)
    }

    @Test func fallsBackToSmallestPlayableWhenNothingFits() {
        let streams = [video(.h264, 1080, bitrate: 5_000_000), video(.h264, 360, bitrate: 1_000_000)]
        let pick = av1Device.select(from: streams, for: .mpv, maxDisplayHeight: 1080,
                                    throughputBitsPerSecond: 100_000, allowHDR: false)
        #expect(pick?.height == 360)
    }

    @Test func excludesHDRUnlessAllowed() {
        let streams = [video(.av1, 2160, hdr: true), video(.av1, 1440)]
        let sdr = av1Device.select(from: streams, for: .mpv, maxDisplayHeight: 2160,
                                   throughputBitsPerSecond: nil, allowHDR: false)
        let hdr = av1Device.select(from: streams, for: .mpv, maxDisplayHeight: 2160,
                                   throughputBitsPerSecond: nil, allowHDR: true)
        #expect(sdr?.height == 1440)
        #expect(hdr?.isHDR == true)
    }

    @Test func avPlayerOnlyGetsMP4() {
        let streams = [video(.vp9, 1440), video(.av1, 1080, container: .mp4), video(.h264, 720)]
        let pick = av1Device.select(from: streams, for: .avPlayer, maxDisplayHeight: 2160,
                                    throughputBitsPerSecond: nil, allowHDR: false)
        #expect(pick?.container == .mp4)
        #expect(pick?.codec == .av1)
    }

    @Test func avPlayerAudioIsAACEvenWhenOpusIsBetter() {
        let streams = [audio(.opus, bitrate: 160_000), audio(.aac, bitrate: 128_000)]
        #expect(av1Device.selectAudio(from: streams, for: .avPlayer, preferredLanguage: nil)?.codec == .aac)
        #expect(av1Device.selectAudio(from: streams, for: .mpv, preferredLanguage: nil)?.codec == .opus)
    }

    @Test func audioMatchesPrimaryLanguageAndFallsBackWhenMissing() {
        let streams = [audio(.opus, bitrate: 160_000, language: "en-US"),
                       audio(.opus, bitrate: 160_000, language: "pt-BR")]
        let portuguese = av1Device.selectAudio(from: streams, for: .mpv, preferredLanguage: "PT")
        let german = av1Device.selectAudio(from: streams, for: .mpv, preferredLanguage: "de")
        #expect(portuguese?.language == "pt-BR")
        #expect(german != nil)
    }
}
