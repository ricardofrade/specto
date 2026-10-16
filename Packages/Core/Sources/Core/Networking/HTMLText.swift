import Foundation

/// Converts the small HTML subset sources use for descriptions and comments (`<br>`, links,
/// entities) to plain text. `NSAttributedString`'s HTML importer is main-thread only and slow,
/// so this runs anywhere and stays cheap enough for a page of comments.
public enum HTMLText {
    public static func plain(_ html: String) -> String {
        guard html.contains("<") || html.contains("&") else { return html }
        var text = html
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</p>\s*<p[^>]*>"#, with: "\n\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        if text.contains("&#") { text = decodeNumericEntities(text) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
