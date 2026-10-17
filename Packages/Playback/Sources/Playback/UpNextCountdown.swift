import Foundation
import Core

/// Autoplay: the video that plays when this one ends with nothing queued, and the countdown
/// before it does ("Up next in 5"), pre-formatted for the card.
public struct UpNextCountdown: Equatable, Sendable {
    public static let seconds = 5

    public let video: VideoSummary
    public private(set) var secondsLeft: Int
    public private(set) var label: String

    public init(video: VideoSummary, secondsLeft: Int = UpNextCountdown.seconds) {
        self.video = video
        self.secondsLeft = secondsLeft
        label = Self.label(secondsLeft)
    }

    public mutating func tick(_ secondsLeft: Int) {
        self.secondsLeft = secondsLeft
        label = Self.label(secondsLeft)
    }

    /// The first related video worth autoplaying: not this one, not live, not a Short.
    public static func candidate(in related: [VideoSummary], after current: VideoID) -> VideoSummary? {
        related.first { $0.id != current && !$0.isLive && !$0.isShort }
    }

    private static func label(_ seconds: Int) -> String {
        String(localized: "Up next in \(seconds)")
    }
}
