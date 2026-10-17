import Foundation
import Core

/// One feed cell, fully pre-formatted so views do no formatting, date math or sorting in `body`.
public struct FeedRow: Identifiable, Hashable, Sendable {
    public let id: VideoID
    public let channelID: ChannelID
    public let title: String
    public let channelName: String
    /// "1.2M views · 3 days ago"
    public let detail: String
    /// "12:34", "1:02:03", or nil for live/unknown.
    public let durationText: String?
    public let thumbnails: [Thumbnail]
    public let isLive: Bool
    public let isShort: Bool
    /// Watched fraction (0…1) for the progress bar; nil when never started.
    public let progress: Double?
    /// The underlying video, for navigation.
    public let video: VideoSummary
    /// The channel's avatar (from the subscription), and its first letter as a fallback.
    public var channelAvatar: URL? = nil
    public let channelInitial: String
}

/// Formats rows for the current locale. Create one per observation pass, not per row.
public struct RowFormatter: Sendable {
    private let now: Date
    private let locale: Locale

    public init(now: Date = .now, locale: Locale = .current) {
        self.now = now
        self.locale = locale
    }

    public func row(_ video: VideoSummary, positionSeconds: Double?, durationSeconds: Double?) -> FeedRow {
        var parts: [String] = []
        if let views = video.viewCount {
            parts.append(String(localized: "\(views.formatted(.number.notation(.compactName).locale(locale))) views",
                                comment: "View count; the number is already abbreviated, e.g. 1.2M"))
        }
        if video.isLive {
            parts.append(String(localized: "Live", comment: "Badge text for a live stream"))
        } else if let published = video.publishedAt {
            parts.append(published.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(locale)))
        } else if let text = video.publishedText, !text.isEmpty {
            parts.append(text)
        }

        let length = video.duration.map { Double($0.components.seconds) } ?? durationSeconds
        let progress: Double? = if let position = positionSeconds, let length, length > 0, position > 0 {
            min(1, position / length)
        } else {
            nil
        }
        return FeedRow(id: video.id, channelID: video.channelID, title: video.title, channelName: video.channelName,
                       detail: parts.joined(separator: " · "),
                       durationText: video.isLive ? nil : video.duration.map(Self.clock),
                       thumbnails: video.thumbnails, isLive: video.isLive, isShort: video.isShort,
                       progress: progress, video: video, channelInitial: Self.initial(video.channelName))
    }

    static func initial(_ name: String) -> String {
        name.first.map { String($0).uppercased() } ?? "•"
    }

    /// 754 s → "12:34"; 3723 s → "1:02:03".
    public static func clock(_ duration: Duration) -> String {
        let total = Int(duration.components.seconds)
        let hours = total / 3600, minutes = total % 3600 / 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
