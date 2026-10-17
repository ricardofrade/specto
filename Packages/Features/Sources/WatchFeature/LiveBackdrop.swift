import SwiftUI
import Core
import Playback
import DesignSystem

/// The light behind the Watch screen follows the video: the scrubbing preview's frame for the
/// current moment (the storyboard the player already has), blurred to colour, cross-fading
/// every few seconds. Without a storyboard, the thumbnail's tint, as before.
struct LiveBackdrop: View {
    let session: PlaybackSession
    let storyboard: Storyboard?
    let thumbnail: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Only the moment's bucket changes this view, not every position update.
        LiveBackdropFrame(storyboard: reduceMotion ? nil : storyboard, thumbnail: thumbnail,
                          moment: Int(session.position.components.seconds) / Self.step)
            .equatable()
    }

    static let step = 6
}

private struct LiveBackdropFrame: View, Equatable {
    let storyboard: Storyboard?
    let thumbnail: URL?
    let moment: Int
    @State private var size = CGSize(width: 390, height: 844)
    @Environment(\.colorScheme) private var colorScheme

    nonisolated static func == (lhs: LiveBackdropFrame, rhs: LiveBackdropFrame) -> Bool {
        lhs.moment == rhs.moment && lhs.thumbnail == rhs.thumbnail && (lhs.storyboard == nil) == (rhs.storyboard == nil)
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(thumbnail)
            if let storyboard, let frame = storyboard.frame(at: .seconds(moment * LiveBackdrop.step)) {
                Color.clear
                    .overlay {
                        StoryboardFrameView(page: frame.page, origin: CGPoint(x: frame.x, y: frame.y),
                                            frameSize: CGSize(width: storyboard.frameWidth, height: storyboard.frameHeight),
                                            pageSize: CGSize(width: storyboard.pageWidth, height: storyboard.pageHeight),
                                            displayWidth: Self.width)
                            .scaleEffect(max(size.width / Self.width, size.height / (Self.width * 9 / 16)))
                    }
                    .blur(radius: 50, opaque: true)
                    .saturation(1.4)
                    .overlay(Tokens.Colors.background.opacity(colorScheme == .dark ? 0.5 : 0.7))
                    .id(moment)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 2), value: moment)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private static let width: CGFloat = 48
}
