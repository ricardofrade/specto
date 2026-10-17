import Foundation

/// Preview frames for scrubbing: sprite sheets ("pages") of `columns × rows` small frames, one
/// every `interval`. Only from Piped, whose frames come through the instance's proxy (Invidious
/// redirects storyboards to Google, which would reveal the device; not used).
public struct Storyboard: Hashable, Sendable, Codable {
    public let pages: [URL]
    public let frameWidth: Int
    public let frameHeight: Int
    public let columns: Int
    public let rows: Int
    public let frameCount: Int
    public let intervalMilliseconds: Int

    public init(pages: [URL], frameWidth: Int, frameHeight: Int, columns: Int, rows: Int,
                frameCount: Int, intervalMilliseconds: Int) {
        self.pages = pages
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.columns = columns
        self.rows = rows
        self.frameCount = frameCount
        self.intervalMilliseconds = intervalMilliseconds
    }

    /// Where a frame sits: its page, and its origin in that page in pixels.
    public struct Frame: Hashable, Sendable {
        public let page: URL
        public let x: Int
        public let y: Int
    }

    public var pageWidth: Int { frameWidth * columns }
    public var pageHeight: Int { frameHeight * rows }

    /// The frame showing at `position`, or nil if there's none.
    public func frame(at position: Duration) -> Frame? {
        guard frameCount > 0, intervalMilliseconds > 0, columns > 0, rows > 0 else { return nil }
        let millis = Int(position.components.seconds) * 1000 + Int(position.components.attoseconds / 1_000_000_000_000_000)
        let index = min(frameCount - 1, max(0, millis / intervalMilliseconds))
        let perPage = columns * rows
        let page = index / perPage, inPage = index % perPage
        guard page < pages.count else { return nil }
        return Frame(page: pages[page], x: (inPage % columns) * frameWidth, y: (inPage / columns) * frameHeight)
    }
}

extension Array where Element == Storyboard {
    /// The smallest storyboard whose frames are at least `width` pixels wide, else the largest.
    public func best(forFrameWidth width: Int) -> Storyboard? {
        sorted { $0.frameWidth < $1.frameWidth }.first { $0.frameWidth >= width } ?? self.max { $0.frameWidth < $1.frameWidth }
    }
}
