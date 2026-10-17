import Foundation

/// One subtitle line and when it shows.
public struct SubtitleCue: Sendable, Equatable {
    public let start: Duration
    public let end: Duration
    public let text: String

    public init(start: Duration, end: Duration, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// WebVTT, as Piped and Invidious serve it. Subtitles are drawn by the app over either engine,
/// so they look the same with mpv and AVPlayer, on every platform.
public enum WebVTT {
    /// Cues in time order. Inline markup (`<c>`, `<i>`, karaoke timestamps in YouTube's
    /// auto-generated captions) is removed, and a line that only repeats the previous cue's last
    /// line (auto-captions roll) is dropped.
    public static func parse(_ text: String) -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timing = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timing].components(separatedBy: "-->")
            guard parts.count == 2, let start = time(parts[0]),
                  let end = time(parts[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "")
            else { continue }
            var body = lines[(timing + 1)...].map(strip).filter { !$0.isEmpty }
            if let previous = cues.last?.text.components(separatedBy: "\n").last, body.first == previous {
                body.removeFirst()
            }
            guard !body.isEmpty, end > start else { continue }
            cues.append(SubtitleCue(start: start, end: end, text: body.joined(separator: "\n")))
        }
        return cues.sorted { $0.start < $1.start }
    }

    /// "01:02:03.456" or "02:03.456".
    static func time(_ raw: String) -> Duration? {
        let fields = raw.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard (2...3).contains(fields.count) else { return nil }
        let secondsParts = fields[fields.count - 1].split(separator: ".")
        guard let seconds = Int(secondsParts[0]), let minutes = Int(fields[fields.count - 2]) else { return nil }
        let hours = fields.count == 3 ? Int(fields[0]) ?? 0 : 0
        let millis = secondsParts.count > 1 ? Int(secondsParts[1].prefix(3).padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0 : 0
        return .milliseconds(Int64(((hours * 60 + minutes) * 60 + seconds) * 1000 + millis))
    }

    private static func strip(_ line: String) -> String {
        line.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// The cue showing at `position`, by binary search (cues are sorted by start).
    public static func cue(at position: Duration, in cues: [SubtitleCue]) -> SubtitleCue? {
        var low = 0, high = cues.count - 1, found: Int?
        while low <= high {
            let middle = (low + high) / 2
            if cues[middle].start <= position { found = middle; low = middle + 1 } else { high = middle - 1 }
        }
        guard let index = found, position < cues[index].end else { return nil }
        return cues[index]
    }
}
