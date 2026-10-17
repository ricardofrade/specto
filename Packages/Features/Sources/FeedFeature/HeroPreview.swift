#if os(iOS)
import SwiftUI
import Core
import Playback
import PlaybackUI

/// The featured video playing muted behind its title, as the Apple TV app's billboard does:
/// after a moment on screen, a short stretch from a little way in, fading over the artwork and
/// back. Gone the moment the card scrolls away or something else plays (the app stops passing a
/// loader).
struct HeroPreview: View {
    let videoID: VideoID
    let duration: Duration?
    let load: (VideoID) async -> StreamManifest?
    /// Owned by Home, so a tap on the card can continue from the preview's moment.
    let preview: PreviewPlayer

    var body: some View {
        PreviewSurface(preview)
            .opacity(preview.isShowing ? 1 : 0)
            .animation(.easeInOut(duration: 0.9), value: preview.isShowing)
            .task(id: videoID) {
                try? await Task.sleep(for: .seconds(1.5))   // A glance at Home shouldn't cost a stream.
                guard !Task.isCancelled, let manifest = await load(videoID), !Task.isCancelled else { return }
                preview.start(manifest, duration: duration)
            }
            .onDisappear { preview.stop() }
            .accessibilityHidden(true)
            .accessibilityIdentifier("hero.preview")
    }
}
#endif
