import Foundation

/// Invidious's wire format. Several numbers are strings (`itag`, `bitrate`, `clen`), byte
/// ranges are "start-end" strings, and `published` is unix seconds.
enum InvidiousDTO {
    struct ErrorBody: Decodable { let error: String? }

    struct Stats: Decodable {
        struct Software: Decodable { let name: String?; let version: String? }
        let software: Software?
    }

    struct Image: Decodable {
        let url: String
        let width: Int?
        let height: Int?

        var thumbnail: Thumbnail {
            Thumbnail(url: URL(string: url) ?? URL(filePath: "/"), width: width ?? 0, height: height ?? 0)
        }
    }

    /// Search results, trending, channel videos and playlist entries share this shape.
    struct Item: Decodable {
        let type: String?
        let title: String?
        let videoId: String?
        let author: String?
        let authorId: String?
        let videoThumbnails: [Image]?
        let viewCount: Int64?
        let published: Int64?
        let publishedText: String?
        let lengthSeconds: Int?
        let liveNow: Bool?
        let index: Int?

        var videoSummary: VideoSummary? {
            guard type == nil || type == "video", let videoId, let authorId else { return nil }
            return VideoSummary(
                id: VideoID(rawValue: videoId), title: title ?? "", channelID: ChannelID(rawValue: authorId),
                channelName: author ?? "",
                duration: lengthSeconds.flatMap { $0 > 0 ? .seconds($0) : nil },
                publishedAt: published.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil },
                publishedText: publishedText,
                viewCount: viewCount.flatMap { $0 > 0 ? Int($0) : nil },
                thumbnails: InvidiousDTO.thumbnails(videoThumbnails),
                isLive: liveNow ?? false)
        }
    }

    struct ChannelHome: Decodable {
        let author: String?
        let authorThumbnails: [Image]?
    }

    struct ChannelPlaylists: Decodable {
        let playlists: [PlaylistItem]?
        let continuation: String?
    }

    struct PlaylistItem: Decodable {
        let playlistId: String?
        let title: String?
        let videoCount: Int?
        let playlistThumbnail: String?

        /// The thumbnail points at i.ytimg.com; the instance serves the same image (`/vi/<id>/…`),
        /// so the device never talks to Google. `author` is unreliable here ("Playlist"), so the
        /// channel name is left to the caller.
        func playlistSummary(instance: URL) -> PlaylistSummary? {
            guard let playlistId else { return nil }
            let video = playlistThumbnail.flatMap(URL.init(string:)).flatMap { url -> String? in
                let parts = url.pathComponents
                guard let index = parts.firstIndex(of: "vi"), parts.indices.contains(index + 1) else { return nil }
                return parts[index + 1]
            }
            let thumbnail = video.map {
                Thumbnail(url: instance.appending(path: "vi/\($0)/mqdefault.jpg"), width: 320, height: 180)
            }
            return PlaylistSummary(id: PlaylistID(rawValue: playlistId), title: title ?? "", channelName: nil,
                                   videoCount: videoCount, thumbnails: thumbnail.map { [$0] } ?? [])
        }
    }

    struct ChannelVideos: Decodable {
        let videos: [Item]?
        let continuation: String?
    }

    struct Playlist: Decodable {
        let title: String?
        let author: String?
        let videoCount: Int?
        let videos: [Item]?
    }

    struct CommentsPage: Decodable {
        let comments: [CommentItem]?
        let continuation: String?
    }

    struct CommentItem: Decodable {
        struct Replies: Decodable { let replyCount: Int?; let continuation: String? }
        let commentId: String?
        let author: String?
        let authorId: String?
        let content: String?
        let published: Int64?
        let publishedText: String?
        let likeCount: Int?
        let isPinned: Bool?
        let replies: Replies?

        var comment: Comment {
            Comment(id: commentId ?? UUID().uuidString, authorName: author ?? "",
                    authorChannelID: authorId.map(ChannelID.init(rawValue:)), text: content ?? "",
                    likeCount: likeCount,
                    // Reconstructed from "x ago" by Invidious, so only the text is trustworthy.
                    publishedAt: nil, publishedText: publishedText,
                    isPinned: isPinned ?? false, replyCount: replies?.replyCount ?? 0,
                    repliesCursor: replies?.continuation)
        }
    }

    struct Video: Decodable {
        let title: String?
        let videoThumbnails: [Image]?
        let description: String?
        let published: Int64?
        let publishedText: String?
        let viewCount: Int64?
        let likeCount: Int64?
        let author: String?
        let authorId: String?
        let lengthSeconds: Int?
        let liveNow: Bool?
        let hlsUrl: String?
        let dashUrl: String?
        let adaptiveFormats: [Format]?
        let captions: [Caption]?
        let recommendedVideos: [Recommended]?

        func watchPage(id: VideoID, instance: URL) -> WatchPage {
            let summary = VideoSummary(
                id: id, title: title ?? "", channelID: ChannelID(rawValue: authorId ?? ""),
                channelName: author ?? "",
                duration: lengthSeconds.flatMap { $0 > 0 ? .seconds($0) : nil },
                publishedAt: published.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil },
                publishedText: publishedText,
                viewCount: viewCount.flatMap { $0 > 0 ? Int($0) : nil },
                thumbnails: InvidiousDTO.thumbnails(videoThumbnails),
                isLive: liveNow ?? false)
            let details = VideoDetails(summary: summary, description: description ?? "",
                                       likeCount: likeCount.flatMap { $0 > 0 ? Int($0) : nil },
                                       related: (recommendedVideos ?? []).compactMap(\.videoSummary))
            let formats = adaptiveFormats ?? []
            let video = formats.compactMap(\.videoStream)
            let audio = formats.compactMap(\.audioStream)
            let manifest = StreamManifest(
                videoID: id, videoStreams: video, audioStreams: audio,
                hlsURL: hlsUrl.flatMap(URL.init(string:)),
                // `local=true` makes the manifest's segments go through the instance too.
                dashURL: dashUrl.flatMap { URL(string: $0.contains("?") ? $0 + "&local=true" : $0 + "?local=true") },
                captions: (captions ?? []).compactMap { $0.track(instance: instance) },
                chapters: [],
                expiresAt: PipedDTO.expiry(of: video.first?.url ?? audio.first?.url))
            return WatchPage(details: details, manifest: manifest)
        }
    }

    struct Format: Decodable {
        struct ColorInfo: Decodable { let transferCharacteristics: String? }
        let url: String?
        let itag: String?
        let type: String?
        let bitrate: String?
        let clen: String?
        let fps: Int?
        let size: String?
        let `init`: String?
        let index: String?
        let colorInfo: ColorInfo?

        /// `video/mp4; codecs="avc1.640028"` → ("video/mp4", "avc1.640028").
        private var mimeAndCodecs: (mime: String, codecs: String)? {
            guard let type, let semicolon = type.firstIndex(of: ";") else { return nil }
            let mime = type[..<semicolon].trimmingCharacters(in: .whitespaces)
            guard let start = type.range(of: "codecs=\"")?.upperBound,
                  let end = type[start...].firstIndex(of: "\"") else { return nil }
            return (mime, String(type[start..<end]))
        }

        private var container: MediaContainer? {
            guard let mime = mimeAndCodecs?.mime else { return nil }
            if mime.hasSuffix("/mp4") { return .mp4 }
            if mime.hasSuffix("/webm") { return .webm }
            return nil
        }

        private var ranges: (ByteRange?, ByteRange?) {
            (InvidiousDTO.range(`init`), InvidiousDTO.range(index))
        }

        var videoStream: VideoStream? {
            guard let (mime, codecs) = mimeAndCodecs, mime.hasPrefix("video/"),
                  let url = url.flatMap(URL.init(string:)), let codec = PipedDTO.videoCodec(codecs),
                  let container else { return nil }
            let dimensions = size?.split(separator: "x").compactMap { Int($0) } ?? []
            let transfer = colorInfo?.transferCharacteristics ?? ""
            let (initRange, indexRange) = ranges
            return VideoStream(url: url, codec: codec, codecs: codecs, container: container,
                               itag: itag.flatMap(Int.init),
                               width: dimensions.first ?? 0, height: dimensions.count == 2 ? dimensions[1] : 0,
                               fps: fps ?? 0, bitrate: bitrate.flatMap(Int.init),
                               isHDR: transfer.contains("SMPTEST2084") || transfer.contains("ARIB_STD_B67")
                                   || codecs.hasPrefix("vp09.02") || codecs.hasPrefix("vp9.2"),
                               initRange: initRange, indexRange: indexRange,
                               contentLength: clen.flatMap(Int64.init).flatMap { $0 > 0 ? $0 : nil })
        }

        /// Audio tracks are told apart only by `xtags` in the URL (`acont=original:lang=en`,
        /// `drc=1`). Dynamic-range-compressed copies are skipped: same content, worse sound.
        var audioStream: AudioStream? {
            guard let (mime, codecs) = mimeAndCodecs, mime.hasPrefix("audio/"),
                  let url = url.flatMap(URL.init(string:)), let codec = PipedDTO.audioCodec(codecs),
                  let container else { return nil }
            let tags = InvidiousDTO.xtags(of: url)
            guard tags["drc"] != "1" else { return nil }
            let (initRange, indexRange) = ranges
            return AudioStream(url: url, codec: codec, codecs: codecs, container: container,
                               itag: itag.flatMap(Int.init), bitrate: bitrate.flatMap(Int.init),
                               language: tags["lang"], isOriginal: (tags["acont"] ?? "original") == "original",
                               initRange: initRange, indexRange: indexRange,
                               contentLength: clen.flatMap(Int64.init).flatMap { $0 > 0 ? $0 : nil })
        }
    }

    struct Caption: Decodable {
        let label: String?
        let language_code: String?
        let url: String?

        /// URLs are relative to the instance and return WebVTT.
        func track(instance: URL) -> CaptionTrack? {
            guard let url, let language = language_code,
                  let absolute = URL(string: url, relativeTo: instance)?.absoluteURL else { return nil }
            let label = label ?? language
            return CaptionTrack(url: absolute, language: language, label: label,
                                isAutoGenerated: label.contains("auto-generated"))
        }
    }

    struct Recommended: Decodable {
        let videoId: String?
        let title: String?
        let author: String?
        let authorId: String?
        let lengthSeconds: Int?
        let videoThumbnails: [Image]?
        let published: String?
        let publishedText: String?

        var videoSummary: VideoSummary? {
            guard let videoId else { return nil }
            return VideoSummary(id: VideoID(rawValue: videoId), title: title ?? "",
                                channelID: ChannelID(rawValue: authorId ?? ""), channelName: author ?? "",
                                duration: lengthSeconds.flatMap { $0 > 0 ? .seconds($0) : nil },
                                publishedAt: published.flatMap { try? Date($0, strategy: .iso8601) },
                                publishedText: publishedText, viewCount: nil,
                                thumbnails: InvidiousDTO.thumbnails(videoThumbnails))
        }
    }

    // MARK: Helpers

    /// Invidious synthesises a fixed set of thumbnails; keep the sized, non-"maxres" ones
    /// (maxres often 404s) so the image pipeline can pick the one matching the cell.
    static func thumbnails(_ images: [Image]?) -> [Thumbnail] {
        (images ?? []).filter { ($0.width ?? 0) > 0 && !$0.url.contains("maxres") }.map(\.thumbnail)
    }

    /// "0-740" → 0...740.
    static func range(_ text: String?) -> ByteRange? {
        guard let parts = text?.split(separator: "-"), parts.count == 2,
              let start = Int64(parts[0]), let end = Int64(parts[1]), end >= start else { return nil }
        return ByteRange(start: start, end: end)
    }

    static func xtags(of url: URL) -> [String: String] {
        guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "xtags" })?.value else { return [:] }
        return Dictionary(value.split(separator: ":").compactMap { pair -> (String, String)? in
            let kv = pair.split(separator: "=", maxSplits: 1)
            return kv.count == 2 ? (String(kv[0]), String(kv[1])) : nil
        }, uniquingKeysWith: { first, _ in first })
    }
}
