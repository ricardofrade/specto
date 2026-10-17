import Foundation
import Core

/// Pre-formatted transport strings for a position: built when the position changes, not in `body`.
public struct TransportClock: Equatable, Sendable {
    public var elapsed = ""
    public var remaining = ""
    /// Played fraction, 0…1.
    public var fraction = 0.0
    public var chapterTitle: String?
    public var chapterIndex: Int?

    public init() {}

    public init(position: Duration, duration: Duration?, chapters: [Chapter] = []) {
        elapsed = Self.format(position, longest: duration)
        if let duration, duration > .zero {
            remaining = "-" + Self.format(max(.zero, duration - position), longest: duration)
            fraction = min(1, max(0, position / duration))
        }
        chapterIndex = chapters.lastIndex { $0.start <= position }
        chapterTitle = chapterIndex.map { chapters[$0].title }
    }

    /// "4:05", or "1:02:03" when the video is an hour or longer.
    public static func format(_ value: Duration, longest: Duration?) -> String {
        let hours = (longest ?? value) >= .seconds(3600)
        return value.formatted(.time(pattern: hours ? .hourMinuteSecond : .minuteSecond))
    }
}
