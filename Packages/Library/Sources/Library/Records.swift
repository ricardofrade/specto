import Foundation
import GRDB
import Core

struct InstanceRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "instance"
    var id: String
    var kind: String
    var displayName: String
    var apiURL: String
    var sortOrder: Int
    var addedAt: Date

    var config: InstanceConfig? {
        guard let uuid = UUID(uuidString: id), let kind = SourceKind(rawValue: kind),
              let url = URL(string: apiURL) else { return nil }
        return InstanceConfig(id: uuid, kind: kind, displayName: displayName, apiURL: url)
    }
}

struct SubscriptionRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "subscription"
    var channelID: String
    var channelName: String
    var avatarURL: String?
    var subscribedAt: Date
    var modifiedAt: Date
    var isDeleted: Bool
    var syncMetadata: Data?

    var summary: ChannelSummary {
        ChannelSummary(id: ChannelID(rawValue: channelID), name: channelName,
                       avatar: avatarURL.flatMap(Thumbnail.unsized))
    }
}

struct VideoRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "video"
    var id: String
    var title: String
    var channelID: String
    var channelName: String
    var durationSeconds: Int?
    var publishedAt: Date?
    var publishedText: String?
    var viewCount: Int?
    var thumbnails: [Thumbnail]
    var isLive: Bool
    var isShort: Bool
    var fetchedAt: Date

    init(_ video: VideoSummary, fetchedAt: Date) {
        id = video.id.rawValue
        title = video.title
        channelID = video.channelID.rawValue
        channelName = video.channelName
        durationSeconds = video.duration.map { Int($0.components.seconds) }
        publishedAt = video.publishedAt
        publishedText = video.publishedText
        viewCount = video.viewCount
        thumbnails = video.thumbnails
        isLive = video.isLive
        isShort = video.isShort
        self.fetchedAt = fetchedAt
    }

    var summary: VideoSummary {
        VideoSummary(id: VideoID(rawValue: id), title: title, channelID: ChannelID(rawValue: channelID),
                     channelName: channelName, duration: durationSeconds.map { .seconds($0) },
                     publishedAt: publishedAt, publishedText: publishedText, viewCount: viewCount,
                     thumbnails: thumbnails, isLive: isLive, isShort: isShort)
    }
}

struct WatchStateRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "watchState"
    var videoID: String
    var positionSeconds: Double
    var durationSeconds: Double?
    var isFinished: Bool
    var lastWatchedAt: Date
    var modifiedAt: Date
    var isDeleted: Bool
    var syncMetadata: Data?
}

struct RefreshRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "refreshLog"
    var resource: String
    var refreshedAt: Date
}

struct ManifestCacheRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "manifestCache"
    var videoID: String
    var payload: Data
    var expiresAt: Date
}

struct BrandingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "branding"
    var videoID: String
    var title: String?
    var thumbnailTime: Double?
    var fetchedAt: Date
}

struct QueueRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "queueItem"
    var videoID: String
    var position: Double
    var addedAt: Date
}

struct DownloadRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "download"
    var videoID: String
    var state: String
    var fileName: String?
    var bytes: Int64
    var createdAt: Date
    var completedAt: Date?
    var lastPlayedAt: Date?
}
