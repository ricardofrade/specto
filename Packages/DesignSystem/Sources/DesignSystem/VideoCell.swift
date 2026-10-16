import SwiftUI

/// Everything a video cell shows, pre-formatted by the store layer.
public struct VideoCellContent: Hashable, Sendable {
    public var title: String
    public var channelName: String
    public var detail: String
    public var durationText: String?
    public var thumbnailURL: URL?
    public var isLive: Bool
    /// Watched fraction (0…1), or nil.
    public var progress: Double?

    public init(title: String, channelName: String, detail: String, durationText: String?, thumbnailURL: URL?,
                isLive: Bool, progress: Double?) {
        self.title = title
        self.channelName = channelName
        self.detail = detail
        self.durationText = durationText
        self.thumbnailURL = thumbnailURL
        self.isLive = isLive
        self.progress = progress
    }
}

/// The video cell shared by the feed, search and channel screens. Shallow tree, no
/// `GeometryReader`, `Equatable` so unchanged cells are skipped.
public struct VideoCell: View, Equatable {
    public enum Style: Sendable { case stacked, row }

    private let content: VideoCellContent
    private let style: Style
    /// The thumbnail's laid-out width in points; the image pipeline requests exactly that.
    private let thumbnailWidth: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize

    public init(_ content: VideoCellContent, style: Style = .stacked, thumbnailWidth: CGFloat) {
        self.content = content
        self.style = style
        self.thumbnailWidth = thumbnailWidth
    }

    /// Inputs only; environment changes (such as text size) still re-render.
    nonisolated public static func == (lhs: VideoCell, rhs: VideoCell) -> Bool {
        lhs.content == rhs.content && lhs.style == rhs.style && lhs.thumbnailWidth == rhs.thumbnailWidth
    }

    public var body: some View {
        switch style {
        case .stacked:
            VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
                thumbnail
                text(titleLines: 2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        case .row:
            HStack(alignment: .top, spacing: Tokens.Spacing.m) {
                thumbnail.frame(width: thumbnailWidth)
                text(titleLines: 2)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
    }

    private var thumbnail: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                RemoteImage(content.thumbnailURL,
                            pointSize: CGSize(width: thumbnailWidth, height: thumbnailWidth * 9 / 16))
            }
            .overlay(alignment: .bottomTrailing) {
                if content.isLive {
                    Badge(text: String(localized: "LIVE"), tint: Tokens.Colors.liveBadge)
                } else if let duration = content.durationText {
                    Badge(text: duration, tint: .black.opacity(0.75))
                }
            }
            .overlay(alignment: .bottom) {
                if let progress = content.progress {
                    ProgressBar(fraction: progress)
                }
            }
            .clipShape(.rect(cornerRadius: Tokens.Radius.thumbnail))
    }

    /// At accessibility text sizes nothing is truncated: the cell grows instead.
    private func text(titleLines: Int) -> some View {
        let wraps = typeSize.isAccessibilitySize
        return VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            Text(content.title)
                .font(style == .stacked ? Tokens.Typography.cellTitle : Tokens.Typography.cellMeta.weight(.semibold))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .lineLimit(wraps ? nil : titleLines)
            Text(content.channelName)
                .font(style == .stacked ? Tokens.Typography.cellMeta : Tokens.Typography.caption)
                .foregroundStyle(Tokens.Colors.textSecondary)
                .lineLimit(wraps ? nil : 1)
            if !content.detail.isEmpty {
                Text(content.detail)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .lineLimit(wraps ? nil : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
