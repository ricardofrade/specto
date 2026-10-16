import SwiftUI
import Core
import Playback
import DesignSystem

/// The current video while the Watch screen is closed. Lives in the tab bar's bottom
/// accessory (a system Liquid Glass surface), so it adds no glass of its own.
public struct MiniPlayerBar: View {
    private let session: PlaybackSession
    private let onOpen: () -> Void

    public init(session: PlaybackSession, onOpen: @escaping () -> Void) {
        self.session = session
        self.onOpen = onOpen
    }

    public var body: some View {
        if let item = session.item {
            HStack(spacing: Tokens.Spacing.m) {
                RemoteImage(item.artworkURL, pointSize: CGSize(width: 56, height: 32))
                    .frame(width: 56, height: 32)
                    .clipShape(.rect(cornerRadius: Tokens.Spacing.xs))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title).font(Tokens.Typography.caption.weight(.semibold)).lineLimit(1)
                    Text(item.channelName).font(Tokens.Typography.caption).foregroundStyle(Tokens.Colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    session.state == .playing ? session.pause() : session.resume()
                } label: {
                    Image(systemName: session.state == .playing ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(session.state == .playing ? Text("Pause") : Text("Play"))
            }
            .padding(.horizontal, Tokens.Spacing.m)
            .contentShape(.rect)
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("miniplayer")
        }
    }
}
