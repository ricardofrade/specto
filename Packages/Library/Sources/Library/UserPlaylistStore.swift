import Foundation
import GRDB
import Core

/// A playlist the person keeps: Watch Later, or one they made. Its videos are kept in order.
public struct UserPlaylist: Identifiable, Hashable, Sendable {
    public static let watchLaterID = "watch-later"

    public let id: String
    /// As stored; `displayTitle` localizes Watch Later.
    public let title: String
    public let videos: [VideoSummary]
    public let createdAt: Date

    public var isWatchLater: Bool { id == Self.watchLaterID }
    public var displayTitle: String { isWatchLater ? String(localized: "Watch Later") : title }
    public func contains(_ video: VideoID) -> Bool { videos.contains { $0.id == video } }
}

struct UserPlaylistRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "userPlaylist"
    var id: String
    var title: String
    var videos: Data
    var createdAt: Date
    var modifiedAt: Date
    var isDeleted: Bool = false
    var syncMetadata: Data? = nil
    var uploadedAt: Date? = nil

    var playlist: UserPlaylist {
        UserPlaylist(id: id, title: title, videos: Self.decode(videos), createdAt: createdAt)
    }

    static func encode(_ videos: [VideoSummary]) -> Data {
        (try? JSONEncoder().encode(videos)) ?? Data("[]".utf8)
    }

    static func decode(_ data: Data) -> [VideoSummary] {
        (try? JSONDecoder().decode([VideoSummary].self, from: data)) ?? []
    }
}

/// Watch Later and the person's playlists: Watch Later first, then newest. Every change bumps
/// `modifiedAt`, so it syncs; deleting is a tombstone. Watch Later always exists.
public struct UserPlaylistStore: Sendable {
    /// Enough for any real list; keeps the synced record well under CloudKit's 1 MB.
    public static let maxVideos = 500
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func all() throws -> [UserPlaylist] {
        try database.writer.read(Self.fetch)
    }

    public func observe() -> AsyncThrowingStream<[UserPlaylist], Error> {
        database.stream(Self.fetch)
    }

    public func playlist(_ id: String) throws -> UserPlaylist? {
        try all().first { $0.id == id }
    }

    @discardableResult
    public func create(title: String, with video: VideoSummary? = nil) throws -> UserPlaylist {
        let record = UserPlaylistRecord(id: UUID().uuidString, title: title, videos: UserPlaylistRecord.encode(video.map { [$0] } ?? []),
                                        createdAt: .now, modifiedAt: .now)
        try database.writer.write { db in try record.save(db) }
        return record.playlist
    }

    public func rename(_ id: String, to title: String) throws {
        guard id != UserPlaylist.watchLaterID else { return }
        try change(id) { $0.title = title }
    }

    public func delete(_ id: String) throws {
        guard id != UserPlaylist.watchLaterID else { return }
        try change(id) { $0.isDeleted = true }
    }

    /// Adds at the end; a video already in it stays where it is.
    public func add(_ video: VideoSummary, to id: String) throws {
        try change(id, creatingWatchLater: true) { record in
            var videos = UserPlaylistRecord.decode(record.videos)
            guard !videos.contains(where: { $0.id == video.id }), videos.count < Self.maxVideos else { return }
            videos.append(video)
            record.videos = UserPlaylistRecord.encode(videos)
        }
    }

    public func remove(_ video: VideoID, from id: String) throws {
        try change(id) { record in
            record.videos = UserPlaylistRecord.encode(UserPlaylistRecord.decode(record.videos).filter { $0.id != video })
        }
    }

    public func move(in id: String, from source: IndexSet, to destination: Int) throws {
        try change(id) { record in
            // List semantics (`destination` counts the moved items), without SwiftUI's helper.
            let videos = UserPlaylistRecord.decode(record.videos)
            let moving = source.filter { videos.indices.contains($0) }.map { videos[$0] }
            var rest = videos.enumerated().filter { !source.contains($0.offset) }.map(\.element)
            let insertAt = destination - source.filter { $0 < destination }.count
            rest.insert(contentsOf: moving, at: max(0, min(insertAt, rest.count)))
            record.videos = UserPlaylistRecord.encode(rest)
        }
    }

    /// Watch Later's add/remove in one tap.
    public func toggleWatchLater(_ video: VideoSummary) throws {
        if try playlist(UserPlaylist.watchLaterID)?.contains(video.id) == true {
            try remove(video.id, from: UserPlaylist.watchLaterID)
        } else {
            try add(video, to: UserPlaylist.watchLaterID)
        }
    }

    // MARK: Private

    private func change(_ id: String, creatingWatchLater: Bool = false, _ edit: (inout UserPlaylistRecord) -> Void) throws {
        try database.writer.write { db in
            var record: UserPlaylistRecord
            if let existing = try UserPlaylistRecord.fetchOne(db, key: id), !existing.isDeleted {
                record = existing
            } else if id == UserPlaylist.watchLaterID {
                // Watch Later appears on first use (or comes back after an old tombstone).
                let existing = try UserPlaylistRecord.fetchOne(db, key: id)
                record = UserPlaylistRecord(id: id, title: "Watch Later", videos: UserPlaylistRecord.encode([]),
                                            createdAt: existing?.createdAt ?? .now, modifiedAt: .now,
                                            syncMetadata: existing?.syncMetadata, uploadedAt: existing?.uploadedAt)
            } else {
                return
            }
            let before = record
            edit(&record)
            // Only a real change is an edit: an unchanged row must not re-sync.
            guard record.videos != before.videos || record.title != before.title || record.isDeleted != before.isDeleted
            else { return }
            record.modifiedAt = .now
            try record.save(db)
        }
    }

    private static func fetch(_ db: Database) throws -> [UserPlaylist] {
        let playlists = try UserPlaylistRecord.filter(Column("isDeleted") == false).order(Column("createdAt").desc)
            .fetchAll(db).map(\.playlist)
        let watchLater = playlists.first(where: \.isWatchLater)
            ?? UserPlaylist(id: UserPlaylist.watchLaterID, title: "Watch Later", videos: [], createdAt: .distantPast)
        return [watchLater] + playlists.filter { !$0.isWatchLater }
    }
}
