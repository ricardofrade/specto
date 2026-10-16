import Foundation
import Core

/// Turns a watch page into what an engine plays: codec policy and format selection for
/// adaptive streams, HLS for live, and single-URL sources (YT Zero) as they come.
public struct PlaybackPlanner: Sendable {
    public var selector: FormatSelector
    /// BCP 47; nil plays the original audio track.
    public var preferredAudioLanguage: String?

    public init(selector: FormatSelector, preferredAudioLanguage: String? = nil) {
        self.selector = selector
        self.preferredAudioLanguage = preferredAudioLanguage
    }

    /// - Parameters:
    ///   - maxDisplayHeight: the surface height in pixels (no point decoding more).
    ///   - throughputBitsPerSecond: recent measured download speed; nil when unknown.
    public func request(for page: WatchPage, mode: PlaybackMode, maxDisplayHeight: Int,
                        throughputBitsPerSecond: Double?, allowHDR: Bool,
                        startAt: Duration = .zero) throws -> PlaybackRequest {
        let manifest = page.manifest
        let engine = EngineKind.preferred(for: mode)
        let source: MediaSource

        if page.details.summary.isLive, let hls = manifest.hlsURL {
            source = .hls(hls)
        } else if let audio = selector.selectAudio(from: manifest.audioStreams, for: engine,
                                                   preferredLanguage: preferredAudioLanguage) {
            if mode == .audioOnly {
                source = .adaptive(video: nil, audio: audio)
            } else if let video = selector.select(from: manifest.videoStreams, for: engine,
                                                  maxDisplayHeight: maxDisplayHeight,
                                                  throughputBitsPerSecond: throughputBitsPerSecond,
                                                  allowHDR: allowHDR) {
                source = .adaptive(video: video, audio: audio)
            } else if let hls = manifest.hlsURL {
                source = .hls(hls)
            } else {
                throw PlaybackError.unsupportedFormat("No video stream this device can play")
            }
        } else if let hls = manifest.hlsURL {
            source = .hls(hls)
        } else if let muxed = manifest.muxedURL {
            source = .progressive(muxed)
        } else {
            throw PlaybackError.unsupportedFormat("The source returned no playable streams")
        }
        return PlaybackRequest(videoID: manifest.videoID, source: source, startAt: startAt, mode: mode)
    }
}
