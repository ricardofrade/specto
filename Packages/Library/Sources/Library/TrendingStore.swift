import Foundation
import GRDB
import Core

/// The instances' trending lists, cached so Explore opens on the last one it saw and refreshes
/// behind it (stale-while-revalidate, like every screen). One list per category, for the
/// person's region.
public struct TrendingStore: Sendable {
    private let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Replaces a category's list; the videos join the cache (and stay while they're listed).
    public func replace(with videos: [VideoSummary], category: TrendingCategory = .all) throws {
        try FeedStore(database).save(videos)
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM trending WHERE category = ?", arguments: [category.rawValue])
            var seen = Set<VideoID>()
            for video in videos where seen.insert(video.id).inserted {
                try db.execute(sql: "INSERT INTO trending (category, position, videoID) VALUES (?, ?, ?)",
                               arguments: [category.rawValue, seen.count, video.id.rawValue])
            }
        }
    }

    public func rows(_ category: TrendingCategory = .all) throws -> [FeedRow] {
        try database.writer.read { db in try Self.fetchRows(db, category) }
    }

    public func observe(_ category: TrendingCategory = .all) -> AsyncThrowingStream<[FeedRow], Error> {
        database.stream { db in try Self.fetchRows(db, category) }
    }

    private static func fetchRows(_ db: Database, _ category: TrendingCategory) throws -> [FeedRow] {
        let formatter = RowFormatter()
        return try Row.fetchAll(db, sql: """
            SELECT video.*, watchState.positionSeconds AS position, watchState.durationSeconds AS length
            FROM trending JOIN video ON video.id = trending.videoID
            LEFT JOIN watchState ON watchState.videoID = video.id AND watchState.isDeleted = 0
            WHERE trending.category = ?
            ORDER BY trending.position
            """, arguments: [category.rawValue]).map { row in
            formatter.row(try VideoRecord(row: row).summary, positionSeconds: row["position"],
                          durationSeconds: row["length"])
        }
    }
}
