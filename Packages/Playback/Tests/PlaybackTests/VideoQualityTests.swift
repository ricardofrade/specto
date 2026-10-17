import Foundation
import Testing
import Core
@testable import Playback

private func video(_ codec: VideoCodec, _ height: Int, hdr: Bool = false) -> VideoStream {
    VideoStream(url: URL(string: "https://proxy.example/v")!, codec: codec, container: codec == .h264 ? .mp4 : .webm,
                width: height * 16 / 9, height: height, fps: 30, bitrate: nil, isHDR: hdr)
}

/// ADR 0007: limits per network, Low Data Mode, and a manual pick.
struct VideoQualityTests {
    @Test func theSurfaceLimitsWithoutSettings() {
        #expect(VideoQuality.maxHeight(surface: 1170, manual: nil, limit: nil, isConstrained: false) == 1170)
    }

    @Test func theNetworksLimitApplies() {
        #expect(VideoQuality.maxHeight(surface: 1170, manual: nil, limit: 480, isConstrained: false) == 480)
        #expect(VideoQuality.maxHeight(surface: 360, manual: nil, limit: 720, isConstrained: false) == 360)
    }

    @Test func lowDataModeCapsUnlessTheLimitIsLower() {
        #expect(VideoQuality.maxHeight(surface: 1170, manual: nil, limit: nil, isConstrained: true) == 480)
        #expect(VideoQuality.maxHeight(surface: 1170, manual: nil, limit: 360, isConstrained: true) == 360)
    }

    @Test func aManualPickOverridesEverything() {
        #expect(VideoQuality.maxHeight(surface: 720, manual: 1080, limit: 480, isConstrained: true) == 1080)
    }

    @Test func pickerOffersDecodableHeightsOnce() {
        let capabilities = DecodeCapabilities(av1Hardware: false, vp9Hardware: false, vp9SoftwareMaxHeight: 1440)
        let streams = [video(.av1, 2160), video(.vp9, 2160), video(.vp9, 1440), video(.h264, 1080), video(.vp9, 1080),
                       video(.h264, 720), video(.vp9, 1440, hdr: true)]
        #expect(VideoQuality.heights(in: streams, capabilities: capabilities, allowHDR: false) == [1440, 1080, 720])
    }

    @Test func labels() {
        #expect(VideoQuality.label(2160) == "4K")
        #expect(VideoQuality.label(720) == "720p")
    }

    @Test func aManualPickPlansThatHeightThroughTheSelector() {
        let selector = FormatSelector(capabilities: DecodeCapabilities(av1Hardware: false, vp9Hardware: false,
                                                                       vp9SoftwareMaxHeight: 1440))
        let streams = [video(.h264, 1080), video(.h264, 720), video(.h264, 480)]
        let height = VideoQuality.maxHeight(surface: 1170, manual: 720, limit: nil, isConstrained: false)
        #expect(selector.select(from: streams, for: .avPlayer, maxDisplayHeight: height,
                                throughputBitsPerSecond: nil, allowHDR: false)?.height == 720)
    }
}
