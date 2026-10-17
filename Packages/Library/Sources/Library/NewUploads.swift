import Foundation
import Core

/// Which feed videos are worth a "new upload" notification: published after the last time the
/// person saw the feed (or was notified), not live, newest first.
public enum NewUploads {
    /// - Parameter muted: channels whose uploads never notify (Library → Channels).
    public static func select(from rows: [FeedRow], since: Date, excluding muted: Set<ChannelID> = []) -> [FeedRow] {
        rows.filter { row in
            guard let published = row.video.publishedAt, !row.isLive, !muted.contains(row.channelID) else { return false }
            return published > since
        }
        .sorted { ($0.video.publishedAt ?? .distantPast) > ($1.video.publishedAt ?? .distantPast) }
    }
}
