#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit
import Playback

/// Draws a `PreviewPlayer`, filling its box (the hero card crops like its artwork).
public struct PreviewSurface: UIViewRepresentable {
    private let preview: PreviewPlayer

    public init(_ preview: PreviewPlayer) {
        self.preview = preview
    }

    public func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = preview.player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.isUserInteractionEnabled = false
        return view
    }

    public func updateUIView(_ view: LayerView, context: Context) {}

    public final class LayerView: UIView {
        override public class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }   // Guaranteed by layerClass.
    }
}
#endif
