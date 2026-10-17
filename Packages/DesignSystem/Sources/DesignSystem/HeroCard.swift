import SwiftUI

/// The featured video at the top of Home: large artwork with the title over a gradient and a
/// glass Play capsule. At accessibility text sizes the text moves below the artwork instead,
/// so nothing is clipped.
public struct HeroCard<Preview: View>: View, Equatable {
    private let content: VideoCellContent
    private let width: CGFloat
    private let preview: Preview
    @Environment(\.dynamicTypeSize) private var typeSize

    /// - Parameters:
    ///   - width: the card's width in points; the artwork is requested at that size.
    ///   - preview: drawn over the artwork, under the title (Home's muted preview).
    public init(_ content: VideoCellContent, width: CGFloat, @ViewBuilder preview: () -> Preview) {
        self.content = content
        self.width = width
        self.preview = preview()
    }

    /// 4:3, taller than the 16:9 artwork (cropped at the sides), so the title has room on a phone;
    /// on wide windows the height stops here rather than filling the screen.
    public static var maxHeight: CGFloat { 460 }
    private var height: CGFloat { min(width * 3 / 4, Self.maxHeight) }

    nonisolated public static func == (lhs: HeroCard, rhs: HeroCard) -> Bool {
        lhs.content == rhs.content && lhs.width == rhs.width
    }

    public var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
                    artwork.clipShape(.rect(cornerRadius: Tokens.Radius.card))
                    text(onArtwork: false)
                }
            } else {
                artwork
                    .overlay(alignment: .bottomLeading) {
                        text(onArtwork: true)
                            .padding(Tokens.Spacing.xl)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                               .init(color: .black.opacity(0.55), location: 0.35),
                                                               .init(color: .black.opacity(0.85), location: 1)],
                                                       startPoint: .top, endPoint: .bottom))
                    }
                    .clipShape(.rect(cornerRadius: Tokens.Radius.card))
                    .overlay {
                        RoundedRectangle(cornerRadius: Tokens.Radius.card)
                            .strokeBorder(Tokens.Colors.separator.opacity(0.5), lineWidth: 0.5)
                    }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Requested at the size it fills (wider than the card, since the sides are cropped).
    private var artwork: some View {
        let fill = max(width, height * 16 / 9)
        return RemoteImage(content.thumbnailURL, pointSize: CGSize(width: fill, height: fill * 9 / 16))
            .frame(width: width, height: height)
            .overlay { preview }
            .clipped()
    }

    private func text(onArtwork: Bool) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Text(content.title)
                .font(Tokens.Typography.heroTitle)
                .lineLimit(onArtwork ? 3 : nil)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tokens.Spacing.xs) {
                    Text(content.channelName)
                    if !content.detail.isEmpty { Text(verbatim: "·"); Text(content.detail) }
                }
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                    Text(content.channelName)
                    if !content.detail.isEmpty { Text(content.detail) }
                }
            }
            .font(Tokens.Typography.cellMeta)
            .opacity(0.85)
            Label { Text("Play") } icon: { Image(systemName: "play.fill") }
                .font(.headline)
                .padding(.horizontal, Tokens.Spacing.l)
                .padding(.vertical, Tokens.Spacing.s)
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.top, Tokens.Spacing.xs)
        }
        .foregroundStyle(onArtwork ? .white : Tokens.Colors.textPrimary)
    }
}

extension HeroCard where Preview == EmptyView {
    public init(_ content: VideoCellContent, width: CGFloat) {
        self.init(content, width: width) { EmptyView() }
    }
}
