import SwiftUI

/// What a list looks like while its first page loads: cells in the final layout, redacted, so
/// the screen has its shape at once and nothing jumps when the content arrives.
public struct VideoCellPlaceholder: View {
    private let style: VideoCell.Style
    private let thumbnailWidth: CGFloat

    public init(style: VideoCell.Style = .stacked, thumbnailWidth: CGFloat) {
        self.style = style
        self.thumbnailWidth = thumbnailWidth
    }

    public var body: some View {
        VideoCell(VideoCellContent(title: "A video title that runs onto a second line", channelName: "Channel name",
                                   detail: "1.2M views · 3 days ago", durationText: nil, thumbnailURL: nil,
                                   isLive: false, progress: nil),
                  style: style, thumbnailWidth: thumbnailWidth)
            .redacted(reason: .placeholder)
            .accessibilityHidden(true)
    }
}

/// A column of placeholders, and the label VoiceOver reads instead.
public struct LoadingPlaceholders: View {
    private let count: Int
    private let style: VideoCell.Style
    private let thumbnailWidth: CGFloat

    public init(count: Int = 6, style: VideoCell.Style = .row, thumbnailWidth: CGFloat = 160) {
        self.count = count
        self.style = style
        self.thumbnailWidth = thumbnailWidth
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            ForEach(0..<count, id: \.self) { _ in
                VideoCellPlaceholder(style: style, thumbnailWidth: thumbnailWidth)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading"))
        .accessibilityIdentifier("loading.placeholders")
    }
}
