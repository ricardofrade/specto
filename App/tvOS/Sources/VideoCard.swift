import SwiftUI
import Core
import Library
import DesignSystem

/// A focusable thumbnail card (the system card style lifts it under focus) with the title and
/// channel below. Long press offers the channel and the queue.
struct VideoCard: View {
    let row: FeedRow
    let actions: VideoActions
    /// Shown last in the long-press menu (Library: "Remove from History").
    var remove: (label: Text, action: () -> Void)?
    /// The channel's avatar beside the title (Home).
    var showsAvatar = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            Button { actions.play(row.video) } label: {
                thumbnail
            }
            .buttonStyle(.card)
            .contextMenu {
                Button { actions.openChannel(row.channelID, row.channelName) } label: {
                    Label { Text("Go to Channel") } icon: { Image(systemName: "person.crop.circle") }
                }
                Button { actions.addToQueue(row.video) } label: {
                    Label { Text("Add to Queue") } icon: { Image(systemName: "text.badge.plus") }
                }
                Button { actions.setWatched(row.video, !row.isWatched) } label: {
                    if row.isWatched {
                        Label { Text("Mark as Unwatched") } icon: { Image(systemName: "eye.slash") }
                    } else {
                        Label { Text("Mark as Watched") } icon: { Image(systemName: "checkmark.circle") }
                    }
                }
                Button { actions.hideChannel(row.channelID) } label: {
                    Label { Text("Hide \(row.channelName) from Home") } icon: { Image(systemName: "rectangle.slash") }
                }
                if let remove {
                    Button(role: .destructive, action: remove.action) {
                        Label { remove.label } icon: { Image(systemName: "trash") }
                    }
                }
            }
            HStack(alignment: .top, spacing: 14) {
                if showsAvatar {
                    ZStack {
                        Circle().fill(Tokens.Colors.accent.opacity(0.25))
                        Text(verbatim: row.channelInitial).font(.caption.weight(.bold))
                        if let avatar = row.channelAvatar {
                            RemoteImage(avatar, pointSize: CGSize(width: 44, height: 44)).clipShape(.circle)
                        }
                    }
                    .frame(width: 44, height: 44)
                }
                titles
            }
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            Text(row.title).font(.callout.weight(.medium)).lineLimit(2)
            Text(row.channelName).font(.caption).foregroundStyle(Tokens.Colors.textSecondary).lineLimit(1)
            if !row.detail.isEmpty {
                Text(row.detail).font(.caption2).foregroundStyle(Tokens.Colors.textSecondary).lineLimit(1)
            }
        }
    }

    private var thumbnail: some View {
        let pointSize = CGSize(width: TVMetrics.cardWidth, height: TVMetrics.cardWidth * 9 / 16)
        return Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                RemoteImage(row.thumbnails.best(forPixelWidth: Int(pointSize.width * displayScale))?.url,
                            pointSize: pointSize)
            }
            .overlay(alignment: .bottomTrailing) {
                if let duration = row.durationText {
                    Text(duration).font(.caption2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, Tokens.Spacing.s).padding(.vertical, Tokens.Spacing.xxs)
                        .background(.black.opacity(0.75), in: .rect(cornerRadius: 6))
                        .foregroundStyle(.white)
                        .padding(Tokens.Spacing.s)
                }
            }
            .overlay(alignment: .bottom) {
                if let progress = row.progress {
                    // Scaled rather than measured: no GeometryReader in cells.
                    Rectangle().fill(Tokens.Colors.watchProgress)
                        .frame(height: 6)
                        .scaleEffect(x: progress, y: 1, anchor: .leading)
                }
            }
    }
}

/// What a card can do; the root supplies the behaviour.
struct VideoActions {
    var play: (VideoSummary) -> Void
    let openChannel: (ChannelID, String) -> Void
    let addToQueue: (VideoSummary) -> Void
    let openPlaylist: (PlaylistSummary) -> Void
    /// Plays `videos[start]`, then the rest in order.
    let playPlaylist: (_ videos: [VideoSummary], _ start: Int) -> Void
    let setWatched: (VideoSummary, Bool) -> Void
    let hideChannel: (ChannelID) -> Void
}
