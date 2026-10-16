import Foundation

/// Piped's wire format. Every field is optional because Piped emits nulls freely, and unknown
/// numbers are -1 (mapped to nil). Units: `duration` seconds, `uploaded` epoch milliseconds.
enum PipedDTO {
    struct ErrorBody: Decodable {
        let error: String?
        let message: String?
    }

    struct ContentItem: Decodable {
        let type: String?
        let url: String?
        let title: String?
        let thumbnail: String?
        let uploaderName: String?
        let uploaderUrl: String?
        let uploadedDate: String?
        let duration: Int64?
        let views: Int64?
        let uploaded: Int64?
        let isShort: Bool?

        /// Stream items only; channels and playlists in mixed lists are skipped.
        var videoSummary: VideoSummary? {
            guard type == nil || type == "stream", let id = url.flatMap(PipedDTO.videoID),
                  let channel = uploaderUrl.flatMap(PipedDTO.channelID) else { return nil }
            let seconds = duration.flatMap { $0 > 0 ? $0 : nil }
            return VideoSummary(
                id: VideoID(rawValue: id), title: title ?? "", channelID: ChannelID(rawValue: channel),
                channelName: uploaderName ?? "",
                duration: seconds.map { .seconds($0) },
                publishedAt: PipedDTO.date(milliseconds: uploaded),
                publishedText: uploadedDate,
                viewCount: views.flatMap { $0 >= 0 ? Int($0) : nil },
                thumbnails: thumbnail.flatMap(Thumbnail.unsized).map { [$0] } ?? [],
                // Live items report duration -1 with no upload time.
                isLive: duration == -1 && (uploaded ?? -1) < 0,
                isShort: isShort ?? false)
        }
    }

    struct SearchResults: Decodable {
        let items: [ContentItem]?
        let nextpage: String?
    }

    struct StreamsPage: Decodable {
        let relatedStreams: [ContentItem]?
        let nextpage: String?
    }

    struct Channel: Decodable {
        let name: String?
        let avatarUrl: String?
        let relatedStreams: [ContentItem]?
        let nextpage: String?
    }

    struct Playlist: Decodable {
        let name: String?
        let uploader: String?
        let videos: Int?
        let relatedStreams: [ContentItem]?
        let nextpage: String?
    }

    struct CommentsPage: Decodable {
        let comments: [CommentItem]?
        let nextpage: String?
    }

    struct CommentItem: Decodable {
        let commentId: String?
        let author: String?
        let commentorUrl: String?
        let commentText: String?
        let commentedTime: String?
        let likeCount: Int?
        let replyCount: Int?
        let repliesPage: String?
        let pinned: Bool?

        var comment: Comment {
            Comment(id: commentId ?? UUID().uuidString, authorName: author ?? "",
                    authorChannelID: commentorUrl.flatMap(PipedDTO.channelID).map(ChannelID.init(rawValue:)),
                    text: HTMLText.plain(commentText ?? ""),
                    likeCount: likeCount.flatMap { $0 >= 0 ? $0 : nil },
                    publishedAt: nil, publishedText: commentedTime,
                    isPinned: pinned ?? false, replyCount: max(replyCount ?? 0, 0),
                    repliesCursor: PipedSource.cursor(repliesPage))
        }
    }

    struct Streams: Decodable {
        let title: String?
        let description: String?
        let uploaded: Int64?
        let uploader: String?
        let uploaderUrl: String?
        let thumbnailUrl: String?
        let duration: Int64?
        let views: Int64?
        let likes: Int64?
        let livestream: Bool?
        let hls: String?
        let audioStreams: [Stream]?
        let videoStreams: [Stream]?
        let relatedStreams: [ContentItem]?
        let subtitles: [Subtitle]?
        let chapters: [ChapterItem]?

        func watchPage(id: VideoID) -> WatchPage {
            let isLive = livestream ?? false
            let summary = VideoSummary(
                id: id, title: title ?? "",
                channelID: ChannelID(rawValue: uploaderUrl.flatMap(PipedDTO.channelID) ?? ""),
                channelName: uploader ?? "",
                duration: duration.flatMap { $0 > 0 ? .seconds($0) : nil },
                publishedAt: PipedDTO.date(milliseconds: uploaded),
                viewCount: views.flatMap { $0 >= 0 ? Int($0) : nil },
                thumbnails: thumbnailUrl.flatMap(Thumbnail.unsized).map { [$0] } ?? [],
                isLive: isLive)
            let details = VideoDetails(summary: summary, description: HTMLText.plain(description ?? ""),
                                       likeCount: likes.flatMap { $0 >= 0 ? Int($0) : nil },
                                       related: (relatedStreams ?? []).compactMap(\.videoSummary))
            let video = (videoStreams ?? []).compactMap(\.videoStream)
            let audio = (audioStreams ?? []).compactMap(\.audioStream)
            let manifest = StreamManifest(
                videoID: id, videoStreams: video, audioStreams: audio,
                hlsURL: hls.flatMap(URL.init(string:)),
                captions: (subtitles ?? []).compactMap(\.captionTrack),
                chapters: (chapters ?? []).compactMap(\.chapter),
                expiresAt: PipedDTO.expiry(of: video.first?.url ?? audio.first?.url))
            return WatchPage(details: details, manifest: manifest)
        }
    }

    struct Stream: Decodable {
        let url: String?
        let format: String?
        let quality: String?
        let codec: String?
        let videoOnly: Bool?
        let itag: Int?
        let bitrate: Int?
        let width: Int?
        let height: Int?
        let fps: Int?
        let initStart: Int64?
        let initEnd: Int64?
        let indexStart: Int64?
        let indexEnd: Int64?
        let contentLength: Int64?
        let audioTrackLocale: String?
        let audioTrackType: String?

        private var ranges: (ByteRange?, ByteRange?) {
            guard let initStart, let initEnd, let indexStart, let indexEnd, initEnd > 0, indexEnd > 0 else { return (nil, nil) }
            return (ByteRange(start: initStart, end: initEnd), ByteRange(start: indexStart, end: indexEnd))
        }

        /// Adaptive video-only tracks; muxed itag 18 and LBRY pseudo-streams (itag -1) are skipped.
        var videoStream: VideoStream? {
            guard videoOnly == true, (itag ?? -1) > 0, let url = url.flatMap(URL.init(string:)),
                  let codecs = codec, let videoCodec = PipedDTO.videoCodec(codecs),
                  let container = PipedDTO.container(format) else { return nil }
            let (initRange, indexRange) = ranges
            return VideoStream(url: url, codec: videoCodec, codecs: codecs, container: container, itag: itag,
                               width: width ?? 0, height: height ?? 0, fps: fps ?? 0,
                               bitrate: bitrate.flatMap { $0 > 0 ? $0 : nil },
                               isHDR: PipedDTO.isHDR(codecs: codecs, quality: quality),
                               initRange: initRange, indexRange: indexRange,
                               contentLength: contentLength.flatMap { $0 > 0 ? $0 : nil })
        }

        var audioStream: AudioStream? {
            guard let url = url.flatMap(URL.init(string:)), let codecs = codec,
                  let audioCodec = PipedDTO.audioCodec(codecs), let container = PipedDTO.container(format) else { return nil }
            let (initRange, indexRange) = ranges
            return AudioStream(url: url, codec: audioCodec, codecs: codecs, container: container, itag: itag,
                               bitrate: bitrate.flatMap { $0 > 0 ? $0 : nil }, language: audioTrackLocale,
                               isOriginal: audioTrackType == nil || audioTrackType == "ORIGINAL",
                               initRange: initRange, indexRange: indexRange,
                               contentLength: contentLength.flatMap { $0 > 0 ? $0 : nil })
        }
    }

    struct Subtitle: Decodable {
        let url: String?
        let name: String?
        let code: String?
        let autoGenerated: Bool?

        /// Piped serves TTML by default; YouTube's timedtext returns WebVTT for `fmt=vtt`.
        var captionTrack: CaptionTrack? {
            guard let url, var components = URLComponents(string: url), let code else { return nil }
            var items = components.queryItems?.filter { $0.name != "fmt" } ?? []
            items.append(URLQueryItem(name: "fmt", value: "vtt"))
            components.queryItems = items
            guard let vtt = components.url else { return nil }
            return CaptionTrack(url: vtt, language: code, label: name ?? code, isAutoGenerated: autoGenerated ?? false)
        }
    }

    struct ChapterItem: Decodable {
        let title: String?
        let start: Int64?

        var chapter: Chapter? {
            guard let start, start >= 0 else { return nil }
            return Chapter(title: title ?? "", start: .seconds(start))
        }
    }

    // MARK: Helpers

    /// "/watch?v=ID" → "ID".
    static func videoID(_ path: String) -> String? {
        URLComponents(string: path)?.queryItems?.first { $0.name == "v" }?.value
    }

    /// "/channel/UC…" → "UC…".
    static func channelID(_ path: String) -> String? {
        let parts = path.split(separator: "/")
        guard parts.count >= 2, parts[parts.count - 2] == "channel" else { return nil }
        return String(parts.last!)
    }

    static func date(milliseconds: Int64?) -> Date? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    static func videoCodec(_ codecs: String) -> VideoCodec? {
        if codecs.hasPrefix("avc1") { return .h264 }
        if codecs.hasPrefix("vp9") || codecs.hasPrefix("vp09") { return .vp9 }
        if codecs.hasPrefix("av01") { return .av1 }
        return nil
    }

    static func audioCodec(_ codecs: String) -> AudioCodec? {
        if codecs.hasPrefix("mp4a") { return .aac }
        if codecs.hasPrefix("opus") { return .opus }
        return nil
    }

    static func container(_ format: String?) -> MediaContainer? {
        switch format {
        case "MPEG_4", "M4A": .mp4
        case "WEBM", "WEBMA_OPUS", "WEBMA": .webm
        default: nil
        }
    }

    /// No HDR flag in Piped: VP9 profile 2 ("vp9.2"/"vp09.02") and 10-bit AV1 (`av01.P.LLT.10`) or an "HDR" quality label.
    static func isHDR(codecs: String, quality: String?) -> Bool {
        if quality?.contains("HDR") == true || codecs.hasPrefix("vp09.02") || codecs.hasPrefix("vp9.2") { return true }
        let parts = codecs.split(separator: ".")
        return codecs.hasPrefix("av01") && parts.count >= 4 && parts[3] == "10"
    }

    /// googlevideo URLs carry `expire=<unix seconds>`.
    static func expiry(of url: URL?) -> Date? {
        guard let url, let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "expire" })?.value,
              let seconds = TimeInterval(value) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
