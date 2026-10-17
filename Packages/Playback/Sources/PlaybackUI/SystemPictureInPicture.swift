import AVFoundation
import AVKit

/// Picture-in-Picture while AVPlayer plays the video (ADR 0005): starts by itself when the app
/// leaves the foreground, or from the PiP button. mpv video uses `PictureInPictureHandoff`.
@MainActor
public final class SystemPictureInPicture: NSObject, AVPictureInPictureControllerDelegate {
    public private(set) var isActive = false
    /// From `willStart`, which comes before the app reaches the background, so background
    /// handling knows to keep the video attached.
    public private(set) var isStarting = false
    private var controller: AVPictureInPictureController?
    private weak var layer: AVPlayerLayer?

    /// Follows the session: a controller on AVPlayer's layer while it plays video, none otherwise.
    public func update(layer newLayer: AVPlayerLayer?) {
        guard newLayer !== layer else { return }
        controller?.delegate = nil
        controller = nil
        layer = newLayer
        guard let newLayer, AVPictureInPictureController.isPictureInPictureSupported(),
              let controller = AVPictureInPictureController(playerLayer: newLayer) else { return }
        #if !os(tvOS)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        #endif
        controller.delegate = self
        self.controller = controller
    }

    public func start() {
        controller?.startPictureInPicture()
    }

    /// Back in the app: the video returns to its inline layer, as in Apple's own apps.
    public func stop() {
        guard isActive else { return }
        controller?.stopPictureInPicture()
    }

    // MARK: AVPictureInPictureControllerDelegate (AVKit calls these on the main thread)

    public nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated { isStarting = true }
    }

    public nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            isStarting = false
            isActive = true
        }
    }

    public nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                       failedToStartPictureInPictureWithError error: any Error) {
        MainActor.assumeIsolated { isStarting = false }
    }

    public nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated {
            isStarting = false
            isActive = false
        }
    }

    /// The video is still in the app's own layer, so there's nothing to restore.
    public nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}
