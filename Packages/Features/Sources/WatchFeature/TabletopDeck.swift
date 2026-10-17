import SwiftUI
import Core
import Playback
import DesignSystem

/// An iPhone Duo folded on a table: the half that rests flat becomes the remote. The video is
/// above, untouched; here are the title, the timeline (chapters and SponsorBlock colours), big
/// transport controls that never fade, and what's up next.
struct TabletopDeck: View {
    let session: PlaybackSession
    let content: WatchContent
    let actions: PlayerActions

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            HStack(alignment: .top, spacing: Tokens.Spacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: content.title).font(.headline).lineLimit(1)
                    Text(verbatim: content.channelName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: Tokens.Spacing.m)
                PlayerTopControls(session: session, actions: actions)
                    .equatable()
            }
            PlayerScrubber(session: session, storyboard: content.storyboard, chapters: content.chapters,
                           onInteraction: {})
            PlayerControlCluster(isPlaying: session.state == .playing,
                                 captionsAvailable: !actions.captions.isEmpty, scale: 1.3) { action in
                switch action {
                case .togglePlayback: session.state == .playing ? session.pause() : session.resume()
                case .skipBack: Task { await session.seek(to: max(.zero, session.position - .seconds(10)), precise: true) }
                case .skipForward: Task { await session.seek(to: session.position + .seconds(10), precise: true) }
                case .captions: actions.toggleCaptions()
                }
            }
            .frame(maxWidth: .infinity)
            if let upNext = actions.upNext {
                UpNextCard(upNext: upNext, cancel: actions.cancelUpNext, playNow: actions.playUpNextNow)
            }
            Spacer(minLength: 0)
        }
        .padding(Tokens.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.55))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch.tabletopDeck")
        .sensoryFeedback(.selection, trigger: session.state == .playing)
    }
}
