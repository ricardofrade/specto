import Foundation

/// YT Zero's internal API (no versioning; mapped from its source, `docs/adr/0002`). Booleans
/// come as 0/1, `duration` is a display string ("12:34"), `published_at` mixes formats.
enum YTZeroDTO {
    struct ErrorBody: Decodable { let error: String?; let code: String? }

    struct Health: Decodable { let status: String?; let app: String?; let version: String? }

    struct Video: Decodable {
        let video_id: String
        let channel_id: String?
        let title: String?
        let description: String?
        let thumbnail: String?
        let published_at: String?
        let live_status: String?
        let is_short: FlexibleBool?
        let views: Int?
        let likes: Int?
        let duration: String?
        let watch_position: Double?
        let watch_duration: Double?
        let watched: FlexibleBool?
        let channel_title: String?

        func summary(images: ImageProxy) -> VideoSummary {
            VideoSummary(id: VideoID(rawValue: video_id), title: title ?? "",
                         channelID: ChannelID(rawValue: channel_id ?? ""), channelName: channel_title ?? "",
                         duration: duration.flatMap(YTZeroDTO.seconds).map { .seconds($0) },
                         publishedAt: published_at.flatMap(YTZeroDTO.date),
                         viewCount: views,
                         thumbnails: thumbnail.flatMap(images.thumbnail).map { [$0] } ?? [],
                         isLive: live_status == "live",
                         isShort: is_short?.value ?? false)
        }

        /// The TV client's resume rule: ignore the first and last 5 seconds.
        var accountVideoState: (resume: Duration?, watched: Bool) {
            let watched = watched?.value ?? false
            guard !watched, let position = watch_position, let length = watch_duration,
                  position >= 5, position < length - 5 else { return (nil, watched) }
            return (.milliseconds(Int64(position * 1000)), watched)
        }
    }

    struct VideoResponse: Decodable { let video: Video; let related: [Video]? }
    struct FeedResponse: Decodable { let videos: [Video]?; let page: Int?; let limit: Int? }

    struct Channel: Decodable {
        let channel_id: String
        let title: String?
        let thumbnail: String?
    }

    struct ChannelsResponse: Decodable { let channels: [Channel]? }
    struct ChannelResponse: Decodable { let channel: Channel? }

    struct Ticket: Decodable {
        let ticket: String?
        let url: String?
        let content_type: String?
        let expires_in: Int?
        let preparing: Bool?
    }

    struct SearchResponse: Decodable {
        struct Result: Decodable {
            let videoId: String
            let title: String?
            let thumbnail: String?
            let duration: FlexibleString?
            let channelId: String?
            let channelTitle: String?
            let viewCount: Int?
        }
        let results: [Result]?
    }

    struct CommentsResponse: Decodable {
        struct Item: Decodable {
            let id: String?
            let parent: String?
            let text: String?
            let author: String?
            let authorId: String?
            let timeText: String?
            let likeCount: Int?
            let isPinned: FlexibleBool?
        }
        let comments: [Item]?
    }

    struct DeviceCode: Decodable {
        let device_code: String
        let user_code: String
        let verification_uri: String
        let verification_uri_complete: String?
        let expires_in: Int
        let interval: Int
    }

    struct Token: Decodable { let access_token: String; let expires_in: Int? }

    /// Accepts JSON booleans and SQLite's 0/1 integers.
    struct FlexibleBool: Decodable {
        let value: Bool
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let bool = try? container.decode(Bool.self) { value = bool }
            else { value = (try? container.decode(Int.self)) ?? 0 != 0 }
        }
    }

    /// Accepts a string or a number (search durations).
    struct FlexibleString: Decodable {
        let value: String
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) { value = string }
            else if let int = try? container.decode(Int.self) { value = "\(int)" }
            else { value = "" }
        }
    }

    /// Remote thumbnails go through the instance's image cache (`/api/img?u=`), so the device
    /// never contacts YouTube's image hosts directly. Those requests need the Bearer token.
    struct ImageProxy: Sendable {
        let base: URL

        func thumbnail(_ remote: String) -> Thumbnail? {
            var components = URLComponents(url: base.appending(path: "api/img"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "u", value: remote)]
            return components?.url.map { Thumbnail(url: $0, width: 0, height: 0) }
        }
    }

    // MARK: Parsing helpers

    /// "12:34" → 754, "1:02:03" → 3723, "75:03" → 4503. Plain seconds also accepted.
    static func seconds(_ display: String) -> Int? {
        let parts = display.split(separator: ":").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        let total = parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
        return total > 0 ? total : nil
    }

    /// ISO-8601 with or without offset, SQLite's "YYYY-MM-DD HH:MM:SS" (UTC), or a bare date.
    static func date(_ text: String) -> Date? {
        let candidates = [text,
                          text.replacingOccurrences(of: " ", with: "T") + "Z",
                          text + "T00:00:00Z"]
        for candidate in candidates {
            if let date = try? Date(candidate, strategy: .iso8601) { return date }
        }
        return nil
    }
}
