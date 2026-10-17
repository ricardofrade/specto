import Foundation
import GRDB
import Core

/// Playlists the person saved (from a channel or search), newest first. Removal is a tombstone
/// so it syncs.
public struct PlaylistStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func all() throws -> [PlaylistSummary] {
        try database.writer.read(Self.fetch)
    }

    public func observe() -> AsyncThrowingStream<[PlaylistSummary], Error> {
        database.stream(Self.fetch)
    }

    public func isSaved(_ id: PlaylistID) throws -> Bool {
        try database.writer.read { db in
            try SavedPlaylistRecord.filter(key: id.rawValue).filter(Column("isDeleted") == false).fetchCount(db) > 0
        }
    }

    /// Saving again refreshes the title, count and thumbnail, keeping the original date.
    public func save(_ playlist: PlaylistSummary) throws {
        try database.writer.write { db in
            let existing = try SavedPlaylistRecord.fetchOne(db, key: playlist.id.rawValue)
            var record = existing ?? SavedPlaylistRecord(id: playlist.id.rawValue, title: playlist.title, savedAt: .now,
                                                         modifiedAt: .now)
            let before = record
            record.title = playlist.title
            record.channelName = playlist.channelName ?? record.channelName
            record.videoCount = playlist.videoCount ?? record.videoCount
            record.thumbnailURL = playlist.thumbnails.first?.url.absoluteString ?? record.thumbnailURL
            if record.isDeleted { record.savedAt = .now }
            record.isDeleted = false
            guard existing == nil || !Self.sameValues(before, record) else { return }
            record.modifiedAt = .now
            try record.save(db)
        }
    }

    public func remove(_ id: PlaylistID) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE savedPlaylist SET isDeleted = 1, modifiedAt = ? WHERE id = ? AND isDeleted = 0",
                           arguments: [Date.now, id.rawValue])
        }
    }

    private static func fetch(_ db: Database) throws -> [PlaylistSummary] {
        try SavedPlaylistRecord.filter(Column("isDeleted") == false).order(Column("savedAt").desc).fetchAll(db).map(\.summary)
    }

    private static func sameValues(_ a: SavedPlaylistRecord, _ b: SavedPlaylistRecord) -> Bool {
        a.title == b.title && a.channelName == b.channelName && a.videoCount == b.videoCount
            && a.thumbnailURL == b.thumbnailURL && a.isDeleted == b.isDeleted && a.savedAt == b.savedAt
    }
}
