import Foundation

/// Parses the Atom feed `/feed/channel/{ucid}`: the latest 15 uploads with exact timestamps,
/// but no durations or live flags.
enum ChannelFeedParser {
    static func parse(_ data: Data) -> [VideoSummary] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.videos
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var videos: [VideoSummary] = []
        private var entry: [String: String]?
        private var text = ""
        private var authorDepth = false

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch element {
            case "entry": entry = [:]
            case "author": authorDepth = true
            case "media:thumbnail": entry?["thumbnail"] = attributes["url"]
            case "media:statistics": entry?["views"] = attributes["views"]
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                    qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch element {
            case "yt:videoId": entry?["id"] = value
            case "yt:channelId": entry?["channel"] = value
            case "title": if entry != nil { entry?["title"] = value }
            case "name": if authorDepth { entry?["author"] = value }
            case "author": authorDepth = false
            case "published": entry?["published"] = value
            case "entry":
                if let entry, let video = Self.video(from: entry) { videos.append(video) }
                entry = nil
            default: break
            }
        }

        private static func video(from entry: [String: String]) -> VideoSummary? {
            guard let id = entry["id"], let channel = entry["channel"] else { return nil }
            return VideoSummary(id: VideoID(rawValue: id), title: entry["title"] ?? "",
                                channelID: ChannelID(rawValue: channel), channelName: entry["author"] ?? "",
                                duration: nil,
                                publishedAt: entry["published"].flatMap { try? Date($0, strategy: .iso8601) },
                                viewCount: entry["views"].flatMap(Int.init),
                                thumbnails: entry["thumbnail"].flatMap(Thumbnail.unsized).map { [$0] } ?? [],
                                // The feed doesn't say; Shorts ship under /shorts/ links we don't see here.
                                isShort: false)
        }
    }
}
