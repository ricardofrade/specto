import Foundation
import Core

/// Turns a watch page into what an engine plays: codec policy and format selection for
/// adaptive streams, HLS for live, and single-URL sources (YT Zero) as they come.
///
/// Engine policy for video (ADR 0005): AVPlayer when it can play a stream as good as mpv's
/// pick (same height and HDR, AAC audio), for automatic Picture-in-Picture, AirPlay and
/// lower power; mpv when it would play something better (VP9 above 1080p, webm-only videos).
public struct PlaybackPlanner: Sendable {
    public var selector: FormatSelector
    /// BCP 47; nil plays the original audio track.
    public var preferredAudioLanguage: String?
    /// Off plays all video in mpv (the pre-ADR-0005 behaviour).
    public var prefersSystemPlayer: Bool
    /// The person's pick (ADR 0017); `.auto` leaves it to the policy above.
    public var format: StreamFormat = .auto

    public init(selector: FormatSelector, preferredAudioLanguage: String? = nil, prefersSystemPlayer: Bool = true) {
        self.selector = selector
        self.preferredAudioLanguage = preferredAudioLanguage
        self.prefersSystemPlayer = prefersSystemPlayer
    }

    /// - Parameters:
    ///   - maxDisplayHeight: the surface height in pixels (no point decoding more).
    ///   - throughputBitsPerSecond: recent measured download speed; nil when unknown.
    public func request(for page: WatchPage, mode: PlaybackMode, maxDisplayHeight: Int,
                        throughputBitsPerSecond: Double?, allowHDR: Bool,
                        startAt: Duration = .zero) throws -> PlaybackRequest {
        var manifest = page.manifest
        // A codec picked by hand narrows the streams to it (when the video has it); AV1 and VP9
        // stay in mpv rather than turning into AVPlayer's H.264.
        if let codec = format.codec {
            let streams = manifest.videoStreams.filter { $0.codec == codec }
            if !streams.isEmpty { manifest = manifest.keeping(videoStreams: streams) }
        }
        var planner = self
        if format == .av1 || format == .vp9 { planner.prefersSystemPlayer = false }
        return try planner.plan(page, manifest: manifest, mode: mode, maxDisplayHeight: maxDisplayHeight,
                                throughputBitsPerSecond: throughputBitsPerSecond, allowHDR: allowHDR, startAt: startAt)
    }

    private func plan(_ page: WatchPage, manifest: StreamManifest, mode: PlaybackMode, maxDisplayHeight: Int,
                      throughputBitsPerSecond: Double?, allowHDR: Bool, startAt: Duration) throws -> PlaybackRequest {
        let engine = EngineKind.preferred(for: mode)
        var chosenEngine: EngineKind?
        let source: MediaSource

        if page.details.summary.isLive, let hls = manifest.hlsURL {
            source = .hls(hls)
        } else if format == .hls, mode == .video, let hls = manifest.hlsURL {
            source = .hls(hls)
            if prefersSystemPlayer { chosenEngine = .avPlayer }
        } else if let audio = selector.selectAudio(from: manifest.audioStreams, for: engine,
                                                   preferredLanguage: preferredAudioLanguage) {
            if mode == .audioOnly {
                source = .adaptive(video: nil, audio: audio)
            } else if let video = selector.select(from: manifest.videoStreams, for: engine,
                                                  maxDisplayHeight: maxDisplayHeight,
                                                  throughputBitsPerSecond: throughputBitsPerSecond,
                                                  allowHDR: allowHDR) {
                if let system = systemPlayerEquivalent(of: video, in: manifest, maxDisplayHeight: maxDisplayHeight,
                                                       throughputBitsPerSecond: throughputBitsPerSecond, allowHDR: allowHDR) {
                    source = .adaptive(video: system.video, audio: system.audio)
                    chosenEngine = .avPlayer
                } else {
                    source = .adaptive(video: video, audio: audio)
                    chosenEngine = engine
                }
            } else if let hls = manifest.hlsURL {
                source = .hls(hls)
            } else if let muxed = manifest.muxedURL {
                source = .progressive(muxed)
            } else {
                throw PlaybackError.unsupportedFormat("No video stream this device can play")
            }
        } else if let hls = manifest.hlsURL {
            source = .hls(hls)
            // YT Zero: one H.264/AAC rendition over HLS, which AVPlayer plays natively.
            if mode == .video, prefersSystemPlayer { chosenEngine = .avPlayer }
        } else if let muxed = manifest.muxedURL {
            source = .progressive(muxed)
        } else {
            throw PlaybackError.unsupportedFormat("The source returned no playable streams")
        }
        return PlaybackRequest(videoID: manifest.videoID, source: source, startAt: startAt, mode: mode,
                               engine: chosenEngine)
    }

    /// AVPlayer's best pick when it's as good as mpv's: at least as tall, same HDR, with AAC audio.
    private func systemPlayerEquivalent(of best: VideoStream, in manifest: StreamManifest, maxDisplayHeight: Int,
                                        throughputBitsPerSecond: Double?,
                                        allowHDR: Bool) -> (video: VideoStream, audio: AudioStream)? {
        guard prefersSystemPlayer,
              let video = selector.select(from: manifest.videoStreams, for: .avPlayer, maxDisplayHeight: maxDisplayHeight,
                                          throughputBitsPerSecond: throughputBitsPerSecond, allowHDR: allowHDR),
              video.height >= best.height, video.isHDR == best.isHDR,
              let audio = selector.selectAudio(from: manifest.audioStreams, for: .avPlayer,
                                               preferredLanguage: preferredAudioLanguage) else { return nil }
        return (video, audio)
    }
}
