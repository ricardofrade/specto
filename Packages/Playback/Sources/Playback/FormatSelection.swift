import Foundation
import CoreMedia
import VideoToolbox
import Core

/// What this device can decode, queried at runtime. Never decide by device model.
public struct DecodeCapabilities: Sendable, Equatable {
    public let av1Hardware: Bool
    public let vp9Hardware: Bool
    /// Highest VP9 height to attempt in software decode. Tune per device class
    /// after measuring dropped frames (M0 on iPhone, M7 on the A19 Apple TV).
    public var vp9SoftwareMaxHeight: Int

    public init(vp9SoftwareMaxHeight: Int = 1440) {
        self.av1Hardware = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
        // Expected false for third-party apps; VP9 hardware decode has not been available to them.
        self.vp9Hardware = VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9)
        self.vp9SoftwareMaxHeight = vp9SoftwareMaxHeight
    }

    /// For tests.
    public init(av1Hardware: Bool, vp9Hardware: Bool, vp9SoftwareMaxHeight: Int) {
        self.av1Hardware = av1Hardware
        self.vp9Hardware = vp9Hardware
        self.vp9SoftwareMaxHeight = vp9SoftwareMaxHeight
    }

    /// 0 means "don't use this codec on this device".
    public func maxHeight(for codec: VideoCodec) -> Int {
        switch codec {
        case .av1:  av1Hardware ? 2160 : 0
        case .vp9:  vp9Hardware ? 2160 : vp9SoftwareMaxHeight
        case .h264: 1080
        }
    }
}

/// Picks one video stream up front, because mpv does not switch quality mid-stream.
public struct FormatSelector: Sendable {
    public var capabilities: DecodeCapabilities
    /// Share of measured throughput a stream's bitrate may use, leaving headroom for audio and variance.
    public var throughputHeadroom: Double

    public init(capabilities: DecodeCapabilities, throughputHeadroom: Double = 0.7) {
        self.capabilities = capabilities
        self.throughputHeadroom = throughputHeadroom
    }

    /// - Parameters:
    ///   - engine: AVPlayer (on-device HLS) needs MP4; mpv takes anything.
    ///   - maxDisplayHeight: the render surface's height in pixels; no point decoding more.
    ///   - throughputBitsPerSecond: recent measured download speed, nil when unknown.
    ///     Streams without a reported bitrate always pass the budget.
    ///   - allowHDR: false unless the current display and settings support HDR.
    public func select(from streams: [VideoStream],
                       for engine: EngineKind,
                       maxDisplayHeight: Int,
                       throughputBitsPerSecond: Double?,
                       allowHDR: Bool) -> VideoStream? {
        let playable = streams.filter { stream in
            let cap = capabilities.maxHeight(for: stream.codec)
            return cap > 0 && stream.height <= cap && (allowHDR || !stream.isHDR)
                && (engine == .mpv || stream.container == .mp4)
        }

        let budget = throughputBitsPerSecond.map { $0 * throughputHeadroom }
        let fitting = playable.filter { stream in
            guard stream.height <= maxDisplayHeight else { return false }
            if let budget, let bitrate = stream.bitrate, Double(bitrate) > budget { return false }
            return true
        }

        if let best = fitting.min(by: isBetter) {
            return best
        }
        // Nothing fits the budget or display: fall back to the smallest playable stream.
        return playable.min { $0.height != $1.height ? $0.height < $1.height : isBetter($0, $1) }
    }

    /// AVPlayer can only play AAC in MP4. mpv prefers Opus, which sounds better per bit.
    /// - Parameter preferredLanguage: BCP 47 code; matched by primary language ("en" matches "en-US").
    public func selectAudio(from streams: [AudioStream],
                            for engine: EngineKind,
                            preferredLanguage: String?) -> AudioStream? {
        var playable = streams.filter { engine == .mpv || ($0.codec == .aac && $0.container == .mp4) }

        if let preferred = preferredLanguage.map(primaryLanguage) {
            let matching = playable.filter { $0.language.map(primaryLanguage) == preferred }
            if !matching.isEmpty { playable = matching }
        }

        return playable.min { a, b in
            if a.codec != b.codec { return a.codec == .opus }
            return (a.bitrate ?? 0) > (b.bitrate ?? 0)
        }
    }

    private func primaryLanguage(_ code: String) -> String {
        (code.split(separator: "-").first.map(String.init) ?? code).lowercased()
    }

    /// Higher resolution first, then the more efficient codec, then higher frame rate.
    private func isBetter(_ a: VideoStream, _ b: VideoStream) -> Bool {
        if a.height != b.height { return a.height > b.height }
        if rank(a.codec) != rank(b.codec) { return rank(a.codec) < rank(b.codec) }
        return a.fps > b.fps
    }

    private func rank(_ codec: VideoCodec) -> Int {
        switch codec {
        case .av1:  0
        case .vp9:  1
        case .h264: 2
        }
    }
}
