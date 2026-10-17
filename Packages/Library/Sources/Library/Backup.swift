import Foundation
import GRDB
import Core

/// Everything a person would miss on a new device, as one JSON file they own: subscriptions
/// (and which are hidden from Home), watch history with resume positions, saved playlists, and
/// instance addresses. Never tokens: a YT Zero instance is paired again after restoring.
public struct Backup: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var app = "Specto"
    public var version = Backup.currentVersion
    public var exportedAt: Date
    public var subscriptions: [Subscription]
    public var history: [Watched]
    public var playlists: [PlaylistSummary]
    public var instances: [Instance]
    /// Watch Later and the person's playlists (backups from before they existed have none).
    public var userPlaylists: [UserPlaylistBackup]? = nil

    public struct UserPlaylistBackup: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var videos: [VideoSummary]
        public var createdAt: Date
    }

    public struct Subscription: Codable, Sendable, Equatable {
        public var channelID: String
        public var name: String
        public var avatarURL: String?
        public var subscribedAt: Date
        public var hiddenFromHome: Bool
        /// Optional: backups from before per-channel notifications don't have it.
        public var mutesNotifications: Bool?
    }

    public struct Watched: Codable, Sendable, Equatable {
        public var videoID: String
        /// The cached video, so History shows titles and thumbnails right after a restore.
        public var video: VideoSummary?
        public var positionSeconds: Double
        public var durationSeconds: Double?
        public var isFinished: Bool
        public var lastWatchedAt: Date
    }

    public struct Instance: Codable, Sendable, Equatable {
        public var kind: String
        public var displayName: String
        public var apiURL: String
    }

    /// What a restore added (things already here are left alone).
    public struct Summary: Equatable, Sendable {
        public var subscriptions = 0
        public var history = 0
        public var playlists = 0
        public var instances = 0
        public var userPlaylists = 0
    }

    public enum Failure: Error, Equatable {
        case notABackup
        case newerVersion(Int)
    }
}

public struct BackupStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func backup() throws -> Backup {
        try database.writer.read { db in
            let subscriptions = try SubscriptionRecord.filter(Column("isDeleted") == false)
                .order(Column("channelName").collating(.localizedCaseInsensitiveCompare)).fetchAll(db)
                .map { Backup.Subscription(channelID: $0.channelID, name: $0.channelName, avatarURL: $0.avatarURL,
                                           subscribedAt: $0.subscribedAt, hiddenFromHome: $0.hiddenFromHome,
                                           mutesNotifications: $0.mutesNotifications ? true : nil) }
            let states = try WatchStateRecord.filter(Column("isDeleted") == false)
                .order(Column("lastWatchedAt").desc).fetchAll(db)
            let videos = try VideoRecord.filter(keys: states.map(\.videoID)).fetchAll(db)
            let byID = Dictionary(videos.map { ($0.id, $0.summary) }, uniquingKeysWith: { first, _ in first })
            let history = states.map {
                Backup.Watched(videoID: $0.videoID, video: byID[$0.videoID], positionSeconds: $0.positionSeconds,
                               durationSeconds: $0.durationSeconds, isFinished: $0.isFinished, lastWatchedAt: $0.lastWatchedAt)
            }
            let playlists = try SavedPlaylistRecord.filter(Column("isDeleted") == false)
                .order(Column("savedAt").desc).fetchAll(db).map(\.summary)
            let instances = try InstanceStore.fetchActive(db).filter { $0.kind != .ytZero }.map {
                Backup.Instance(kind: $0.kind.rawValue, displayName: $0.displayName, apiURL: $0.apiURL.absoluteString)
            }
            let userPlaylists = try UserPlaylistRecord.filter(Column("isDeleted") == false).fetchAll(db).map {
                Backup.UserPlaylistBackup(id: $0.id, title: $0.title, videos: UserPlaylistRecord.decode($0.videos),
                                          createdAt: $0.createdAt)
            }
            return Backup(exportedAt: .now, subscriptions: subscriptions, history: history, playlists: playlists,
                          instances: instances, userPlaylists: userPlaylists)
        }
    }

    public func encoded() throws -> Data {
        try Self.encoder.encode(backup())
    }

    public static func decode(_ data: Data) throws -> Backup {
        guard let backup = try? decoder.decode(Backup.self, from: data), backup.app == "Specto" else {
            throw Backup.Failure.notABackup
        }
        guard backup.version <= Backup.currentVersion else { throw Backup.Failure.newerVersion(backup.version) }
        return backup
    }

    /// Merges: missing subscriptions, playlists and instances are added; a history entry is
    /// written only where this device has none or an older one. Nothing here is removed.
    public func restore(_ backup: Backup) throws -> Backup.Summary {
        var summary = Backup.Summary()
        let subscriptions = SubscriptionStore(database)
        let known = Set(try subscriptions.channels().map(\.id.rawValue))
        let missing = backup.subscriptions.filter { !known.contains($0.channelID) }
        try subscriptions.subscribe(missing.map {
            ChannelSummary(id: ChannelID(rawValue: $0.channelID), name: $0.name, avatar: $0.avatarURL.flatMap(Thumbnail.unsized))
        })
        for subscription in missing where subscription.hiddenFromHome {
            try subscriptions.setHiddenFromHome(ChannelID(rawValue: subscription.channelID), true)
        }
        for subscription in missing where subscription.mutesNotifications == true {
            try subscriptions.setMutesNotifications(ChannelID(rawValue: subscription.channelID), true)
        }
        summary.subscriptions = missing.count

        try FeedStore(database).save(backup.history.compactMap(\.video))
        summary.history = try database.writer.write { db in
            var written = 0
            for entry in backup.history {
                let existing = try WatchStateRecord.fetchOne(db, key: entry.videoID)
                if let existing, !existing.isDeleted, existing.lastWatchedAt >= entry.lastWatchedAt { continue }
                try WatchStateRecord(videoID: entry.videoID, positionSeconds: entry.positionSeconds,
                                     durationSeconds: entry.durationSeconds, isFinished: entry.isFinished,
                                     lastWatchedAt: entry.lastWatchedAt, modifiedAt: .now, isDeleted: false,
                                     syncMetadata: existing?.syncMetadata, uploadedAt: existing?.uploadedAt).save(db)
                written += 1
            }
            return written
        }

        let playlists = PlaylistStore(database)
        for playlist in backup.playlists {
            guard try !playlists.isSaved(playlist.id) else { continue }
            try playlists.save(playlist)
            summary.playlists += 1
        }

        // Own playlists: new ones are added; Watch Later (or a playlist that's already here)
        // gains the videos it lacks.
        let own = UserPlaylistStore(database)
        let existing = Set(try own.all().map(\.id))
        for playlist in backup.userPlaylists ?? [] {
            if !existing.contains(playlist.id), playlist.id != UserPlaylist.watchLaterID {
                try database.writer.write { db in
                    try UserPlaylistRecord(id: playlist.id, title: playlist.title,
                                           videos: UserPlaylistRecord.encode(playlist.videos),
                                           createdAt: playlist.createdAt, modifiedAt: .now).save(db)
                }
                summary.userPlaylists += 1
            } else {
                let before = try own.playlist(playlist.id)?.videos.count ?? 0
                for video in playlist.videos { try own.add(video, to: playlist.id) }
                if try (own.playlist(playlist.id)?.videos.count ?? 0) > before { summary.userPlaylists += 1 }
            }
        }

        let instances = InstanceStore(database)
        for instance in backup.instances {
            guard let kind = SourceKind(rawValue: instance.kind), kind != .ytZero,
                  let url = URL(string: instance.apiURL), try !instances.contains(url) else { continue }
            try instances.add(InstanceConfig(kind: kind, displayName: instance.displayName, apiURL: url))
            summary.instances += 1
        }
        return summary
    }

    /// Subscriptions in Google Takeout's `subscriptions.csv` layout, which most YouTube clients
    /// (and this app) import.
    public func subscriptionsCSV() throws -> String {
        let rows = try SubscriptionStore(database).channels().map { channel in
            [channel.id.rawValue, "http://www.youtube.com/channel/\(channel.id.rawValue)", channel.name]
                .map(Self.csvField).joined(separator: ",")
        }
        return (["Channel Id,Channel Url,Channel Title"] + rows).joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
