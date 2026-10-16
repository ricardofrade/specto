import SwiftUI
import UIKit
import Playback

/// Hosts the active engine's render layer. Attaches when it enters a window and detaches
/// when it leaves; `PlaybackSession` ignores a stale detach, so SwiftUI building the new
/// surface before tearing down the old one (fold, rotation, split-screen) never blanks video.
public struct PlayerSurface: UIViewRepresentable {
    private let session: PlaybackSession

    public init(session: PlaybackSession) {
        self.session = session
    }

    public func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.session = session
        return view
    }

    public func updateUIView(_ view: PlayerSurfaceView, context: Context) {
        view.session = session
    }

    public static func dismantleUIView(_ view: PlayerSurfaceView, coordinator: ()) {
        view.session?.detach(view)
    }
}

public final class PlayerSurfaceView: UIView, RenderSurfaceHost {
    weak var session: PlaybackSession?

    public var containerLayer: CALayer { layer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Video")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            session?.attach(self)
        } else {
            session?.detach(self)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        session?.hostDidLayout(self)
    }
}
