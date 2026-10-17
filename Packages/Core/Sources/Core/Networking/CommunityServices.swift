import CryptoKit
import Foundation

/// A SponsorBlock segment to skip.
public struct SkipSegment: Hashable, Sendable {
    public enum Category: String, Sendable, CaseIterable, Codable {
        case sponsor, selfpromo, interaction, intro, outro, preview, music_offtopic, filler

        /// SponsorBlock's own colour for the category (as its extension draws it on the seek bar),
        /// 0–1 per channel; views turn it into a `Color`.
        public var rgb: (red: Double, green: Double, blue: Double) {
            switch self {
            case .sponsor: (0, 0.83, 0)                  // #00D400
            case .selfpromo: (1, 1, 0)                   // #FFFF00
            case .interaction: (0.8, 0, 1)               // #CC00FF
            case .intro: (0, 1, 1)                       // #00FFFF
            case .outro: (0.008, 0.008, 0.93)            // #0202ED
            case .preview: (0, 0.56, 0.84)               // #008FD6
            case .music_offtopic: (1, 0.6, 0)            // #FF9900
            case .filler: (0.45, 0, 1)                   // #7300FF
            }
        }

        /// For settings: "Sponsor", "Intro".
        public var title: String {
            switch self {
            case .sponsor: String(localized: "Sponsor")
            case .selfpromo: String(localized: "Self-promotion")
            case .interaction: String(localized: "Interaction reminder")
            case .intro: String(localized: "Intro")
            case .outro: String(localized: "End cards and credits")
            case .preview: String(localized: "Preview and recap")
            case .music_offtopic: String(localized: "Non-music section")
            case .filler: String(localized: "Filler and tangents")
            }
        }

        /// For "Skipped <name>" notices.
        public var localizedName: String {
            switch self {
            case .sponsor: String(localized: "sponsor")
            case .selfpromo: String(localized: "self-promotion")
            case .interaction: String(localized: "reminder to subscribe")
            case .intro: String(localized: "intro")
            case .outro: String(localized: "end cards")
            case .preview: String(localized: "preview")
            case .music_offtopic: String(localized: "non-music section")
            case .filler: String(localized: "filler")
            }
        }
    }

    public let category: Category
    public let start: Duration
    public let end: Duration

    public init(category: Category, start: Duration, end: Duration) {
        self.category = category
        self.start = start
        self.end = end
    }
}

/// Community-sourced title and thumbnail replacements (DeArrow).
public struct Branding: Hashable, Sendable {
    public let title: String?
    /// Seconds into the video for a community-chosen thumbnail frame.
    public let thumbnailTime: Double?

    public init(title: String?, thumbnailTime: Double?) {
        self.title = title
        self.thumbnailTime = thumbnailTime
    }

    /// DeArrow's thumbnail service renders the chosen frame. Unlike the hash-prefix lookups,
    /// this request names the video, so it's a separate, opt-in setting.
    public static func thumbnail(for id: VideoID, at seconds: Double) -> Thumbnail? {
        var components = URLComponents(string: "https://dearrow-thumb.ajay.app/api/v1/getThumbnail")
        components?.queryItems = [URLQueryItem(name: "videoID", value: id.rawValue),
                                  URLQueryItem(name: "time", value: String(format: "%.2f", seconds))]
        return components?.url.map { Thumbnail(url: $0, width: 0, height: 0) }
    }
}

/// SponsorBlock and DeArrow, queried by the first four hex characters of the video ID's SHA-256,
/// so the services never learn which video is being watched (k-anonymity). The matching entry
/// is picked out locally.
public struct CommunityServices: Sendable {
    public static let defaultBase = URL(string: "https://sponsor.ajay.app")!
    private let base: URL
    private let client: any HTTPClient

    public init(base: URL = CommunityServices.defaultBase, client: any HTTPClient = URLSessionHTTPClient()) {
        self.base = base
        self.client = client
    }

    static func hashPrefix(_ id: VideoID) -> String {
        SHA256.hash(data: Data(id.rawValue.utf8)).prefix(2).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: SponsorBlock

    public func skipSegments(for id: VideoID, categories: Set<SkipSegment.Category>) async throws -> [SkipSegment] {
        guard !categories.isEmpty else { return [] }
        struct Entry: Decodable {
            struct Segment: Decodable {
                let category: String
                let actionType: String?
                let segment: [Double]
            }
            let videoID: String
            let segments: [Segment]
        }
        let encoded = try String(decoding: JSONEncoder().encode(categories.map(\.rawValue).sorted()), as: UTF8.self)
        var components = URLComponents(url: base.appending(path: "api/skipSegments/\(Self.hashPrefix(id))"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "categories", value: encoded),
                                 URLQueryItem(name: "actionTypes", value: #"["skip"]"#)]
        let (data, response) = try await client.data(for: URLRequest(url: components.url!, timeoutInterval: 8))
        if response.statusCode == 404 { return [] }      // No segments in this bucket.
        guard (200..<300).contains(response.statusCode) else { throw SourceError.http(status: response.statusCode) }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        return (entries.first { $0.videoID == id.rawValue }?.segments ?? []).compactMap { segment in
            guard segment.actionType ?? "skip" == "skip", segment.segment.count == 2,
                  let category = SkipSegment.Category(rawValue: segment.category),
                  segment.segment[1] > segment.segment[0] else { return nil }
            return SkipSegment(category: category,
                               start: .milliseconds(Int64(segment.segment[0] * 1000)),
                               end: .milliseconds(Int64(segment.segment[1] * 1000)))
        }.sorted { $0.start < $1.start }
    }

    // MARK: DeArrow

    /// Branding for every video in the same hash bucket; callers keep the ones they need.
    public func branding(for ids: [VideoID]) async throws -> [VideoID: Branding] {
        struct Entry: Decodable {
            struct Title: Decodable { let title: String; let original: Bool?; let votes: Int?; let locked: Bool? }
            struct Thumb: Decodable { let timestamp: Double?; let original: Bool?; let votes: Int?; let locked: Bool? }
            let titles: [Title]?
            let thumbnails: [Thumb]?
        }
        let wanted = Set(ids)
        var result: [VideoID: Branding] = [:]
        for prefix in Set(ids.map(Self.hashPrefix)) {
            let url = base.appending(path: "api/branding/\(prefix)")
            let (data, response) = try await client.data(for: URLRequest(url: url, timeoutInterval: 8))
            guard (200..<300).contains(response.statusCode) else { continue }
            let entries = try JSONDecoder().decode([String: Entry].self, from: data)
            for (key, entry) in entries {
                let id = VideoID(rawValue: key)
                guard wanted.contains(id) else { continue }
                // DeArrow's display rule: the top entry, if it isn't the original and has
                // non-negative votes or is locked.
                let title = entry.titles?.first.flatMap { t in
                    (t.original != true && ((t.votes ?? 0) >= 0 || t.locked == true)) ? Self.clean(t.title) : nil
                }
                let thumb = entry.thumbnails?.first.flatMap { t in
                    (t.original != true && ((t.votes ?? 0) >= 0 || t.locked == true)) ? t.timestamp : nil
                }
                if title != nil || thumb != nil { result[id] = Branding(title: title, thumbnailTime: thumb) }
            }
        }
        return result
    }

    /// DeArrow marks words to keep as typed with a leading ">"; display them without it.
    static func clean(_ title: String) -> String {
        title.replacingOccurrences(of: #"(^|\s)>(\S)"#, with: "$1$2", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
