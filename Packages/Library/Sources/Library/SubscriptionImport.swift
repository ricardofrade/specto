import Foundation
import Core

/// Reads subscription exports so a new user is set up in seconds: Google Takeout
/// (`subscriptions.csv`), NewPipe/FreeTube/Piped JSON, and OPML.
public enum SubscriptionImport {
    public enum Failure: Error, Equatable {
        case unrecognisedFormat
        case empty
    }

    public static func parse(_ data: Data) throws -> [ChannelSummary] {
        let channels: [ChannelSummary]
        if let json = try? JSONSerialization.jsonObject(with: data) {
            channels = fromJSON(json)
        } else if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("<") {
                channels = fromOPML(data)
            } else if trimmed.lowercased().hasPrefix("channel id") {
                channels = fromTakeoutCSV(trimmed)
            } else {
                throw Failure.unrecognisedFormat
            }
        } else {
            throw Failure.unrecognisedFormat
        }
        // De-duplicate, keeping the first name seen.
        var seen = Set<ChannelID>()
        let unique = channels.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { throw Failure.empty }
        return unique
    }

    /// "UC" + 22 characters, from a bare id or any YouTube/Piped/Invidious channel URL.
    static func channelID(in text: String) -> ChannelID? {
        guard let range = text.range(of: #"UC[A-Za-z0-9_-]{22}"#, options: .regularExpression) else { return nil }
        return ChannelID(rawValue: String(text[range]))
    }

    /// NewPipe: `{"subscriptions":[{"url","name"}]}`. Piped: `{"subscriptions":["UC…"]}` or
    /// `[{"channelId","name"}]`. FreeTube profiles: `[{"subscriptions":[{"id","name"}]}]`.
    private static func fromJSON(_ json: Any) -> [ChannelSummary] {
        var found: [ChannelSummary] = []
        func visit(_ value: Any) {
            switch value {
            case let string as String:
                if let id = channelID(in: string) { found.append(ChannelSummary(id: id, name: "", avatar: nil)) }
            case let object as [String: Any]:
                let idText = ["url", "channelId", "id", "channel_id"].lazy.compactMap { object[$0] as? String }.first
                if let idText, let id = channelID(in: idText) {
                    let name = ["name", "title", "channelName"].lazy.compactMap { object[$0] as? String }.first ?? ""
                    found.append(ChannelSummary(id: id, name: name, avatar: nil))
                } else {
                    object.values.forEach(visit)
                }
            case let array as [Any]:
                array.forEach(visit)
            default:
                break
            }
        }
        visit(json)
        return found
    }

    /// Takeout: `Channel Id,Channel Url,Channel Title` (titles may be quoted and contain commas).
    private static func fromTakeoutCSV(_ text: String) -> [ChannelSummary] {
        text.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
            let fields = csvFields(String(line))
            guard let first = fields.first, let id = channelID(in: first) else { return nil }
            return ChannelSummary(id: id, name: fields.count > 2 ? fields[2] : "", avatar: nil)
        }
    }

    private static func csvFields(_ line: String) -> [String] {
        var fields: [String] = [], current = "", quoted = false
        var justClosedQuote = false
        for character in line {
            if quoted {
                if character == "\"" { quoted = false; justClosedQuote = true; continue }
                current.append(character)
            } else if character == "\"" {
                // `""` inside a quoted field: the closing quote was really a literal one.
                if justClosedQuote { current.append("\"") }
                quoted = true
            } else if character == "," {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
            justClosedQuote = false
        }
        fields.append(current)
        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// OPML from YouTube, NewPipe or feed readers: `<outline xmlUrl="…channel_id=UC…" title="…"/>`.
    private static func fromOPML(_ data: Data) -> [ChannelSummary] {
        final class Delegate: NSObject, XMLParserDelegate {
            var channels: [ChannelSummary] = []
            func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                        qualifiedName: String?, attributes: [String: String] = [:]) {
                guard element.lowercased() == "outline",
                      let source = attributes["xmlUrl"] ?? attributes["htmlUrl"] ?? attributes["url"],
                      let id = SubscriptionImport.channelID(in: source) else { return }
                channels.append(ChannelSummary(id: id, name: attributes["title"] ?? attributes["text"] ?? "", avatar: nil))
            }
        }
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.channels
    }
}
