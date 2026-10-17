import Foundation

/// A video description with its links made tappable, built once when details arrive (never in
/// `body`): web links open in the browser, YouTube video links open in this app, and timestamps
/// ("12:34", "1:02:03") seek the video.
nonisolated public enum DescriptionText {
    /// `specto-seek:<seconds>`, handled by the Watch screen's `openURL`.
    public static let seekScheme = "specto-seek"

    public static func attributed(_ text: String, appScheme: String = "dev.placeholder.specto") -> AttributedString {
        var result = AttributedString(text)
        let ns = text as NSString

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let url = match.url, let range = Range(match.range, in: result) else { continue }
                result[range].link = videoID(in: url).flatMap { URL(string: "\(appScheme)://watch?v=\($0)") } ?? url
            }
        }

        for match in timestamp.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            func number(_ group: Int) -> Int? {
                let range = match.range(at: group)
                return range.location == NSNotFound ? nil : Int(ns.substring(with: range))
            }
            let hours = number(1)
            guard let minutes = number(2), let seconds = number(3), seconds < 60, hours == nil || minutes < 60,
                  let range = Range(match.range, in: result), result[range].link == nil else { continue }
            result[range].link = URL(string: "\(seekScheme):\((hours ?? 0) * 3600 + minutes * 60 + seconds)")
        }
        return result
    }

    /// "12:34" or "1:02:03", not inside a longer run of digits and colons.
    private static let timestamp = try! NSRegularExpression(pattern: #"(?<![\d:])(?:(\d{1,2}):)?(\d{1,2}):(\d{2})(?![\d:])"#)

    /// More than about six lines on a phone: worth a More button.
    public static func isLong(_ text: String) -> Bool {
        text.count > 280 || text.reduce(0) { $1 == "\n" ? $0 + 1 : $0 } >= 6
    }

    /// The seconds a seek link points at.
    public static func seconds(in url: URL) -> Int? {
        guard url.scheme == seekScheme else { return nil }
        return Int(url.absoluteString.dropFirst(seekScheme.count + 1))
    }

    /// youtube.com/watch?v=…, youtu.be/…, youtube.com/shorts/…, and any front end's
    /// /watch?v=<11-character ID> (Piped and Invidious rewrite YouTube links to their own host).
    static func videoID(in url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        if url.path() == "/watch",
           let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value,
           id.wholeMatch(of: /[A-Za-z0-9_-]{11}/) != nil {
            return id
        }
        if host == "youtu.be" { return url.pathComponents.dropFirst().first }
        guard host == "youtube.com" || host.hasSuffix(".youtube.com") else { return nil }
        let parts = url.pathComponents
        if parts.count >= 3, parts[1] == "shorts" || parts[1] == "live" { return parts[2] }
        return nil
    }
}
