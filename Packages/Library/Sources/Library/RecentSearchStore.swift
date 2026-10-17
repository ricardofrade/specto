import Foundation
import GRDB

/// The last searches on this device, newest first (never synced). Searching again moves a query
/// to the top; only the latest `limit` are kept.
public struct RecentSearchStore: Sendable {
    public static let limit = 20
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func all() throws -> [String] {
        try database.writer.read(Self.fetch)
    }

    public func observe() -> AsyncThrowingStream<[String], Error> {
        database.stream(Self.fetch)
    }

    public func record(_ query: String) throws {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        try database.writer.write { db in
            // Case-insensitively the same search: keep the latest spelling.
            try db.execute(sql: "DELETE FROM recentSearch WHERE query = ? COLLATE NOCASE", arguments: [query])
            try db.execute(sql: "INSERT INTO recentSearch (query, searchedAt) VALUES (?, ?)", arguments: [query, Date.now])
            try db.execute(sql: """
                DELETE FROM recentSearch WHERE query NOT IN
                (SELECT query FROM recentSearch ORDER BY searchedAt DESC, rowid DESC LIMIT ?)
                """, arguments: [Self.limit])
        }
    }

    public func remove(_ query: String) throws {
        try database.writer.write { db in try db.execute(sql: "DELETE FROM recentSearch WHERE query = ?", arguments: [query]) }
    }

    public func clear() throws {
        try database.writer.write { db in try db.execute(sql: "DELETE FROM recentSearch") }
    }

    private static func fetch(_ db: Database) throws -> [String] {
        // Two searches can share a millisecond: the later insert (rowid) comes first.
        try String.fetchAll(db, sql: "SELECT query FROM recentSearch ORDER BY searchedAt DESC, rowid DESC")
    }
}
