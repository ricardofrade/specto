import Foundation
import QuartzCore
import Core

public enum EngineKind: String, Sendable, Hashable {
    /// libmpv: video, DASH with separate audio and video, AV1/VP9/H.264.
    case mpv
    /// AVPlayer: audio-only mode, CarPlay, AirPlay, HLS. MP4/AAC only, no webm.
    case avPlayer

    public static func preferred(for mode: PlaybackMode) -> EngineKind {
        switch mode {
        case .video: .mpv
        case .audioOnly: .avPlayer
        }
    }
}

public enum PlaybackMode: Sendable, Hashable {
    case video
    case audioOnly
}

public enum PlaybackError: Error, Sendable, Equatable {
    /// A stream URL was rejected (HTTP 403/410): it expired or is bound to another IP.
    /// Recover by refetching the manifest and resuming at the current position.
    case streamExpired
    case network
    case unsupportedFormat(String)
    case decoder(String)
    case other(String)
}

public enum PlaybackState: Sendable, Equatable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case ended
    case failed(PlaybackError)
}

public struct DecoderInfo: Sendable, Equatable {
    public let codec: VideoCodec
    public let isHardware: Bool
    public let width: Int
    public let height: Int

    public init(codec: VideoCodec, isHardware: Bool, width: Int, height: Int) {
        self.codec = codec
        self.isHardware = isHardware
        self.width = width
        self.height = height
    }
}

public struct PlaybackStats: Sendable, Equatable {
    public let droppedFrames: Int
    public let bufferedAhead: Duration
    /// Recent download speed; feeds `FormatSelector` for the next video.
    public let throughputBitsPerSecond: Double?

    public init(droppedFrames: Int, bufferedAhead: Duration, throughputBitsPerSecond: Double?) {
        self.droppedFrames = droppedFrames
        self.bufferedAhead = bufferedAhead
        self.throughputBitsPerSecond = throughputBitsPerSecond
    }
}

public enum PlaybackEvent: Sendable {
    case state(PlaybackState)
    /// Emitted at most a few times per second; never per frame.
    case position(Duration, duration: Duration?)
    case decoder(DecoderInfo)
    /// About once per second.
    case stats(PlaybackStats)
}

public enum MediaSource: Sendable, Hashable {
    /// Separate streams. `video` is nil in audio-only mode.
    case adaptive(video: VideoStream?, audio: AudioStream)
    /// Live streams, or a playlist synthesised on device for AVPlayer.
    case hls(URL)
    /// One file with video and audio muxed together (for example a server-side download).
    case progressive(URL)
}

public struct PlaybackRequest: Sendable {
    public var videoID: VideoID
    public var source: MediaSource
    public var caption: CaptionTrack?
    public var startAt: Duration
    public var mode: PlaybackMode

    public init(videoID: VideoID, source: MediaSource, caption: CaptionTrack? = nil,
                startAt: Duration = .zero, mode: PlaybackMode) {
        self.videoID = videoID
        self.source = source
        self.caption = caption
        self.startAt = startAt
        self.mode = mode
    }
}

/// A view-owned container. The engine inserts its own render layer
/// (CAMetalLayer, AVPlayerLayer, AVSampleBufferDisplayLayer) as a sublayer
/// and keeps it sized to the container's bounds.
@MainActor
public protocol RenderSurfaceHost: AnyObject {
    var containerLayer: CALayer { get }
}

@MainActor
public protocol PlaybackEngine: AnyObject {
    var kind: EngineKind { get }

    /// Single consumer: `PlaybackSession` subscribes once, when it creates the engine.
    var events: AsyncStream<PlaybackEvent> { get }

    /// Initialize the engine without media so the first `load` is fast.
    func prewarm()

    /// Replaces any current media. Once called, the engine must not emit events for the
    /// previous media. Throws `PlaybackError`.
    func load(_ request: PlaybackRequest) async throws
    func play()
    func pause()
    func seek(to position: Duration, precise: Bool) async
    func setRate(_ rate: Float)

    /// Stop playback and release media, keeping the engine warm for reuse.
    func stop()

    /// Move the render layer into `host`. Called again with a new host after fold,
    /// unfold, rotation or split-screen; playback must continue without a reload.
    func attach(_ host: any RenderSurfaceHost)
    func detach()

    /// The host's bounds changed; resize the render layer.
    func layoutSurface()
}
