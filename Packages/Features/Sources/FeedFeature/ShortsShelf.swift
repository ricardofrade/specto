import SwiftUI
import Core
import Library
import DesignSystem

/// Home's Shorts: tall cards that open the vertical player at the one tapped.
struct ShortsShelf: View {
    let rows: [FeedRow]
    let open: (Int) -> Void
    static let cardWidth: CGFloat = 150
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            Label { Text("Shorts") } icon: { Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled") }
                .font(Tokens.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Tokens.Spacing.screenInset)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Tokens.Spacing.m) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button { open(index) } label: { card(row) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("feed.short")
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Tokens.Spacing.screenInset)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    private func card(_ row: FeedRow) -> some View {
        let size = CGSize(width: Self.cardWidth, height: Self.cardWidth * 16 / 9)
        return Color.clear
            .frame(width: size.width, height: size.height)
            .overlay {
                RemoteImage(row.thumbnails.best(forPixelWidth: Int(size.height * displayScale))?.url, pointSize: size)
            }
            .overlay(alignment: .bottomLeading) {
                Text(row.title)
                    .font(Tokens.Typography.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .padding(Tokens.Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(.rect(cornerRadius: Tokens.Radius.thumbnail))
            .accessibilityElement(children: .combine)
    }
}
