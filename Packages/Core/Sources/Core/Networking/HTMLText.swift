import Foundation

/// Converts the small HTML subset sources use for descriptions and comments (`<br>`, links,
/// entities) to plain text. `NSAttributedString`'s HTML importer is main-thread only and slow,
/// so this runs anywhere and stays cheap enough for a page of comments.
public enum HTMLText {
    public static func plain(_ html: String) -> String {
        guard html.contains("<") || html.contains("&") else { return html }
        var text = fullLinks(html)
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</p>\s*<p[^>]*>"#, with: "\n\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        if text.contains("&#") { text = decodeNumericEntities(text) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `<a href="https://full/url">https://full/u...</a>`: the visible text is the address,
    /// shortened. Keep the whole address so it can be linked; other link text ("2:00", "#tag")
    /// stays as written.
    private static func fullLinks(_ html: String) -> String {
        guard html.contains("<a") else { return html }
        let ns = html as NSString
        var result = ""
        var last = 0
        for match in anchor.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let href = ns.substring(with: match.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            let label = ns.substring(with: match.range(at: 2))
            let isAddress = label.hasPrefix("http://") || label.hasPrefix("https://") || label.hasPrefix("www.")
            result += isAddress && href.hasPrefix("http") ? href : label
            last = match.range.location + match.range.length
        }
        return result + ns.substring(from: last)
    }

    private static let anchor = try! NSRegularExpression(pattern: #"<a\s[^>]*?href="([^"]*)"[^>]*>([^<]*)</a>"#,
                                                         options: .caseInsensitive)

    private static let entities: [(String, String)] = [
        ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"),
        ("&nbsp;", "\u{00A0}"), ("&amp;", "&"),
    ]

    private static func decodeNumericEntities(_ text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let range = rest.range(of: #"&#(\d+);"#, options: .regularExpression) {
            result += rest[..<range.lowerBound]
            let digits = rest[range].dropFirst(2).dropLast()
            if let value = UInt32(digits), let scalar = Unicode.Scalar(value) {
                result.unicodeScalars.append(scalar)
            } else {
                result += rest[range]
            }
            rest = rest[range.upperBound...]
        }
        return result + rest
    }
}
