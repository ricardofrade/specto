import Foundation
import GRDB
import Core

// MARK: - Queue

/// "Play next" / listening queue, shown in the app and in CarPlay.
public struct QueueStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func add(_ video: VideoSummary) throws {
        try FeedStore(database).save([video])      // Keeps any known duration.
        try database.writer.write { db in
            let last = try Double.fetchOne(db, sql: "SELECT MAX(position) FROM queueItem") ?? 0
            try QueueRecord(videoID: video.id.rawValue, position: last + 1, addedAt: .now).insert(db, onConflict: .ignore)
        }
    }

    public func remove(_ id: VideoID) throws {
        _ = try database.writer.write { db in try QueueRecord.deleteOne(db, key: id.rawValue) }
    }

    public func contains(_ id: VideoID) throws -> Bool {
        try database.writer.read { db in try QueueRecord.exists(db, key: id.rawValue) }
    }

    public func rows() throws -> [FeedRow] {
        try database.writer.read { db in try Self.fetch(db) }
    }

    public func observe() -> AsyncThrowingStream<[FeedRow], Error> {
        database.stream { db in try Self.fetch(db) }
    }

    /// The next queued video after `id` (for auto-advance), skipping finished ones.
    public func next(after id: VideoID) throws -> VideoSummary? {
        let rows = try self.rows()
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return rows.first?.video }
        return rows.dropFirst(index + 1).first?.video
    }

    static func fetch(_ db: Database) throws -> [FeedRow] {
        let formatter = RowFormatter()
        return try Row.fetchAll(db, sql: """
            SELECT video.*, watchState.positionSeconds AS position, watchState.durationSeconds AS length
            FROM queueItem JOIN video ON video.id = queueItem.videoID
            LEFT JOIN watchState ON watchState.videoID = video.id AND watchState.isDeleted = 0
            ORDER BY queueItem.position
            """).map { row in
            formatter.row(try VideoRecord(row: row).summary, positionSeconds: row["position"], durationSeconds: row["length"])
        }
    }
}

// MARK: - Continue listening

public extension WatchStateStore {
    /// Started but unfinished videos, most recent first ("Continue listening" / "Continue watching").
    func inProgress(limit: Int = 20) throws -> [FeedRow] {
        let formatter = RowFormatter()
        return try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT video.*, watchState.positionSeconds AS position, watchState.durationSeconds AS length
                FROM watchState JOIN video ON video.id = watchState.videoID
                WHERE watchState.isDeleted = 0 AND watchState.isFinished = 0 AND watchState.positionSeconds >= 5
                ORDER BY watchState.lastWatchedAt DESC LIMIT ?
                """, arguments: [limit]).map { row in
                formatter.row(try VideoRecord(row: row).summary, positionSeconds: row["position"],
                              durationSeconds: row["length"])
            }
        }
    }
}

// MARK: - Offline audio

/// Bookkeeping for downloaded audio. The transfer itself is `OfflineAudio`'s job.
public struct DownloadStore: Sendable {
    public enum State: String, Sendable {
        case queued, downloading, done, failed
    }

    public struct Entry: Sendable, Equatable {
        public let videoID: VideoID
        public let state: State
        public let fileName: String?
        public let bytes: Int64
    }

    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func entry(for id: VideoID) throws -> Entry? {
        try database.writer.read { db in try DownloadRecord.fetchOne(db, key: id.rawValue).map(Self.entry) }
    }

    public func all() throws -> [Entry] {
        try database.writer.read { db in try DownloadRecord.order(Column("createdAt")).fetchAll(db).map(Self.entry) }
    }

    public func setState(_ state: State, for id: VideoID, fileName: String? = nil, bytes: Int64? = nil) throws {
        try database.writer.write { db in
            var record = try DownloadRecord.fetchOne(db, key: id.rawValue)
                ?? DownloadRecord(videoID: id.rawValue, state: state.rawValue, fileName: nil, bytes: 0,
                                  createdAt: .now, completedAt: nil, lastPlayedAt: nil)
            record.state = state.rawValue
            if let fileName { record.fileName = fileName }
            if let bytes { record.bytes = bytes }
            if state == .done { record.completedAt = .now }
            try record.save(db)
        }
    }

    public func markPlayed(_ id: VideoID) throws {
        try database.writer.write { db in
            try db.execute(sql: "UPDATE download SET lastPlayedAt = ? WHERE videoID = ?", arguments: [Date.now, id.rawValue])
        }
    }

    public func remove(_ id: VideoID) throws {
        _ = try database.writer.write { db in try DownloadRecord.deleteOne(db, key: id.rawValue) }
    }

    /// What to delete to stay under `limitBytes`: finished-and-watched first, then least
    /// recently played (or oldest), never anything still queued in the listening queue unless
    /// nothing else is left.
    public func evictionCandidates(limitBytes: Int64) throws -> [Entry] {
        try database.writer.read { db in
            let total = try Int64.fetchOne(db, sql: "SELECT IFNULL(SUM(bytes), 0) FROM download WHERE state = 'done'") ?? 0
            guard total > limitBytes else { return [] }
            let rows = try Row.fetchAll(db, sql: """
                SELECT download.*, IFNULL(watchState.isFinished, 0) AS finished,
                       (queueItem.videoID IS NOT NULL) AS queued
                FROM download
                LEFT JOIN watchState ON watchState.videoID = download.videoID
                LEFT JOIN queueItem ON queueItem.videoID = download.videoID
                WHERE download.state = 'done'
                ORDER BY finished DESC, queued ASC, IFNULL(download.lastPlayedAt, download.completedAt) ASC
                """)
            var freed: Int64 = 0
            var victims: [Entry] = []
            for row in rows where total - freed > limitBytes {
                let record = try DownloadRecord(row: row)
                victims.append(Self.entry(record))
                freed += record.bytes
            }
            return victims
        }
    }

    /// Downloads of videos that are finished: delete these regardless of the limit.
    public func watched() throws -> [Entry] {
        try database.writer.read { db in
            try DownloadRecord.fetchAll(db, sql: """
                SELECT download.* FROM download JOIN watchState ON watchState.videoID = download.videoID
                WHERE download.state = 'done' AND watchState.isFinished = 1
                """).map(Self.entry)
        }
    }

    private static func entry(_ record: DownloadRecord) -> Entry {
        Entry(videoID: VideoID(rawValue: record.videoID), state: State(rawValue: record.state) ?? .failed,
              fileName: record.fileName, bytes: record.bytes)
    }
}
