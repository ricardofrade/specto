import AVFoundation
import AVKit
import Core
import Playback

/// Picture-in-Picture for mpv playback by handing off to AVPlayer (M0 spike 7).
/// libmpv can't feed an `AVSampleBufferDisplayLayer` efficiently (its render API is OpenGL or
/// software only), so PiP plays the same video through on-device HLS from mpv's position.
@MainActor
public final class PictureInPictureHandoff: NSObject, AVPictureInPictureControllerDelegate {
    public struct Timing: Sendable, Equatable {
        /// Fetching segment indexes and writing playlists.
        public let prepare: Duration
        /// AVPlayer ready at mpv's position and PiP possible.
        public let ready: Duration
        /// Total from request to the PiP window starting.
        public let total: Duration
    }

    public enum Failure: Error, Equatable {
        /// `AVPictureInPictureController.isPictureInPictureSupported()` is false on this device.
        case unsupported
        case controllerUnavailable
        case notReady
    }

    public private(set) var isActive = false
    public private(set) var lastTiming: Timing?
    /// Called with AVPlayer's position when PiP ends, so mpv resumes from there.
    public var onStop: ((Duration) -> Void)?

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var controller: AVPictureInPictureController?
    private var prepared: LocalHLS.Prepared?

    public func start(video: VideoStream, audio: AudioStream, at position: Duration, in host: CALayer) async throws {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { throw Failure.unsupported }
        let begin = ContinuousClock.now
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try AVAudioSession.sharedInstance().setActive(true)

        let prepared = try await LocalHLS.prepare(video: video, audio: audio)
        let prepareDone = ContinuousClock.now
        self.prepared = prepared

        let item = AVPlayerItem(asset: prepared.asset)
        let player = AVPlayer(playerItem: item)
        let layer = AVPlayerLayer(player: player)
        layer.frame = host.bounds
        layer.videoGravity = .resizeAspect
        host.insertSublayer(layer, at: 0)      // Under mpv's layer: PiP needs it in the hierarchy.
        self.player = player
        playerLayer = layer

        let controller = try AVPictureInPictureController(playerLayer: layer).unwrapped()
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.controller = controller

        try await waitUntil { item.status == .readyToPlay || item.status == .failed }
        guard item.status == .readyToPlay else { throw Failure.notReady }
        await item.seek(to: CMTime(seconds: Self.seconds(position), preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
        try await waitUntil { controller.isPictureInPicturePossible }
        let ready = ContinuousClock.now

        player.play()
        controller.startPictureInPicture()
        try await waitUntil { self.isActive }
        lastTiming = Timing(prepare: prepareDone - begin, ready: ready - prepareDone, total: ContinuousClock.now - begin)
    }

    public func stop() {
        controller?.stopPictureInPicture()
    }

    // MARK: AVPictureInPictureControllerDelegate

    public nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated { isActive = true }
    }

    public nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            isActive = false
            let seconds = player?.currentTime().seconds ?? 0
            player?.pause()
            playerLayer?.removeFromSuperlayer()
            player = nil
            playerLayer = nil
            prepared = nil
            onStop?(.milliseconds(Int64(seconds * 1000)))
        }
    }

    // MARK: Helpers

    private func waitUntil(timeout: Duration = .seconds(15), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw Failure.notReady }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

private extension Optional {
    func unwrapped() throws -> Wrapped {
        guard let value = self else { throw PictureInPictureHandoff.Failure.controllerUnavailable }
        return value
    }
}
