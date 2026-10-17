import AVFoundation
import Core
import Observation

/// A muted preview of a video behind Home's featured title (like the Apple TV app's): its own
/// small AVPlayer at the lowest H.264 stream, a few seconds in to skip intros. It never touches
/// `PlaybackSession`; the app starts it only on Wi-Fi without Low Data, Low Power or Reduce
/// Motion (ADR 0015).
@MainActor
@Observable
public final class PreviewPlayer {
    /// True once frames are moving, false again when the preview ends: the view fades on it.
    public private(set) var isShowing = false
    @ObservationIgnored public let player = AVPlayer()
    @ObservationIgnored private var prepared: LocalHLS.Prepared?
    @ObservationIgnored private var run: Task<Void, Never>?

    public init() {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.automaticallyWaitsToMinimizeStalling = true
    }

    /// Plays `length` of the video from `fraction` of the way in, then fades back to the artwork.
    public func start(_ manifest: StreamManifest, duration: Duration?, fraction: Double = 0.2,
                      length: Duration = .seconds(24)) {
        stop()
        run = Task { [weak self] in
            guard let self, let (asset, prepared) = await Self.asset(for: manifest), !Task.isCancelled else { return }
            self.prepared = prepared
            let item = AVPlayerItem(asset: asset)
            item.preferredPeakBitRate = 1_500_000
            item.preferredMaximumResolution = CGSize(width: 640, height: 360)
            player.replaceCurrentItem(with: item)
            let deadline = ContinuousClock.now + .seconds(15)
            while item.status == .unknown, ContinuousClock.now < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard item.status == .readyToPlay, !Task.isCancelled else { return }
            if let duration, duration > .seconds(60) {
                let seconds = Double(duration.components.seconds) * fraction
                await item.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .positiveInfinity,
                                toleranceAfter: .positiveInfinity)
            }
            player.play()
            // Wait for frames to move before showing, so the fade never reveals a black box.
            while player.timeControlStatus != .playing, ContinuousClock.now < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(250))
            isShowing = true
            try? await Task.sleep(for: length)
            guard !Task.isCancelled else { return }
            isShowing = false
            try? await Task.sleep(for: .seconds(1))   // The fade out.
            if !Task.isCancelled { player.pause() }
        }
    }

    /// Where the preview is while it shows: tapping the card continues from here.
    public var position: Duration? {
        guard isShowing else { return nil }
        let seconds = player.currentTime().seconds
        return seconds.isFinite && seconds > 0 ? .milliseconds(Int64(seconds * 1000)) : nil
    }

    public func stop() {
        run?.cancel()
        run = nil
        isShowing = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        prepared = nil
    }

    /// HLS when the instance gives it; else the smallest H.264 stream through a local HLS
    /// playlist, as the main AVPlayer engine does (its audio stays muted).
    private static func asset(for manifest: StreamManifest) async -> (AVURLAsset, LocalHLS.Prepared?)? {
        if let hls = manifest.hlsURL { return (AVURLAsset(url: hls), nil) }
        let video = manifest.videoStreams
            .filter { $0.codec == .h264 && $0.container == .mp4 && $0.height >= 240 }
            .min { $0.height < $1.height }
        let audio = manifest.audioStreams.filter { $0.codec == .aac }.min { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
        guard let video, let audio, let ready = try? await LocalHLS.prepare(video: video, audio: audio) else { return nil }
        return (ready.asset, ready)
    }
}
