import SwiftUI
import Core
import DesignSystem

/// Avatars of the channels on Home, newest upload first. Tapping one shows only its videos;
/// tapping it again, or All, shows everyone's.
struct ChannelStrip: View, Equatable {
    let channels: [FeedChannel]
    let selected: ChannelID?
    let select: (ChannelID?) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    nonisolated static func == (lhs: ChannelStrip, rhs: ChannelStrip) -> Bool {
        lhs.channels == rhs.channels && lhs.selected == rhs.selected
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Tokens.Spacing.m) {
                if selected != nil {
                    Button { select(nil) } label: {
                        item(name: Text("All")) {
                            Image(systemName: "square.grid.2x2")
                                .font(.title3)
                                .foregroundStyle(Tokens.Colors.accent)
                                .frame(width: Self.avatarSize, height: Self.avatarSize)
                                .background(Tokens.Colors.accent.opacity(0.15), in: .circle)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("feed.allChannels")
                }
                ForEach(channels) { channel in
                    let isSelected = selected == channel.id
                    Button { select(channel.id) } label: {
                        item(name: Text(verbatim: channel.name)) {
                            AvatarView(channel.avatar, size: Self.avatarSize)
                                .overlay {
                                    Circle().strokeBorder(Tokens.Colors.accent, lineWidth: 2.5)
                                        .padding(-4)
                                        .opacity(isSelected ? 1 : 0)
                                }
                                .opacity(selected == nil || isSelected ? 1 : 0.45)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: channel.name))
                    .accessibilityHint(Text("Shows only this channel's videos"))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("feed.channel")
                }
            }
            .padding(.horizontal, Tokens.Spacing.screenInset)
            .padding(.vertical, 4)   // Room for the selection ring.
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: selected)
        .animation(Tokens.Motion.standard, value: selected)
    }

    /// The avatar, with the name under it (left out at accessibility sizes, where the name
    /// would be a letter or two wide; VoiceOver still reads it).
    private func item(name: Text, @ViewBuilder avatar: () -> some View) -> some View {
        VStack(spacing: Tokens.Spacing.xs) {
            avatar()
            if !typeSize.isAccessibilitySize {
                name.font(.caption2)
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .lineLimit(1)
                    .frame(width: Self.avatarSize + 12)
            }
        }
    }

    static let avatarSize: CGFloat = 52
}
