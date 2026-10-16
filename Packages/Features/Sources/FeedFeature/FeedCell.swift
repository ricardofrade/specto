import SwiftUI
import Library
import DesignSystem

/// One feed entry. Pure presentation of a pre-formatted `FeedRow`: no formatting, no
/// `GeometryReader`, shallow tree, `Equatable` so SwiftUI skips unchanged cells.
struct FeedCell: View, Equatable {
    let row: FeedRow

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
            Thumbnail(row: row)
            Text(row.title)
                .font(Tokens.Typography.cellTitle)
                .foregroundStyle(Tokens.Colors.textPrimary)
                .lineLimit(2)
            Text(row.channelName)
                .font(Tokens.Typography.cellMeta)
                .foregroundStyle(Tokens.Colors.textSecondary)
                .lineLimit(1)
            if !row.detail.isEmpty {
                Text(row.detail)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct Thumbnail: View {
    let row: FeedRow

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                // Replaced by the downsampling image pipeline in M2.
                AsyncImage(url: row.thumbnails.first?.url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Tokens.Colors.thumbnailPlaceholder
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if row.isLive {
                    Badge(text: String(localized: "LIVE"), tint: Tokens.Colors.liveBadge)
                } else if let duration = row.durationText {
                    Badge(text: duration, tint: .black.opacity(0.75))
                }
            }
            .overlay(alignment: .bottom) {
                if let progress = row.progress {
                    ProgressBar(fraction: progress)
                }
            }
            .clipShape(.rect(cornerRadius: Tokens.Radius.thumbnail))
    }
}

private struct Badge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(Tokens.Typography.timecode)
            .foregroundStyle(.white)
            .padding(.horizontal, Tokens.Spacing.xs + Tokens.Spacing.xxs)
            .padding(.vertical, Tokens.Spacing.xxs)
            .background(tint, in: .rect(cornerRadius: Tokens.Spacing.xs))
            .padding(Tokens.Spacing.s)
    }
}

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.35))
            .frame(height: 3)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Tokens.Colors.watchProgress)
                    .scaleEffect(x: fraction, anchor: .leading)
            }
            .accessibilityHidden(true)
    }
}
