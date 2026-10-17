import Foundation
import Core

/// What the person asks to play (ADR 0017): Auto lets the planner choose (codec policy, and
/// AVPlayer when it's as good); a codec narrows the streams to it; HLS plays the instance's
/// HLS stream.
public enum StreamFormat: String, CaseIterable, Sendable, Codable {
    case auto, av1, vp9, h264, hls

    var codec: VideoCodec? {
        switch self {
        case .av1: .av1
        case .vp9: .vp9
        case .h264: .h264
        case .auto, .hls: nil
        }
    }

    /// The choices a video offers: its codecs this device decodes, and HLS when the instance
    /// gives it. Auto is always first.
    public static func options(for manifest: StreamManifest, capabilities: DecodeCapabilities) -> [StreamFormat] {
        let codecs = Set(manifest.videoStreams.map(\.codec))
        var options: [StreamFormat] = [.auto]
        if codecs.contains(.av1), capabilities.av1Hardware { options.append(.av1) }
        if codecs.contains(.vp9) { options.append(.vp9) }
        if codecs.contains(.h264) { options.append(.h264) }
        if manifest.hlsURL != nil { options.append(.hls) }
        return options
    }
}

extension StreamManifest {
    /// The same manifest with only these video streams.
    func keeping(videoStreams: [VideoStream]) -> StreamManifest {
        StreamManifest(videoID: videoID, videoStreams: videoStreams, audioStreams: audioStreams, hlsURL: hlsURL,
                       muxedURL: muxedURL, dashURL: dashURL, captions: captions, storyboards: storyboards,
                       chapters: chapters, expiresAt: expiresAt)
    }
}
