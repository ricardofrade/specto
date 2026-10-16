import Foundation

// MARK: - Identifiers

public struct VideoID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct ChannelID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct PlaylistID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - Instances

public enum SourceKind: String, Sendable, Codable, CaseIterable {
    case piped, invidious, ytZero
}

public struct InstanceConfig: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var kind: SourceKind
    public var displayName: String
    /// Base URL of the instance's API. For Piped this is the backend API URL, not the frontend.
    public var apiURL: URL

    public init(id: UUID = UUID(), kind: SourceKind, displayName: String, apiURL: URL) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.apiURL = apiURL
    }
}

// MARK: - Capabilities

/// What an adapter can do. Routing picks an instance per capability, so a feed can come
/// from YT Zero while streams come from Piped.
public struct SourceCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let search        = SourceCapabilities(rawValue: 1 << 0)
    public static let trending      = SourceCapabilities(rawValue: 1 << 1)
    public static let channel       = SourceCapabilities(rawValue: 1 << 2)
    public static let comments      = SourceCapabilities(rawValue: 1 << 3)
    public static let streams       = SourceCapabilities(rawValue: 1 << 4)
    /// A batched latest-uploads feed for a list of channels (`feed(for:)`).
    public static let subscriptions = SourceCapabilities(rawValue: 1 << 5)
    public static let playlists     = SourceCapabilities(rawValue: 1 << 6)
}

// MARK: - Content models

public struct Thumbnail: Hashable, Sendable, Codable {
    public let url: URL
    public let width: Int
    public let height: Int

    public init(url: URL, width: Int, height: Int) {
        self.url = url
        self.width = width
        self.height = height
    }
}

public struct VideoSummary: Identifiable, Hashable, Sendable, Codable {
    public let id: VideoID
    public let title: String
    public let channelID: ChannelID
    public let channelName: String
    public let duration: Duration?
    public let publishedAt: Date?
    /// The source's own relative text (for example "3 days ago"), for when `publishedAt` is nil.
    public let publishedText: String?
    public let viewCount: Int?
    public let thumbnails: [Thumbnail]
    public let isLive: Bool
    public let isShort: Bool

    public init(id: VideoID, title: String, channelID: ChannelID, channelName: String,
                duration: Duration?, publishedAt: Date?, publishedText: String? = nil, viewCount: Int?,
                thumbnails: [Thumbnail], isLive: Bool = false, isShort: Bool = false) {
        self.id = id
        self.title = title
        self.channelID = channelID
        self.channelName = channelName
        self.duration = duration
        self.publishedAt = publishedAt
        self.publishedText = publishedText
        self.viewCount = viewCount
        self.thumbnails = thumbnails
        self.isLive = isLive
        self.isShort = isShort
    }
}

/// Everything the Watch screen shows besides the player.
public struct VideoDetails: Sendable, Codable {
    public let summary: VideoSummary
    public let description: String
    public let likeCount: Int?
    public let related: [VideoSummary]

    public init(summary: VideoSummary, description: String, likeCount: Int?, related: [VideoSummary]) {
        self.summary = summary
        self.description = description
        self.likeCount = likeCount
        self.related = related
    }
}

public struct ChannelPage: Sendable {
    public let id: ChannelID
    public let name: String
    public let avatar: Thumbnail?
    public let videos: Page<VideoSummary>

    public init(id: ChannelID, name: String, avatar: Thumbnail?, videos: Page<VideoSummary>) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.videos = videos
    }
}

public struct PlaylistPage: Sendable {
    public let id: PlaylistID
    public let title: String
    public let channelName: String?
    public let videoCount: Int?
    public let videos: Page<VideoSummary>

    public init(id: PlaylistID, title: String, channelName: String?, videoCount: Int?,
                videos: Page<VideoSummary>) {
        self.id = id
        self.title = title
        self.channelName = channelName
        self.videoCount = videoCount
        self.videos = videos
    }
}

public struct Comment: Identifiable, Hashable, Sendable {
    public let id: String
    public let authorName: String
    public let authorChannelID: ChannelID?
    public let text: String
    public let likeCount: Int?
    public let publishedAt: Date?
    /// The source's own relative text, for when `publishedAt` is nil.
    public let publishedText: String?
    public let isPinned: Bool
    public let replyCount: Int
    /// Pass to `comments(for:cursor:)` to load this comment's replies; nil when there are none.
    public let repliesCursor: String?

    public init(id: String, authorName: String, authorChannelID: ChannelID?, text: String,
                likeCount: Int?, publishedAt: Date?, publishedText: String?,
                isPinned: Bool, replyCount: Int, repliesCursor: String?) {
        self.id = id
        self.authorName = authorName
        self.authorChannelID = authorChannelID
        self.text = text
        self.likeCount = likeCount
        self.publishedAt = publishedAt
        self.publishedText = publishedText
        self.isPinned = isPinned
        self.replyCount = replyCount
        self.repliesCursor = repliesCursor
    }
}

public struct Page<Item: Sendable>: Sendable {
    public let items: [Item]
    /// Opaque cursor for the next page; nil when there are no more pages.
    public let nextCursor: String?

    public init(items: [Item], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}

// MARK: - Streams

public enum VideoCodec: String, Hashable, Sendable, Codable {
    case av1, vp9, h264
}

public enum AudioCodec: String, Hashable, Sendable, Codable {
    case aac, opus
}

/// AVPlayer and HLS accept only MP4; mpv plays both.
public enum MediaContainer: String, Hashable, Sendable, Codable {
    case mp4, webm
}

/// An inclusive byte range, as in an HTTP `Range` header.
public struct ByteRange: Hashable, Sendable, Codable {
    public let start: Int64
    public let end: Int64

    public init(start: Int64, end: Int64) {
        self.start = start
        self.end = end
    }

    public var length: Int64 { end - start + 1 }
}

public struct VideoStream: Hashable, Sendable, Codable {
    public let url: URL
    public let codec: VideoCodec
    /// RFC 6381 codecs string (for example "avc1.640028"); required for HLS playlists.
    public let codecs: String?
    public let container: MediaContainer
    public let itag: Int?
    public let width: Int
    public let height: Int
    public let fps: Int
    /// Bits per second, when the source reports it.
    public let bitrate: Int?
    public let isHDR: Bool
    /// Init segment and segment index (sidx/Cues). Needed to build an HLS playlist on device.
    public let initRange: ByteRange?
    public let indexRange: ByteRange?
    public let contentLength: Int64?

    public init(url: URL, codec: VideoCodec, codecs: String? = nil, container: MediaContainer, itag: Int? = nil,
                width: Int, height: Int, fps: Int, bitrate: Int?, isHDR: Bool,
                initRange: ByteRange? = nil, indexRange: ByteRange? = nil, contentLength: Int64? = nil) {
        self.url = url
        self.codec = codec
        self.codecs = codecs
        self.container = container
        self.itag = itag
        self.width = width
        self.height = height
        self.fps = fps
        self.bitrate = bitrate
        self.isHDR = isHDR
        self.initRange = initRange
        self.indexRange = indexRange
        self.contentLength = contentLength
    }
}

public struct AudioStream: Hashable, Sendable, Codable {
    public let url: URL
    public let codec: AudioCodec
    /// RFC 6381 codecs string (for example "mp4a.40.2").
    public let codecs: String?
    public let container: MediaContainer
    public let itag: Int?
    public let bitrate: Int?
    /// BCP 47 code for multi-language videos; nil when the video has a single track.
    public let language: String?
    public let initRange: ByteRange?
    public let indexRange: ByteRange?
    public let contentLength: Int64?

    public init(url: URL, codec: AudioCodec, codecs: String? = nil, container: MediaContainer, itag: Int? = nil,
                bitrate: Int?, language: String?,
                initRange: ByteRange? = nil, indexRange: ByteRange? = nil, contentLength: Int64? = nil) {
        self.url = url
        self.codec = codec
        self.codecs = codecs
        self.container = container
        self.itag = itag
        self.bitrate = bitrate
        self.language = language
        self.initRange = initRange
        self.indexRange = indexRange
        self.contentLength = contentLength
    }
}

/// A WebVTT subtitle track.
public struct CaptionTrack: Hashable, Sendable, Codable {
    public let url: URL
    /// BCP 47 code.
    public let language: String
    public let label: String
    public let isAutoGenerated: Bool

    public init(url: URL, language: String, label: String, isAutoGenerated: Bool) {
        self.url = url
        self.language = language
        self.label = label
        self.isAutoGenerated = isAutoGenerated
    }
}

public struct Chapter: Hashable, Sendable, Codable {
    public let title: String
    public let start: Duration

    public init(title: String, start: Duration) {
        self.title = title
        self.start = start
    }
}

public struct StreamManifest: Sendable, Codable {
    public let videoID: VideoID
    public let videoStreams: [VideoStream]
    public let audioStreams: [AudioStream]
    /// Live streams and some instances provide HLS instead of (or as well as) adaptive streams.
    public let hlsURL: URL?
    public let captions: [CaptionTrack]
    public let chapters: [Chapter]
    /// Stream URLs from YouTube expire; refetch the manifest after this date.
    public let expiresAt: Date?

    public init(videoID: VideoID, videoStreams: [VideoStream], audioStreams: [AudioStream],
                hlsURL: URL?, captions: [CaptionTrack] = [], chapters: [Chapter], expiresAt: Date?) {
        self.videoID = videoID
        self.videoStreams = videoStreams
        self.audioStreams = audioStreams
        self.hlsURL = hlsURL
        self.captions = captions
        self.chapters = chapters
        self.expiresAt = expiresAt
    }
}

/// One fetch gives both, because every source returns them from the same endpoint.
public struct WatchPage: Sendable, Codable {
    public let details: VideoDetails
    public let manifest: StreamManifest

    public init(details: VideoDetails, manifest: StreamManifest) {
        self.details = details
        self.manifest = manifest
    }
}

// MARK: - Health and errors

public struct HealthSample: Sendable {
    public let instanceID: UUID
    public let isHealthy: Bool
    public let latency: Duration?
    public let measuredAt: Date

    public init(instanceID: UUID, isHealthy: Bool, latency: Duration?, measuredAt: Date = .now) {
        self.instanceID = instanceID
        self.isHealthy = isHealthy
        self.latency = latency
        self.measuredAt = measuredAt
    }
}

public enum SourceError: Error, Sendable {
    case unsupported(SourceCapabilities)
    case http(status: Int)
    case decoding(String)
    case rateLimited(retryAfter: Duration?)
    /// The instance was blocked upstream (for example a "sign in to confirm" response).
    case blockedUpstream
    /// The content itself can't be played anywhere: private, removed or region-locked.
    case unavailable(reason: String?)
    case network(URLError)

    /// Whether routing should try the same operation on another instance.
    public var isRetryableElsewhere: Bool {
        switch self {
        case .unsupported, .decoding, .rateLimited, .blockedUpstream, .network: true
        case .http(let status): status >= 500 || status == 403 || status == 429
        case .unavailable: false
        }
    }
}

// MARK: - The adapter contract

/// One adapter per instance. Adapters are stateless apart from their configuration and
/// an HTTP client; caching and persistence belong to `Library`, not here.
///
/// Stream URLs must be playable from the device: request them through the instance's proxy
/// (Piped's proxy, Invidious `local=true`). Direct googlevideo URLs are bound to the IP that
/// requested them, which is the instance, not the phone.
public protocol VideoSource: Sendable {
    var instance: InstanceConfig { get }
    var capabilities: SourceCapabilities { get }

    func search(_ query: String, cursor: String?) async throws -> Page<VideoSummary>
    func trending(region: String?) async throws -> [VideoSummary]
    func channel(_ id: ChannelID, cursor: String?) async throws -> ChannelPage
    func watchPage(for id: VideoID) async throws -> WatchPage
    /// Latest uploads for `channels`. Subscriptions live in `Library`, never on the instance.
    func feed(for channels: [ChannelID]) async throws -> [VideoSummary]
    /// Top-level comments, or a comment's replies when `cursor` is its `repliesCursor`.
    func comments(for id: VideoID, cursor: String?) async throws -> Page<Comment>
    func playlist(_ id: PlaylistID, cursor: String?) async throws -> PlaylistPage
    func healthCheck() async -> HealthSample
}

/// Defaults so adapters only implement what they declare in `capabilities`.
public extension VideoSource {
    func search(_ query: String, cursor: String?) async throws -> Page<VideoSummary> {
        throw SourceError.unsupported(.search)
    }
    func trending(region: String?) async throws -> [VideoSummary] {
        throw SourceError.unsupported(.trending)
    }
    func channel(_ id: ChannelID, cursor: String?) async throws -> ChannelPage {
        throw SourceError.unsupported(.channel)
    }
    func watchPage(for id: VideoID) async throws -> WatchPage {
        throw SourceError.unsupported(.streams)
    }
    func feed(for channels: [ChannelID]) async throws -> [VideoSummary] {
        throw SourceError.unsupported(.subscriptions)
    }
    func comments(for id: VideoID, cursor: String?) async throws -> Page<Comment> {
        throw SourceError.unsupported(.comments)
    }
    func playlist(_ id: PlaylistID, cursor: String?) async throws -> PlaylistPage {
        throw SourceError.unsupported(.playlists)
    }
}

// MARK: - Routing

/// Picks a healthy instance that supports the capability and retries on another
/// instance when the operation fails with an error that is `isRetryableElsewhere`.
public protocol SourceRouting: Sendable {
    func perform<T: Sendable>(
        _ capability: SourceCapabilities,
        _ operation: @Sendable (any VideoSource) async throws -> T
    ) async throws -> T
}
