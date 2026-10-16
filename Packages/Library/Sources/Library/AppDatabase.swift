import Foundation
import GRDB

/// The app's single database. Every screen reads from it first, then refreshes from the network.
public struct AppDatabase: Sendable {
    let writer: any DatabaseWriter

    private init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// A WAL-mode pool, so reads never wait on a write (the feed renders while a refresh is saving).
    public static func onDisk(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        return try AppDatabase(DatabasePool(path: url.path(percentEncoded: false)))
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    /// `Application Support/Library/app.sqlite`.
    public static func defaultURL() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appending(path: "Library/app.sqlite")
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        // Synced tables (`subscription`, `watchState`) carry `modifiedAt`, a tombstone and the
        // CloudKit record's system fields, so CKSyncEngine (M7) needs no migration (ADR 0002).
        migrator.registerMigration("v1") { db in
            try db.create(table: "instance") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("displayName", .text).notNull()
                t.column("apiURL", .text).notNull()
                t.column("sortOrder", .integer).notNull()
                t.column("addedAt", .datetime).notNull()
            }
            try db.create(table: "subscription") { t in
                t.primaryKey("channelID", .text)
                t.column("channelName", .text).notNull()
                t.column("avatarURL", .text)
                t.column("subscribedAt", .datetime).notNull()
                t.column("modifiedAt", .datetime).notNull()
                t.column("isDeleted", .boolean).notNull().defaults(to: false)
                t.column("syncMetadata", .blob)
            }
            try db.create(table: "video") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("channelID", .text).notNull()
                t.column("channelName", .text).notNull()
                t.column("durationSeconds", .integer)
                t.column("publishedAt", .datetime)
                t.column("publishedText", .text)
                t.column("viewCount", .integer)
                t.column("thumbnails", .jsonText).notNull()
                t.column("isLive", .boolean).notNull()
                t.column("isShort", .boolean).notNull()
                t.column("fetchedAt", .datetime).notNull()
            }
            try db.create(index: "video_on_channel_published", on: "video", columns: ["channelID", "publishedAt"])
            try db.create(index: "video_on_published", on: "video", columns: ["publishedAt"])
            try db.create(table: "watchState") { t in
                t.primaryKey("videoID", .text)
                t.column("positionSeconds", .double).notNull()
                t.column("durationSeconds", .double)
                t.column("isFinished", .boolean).notNull().defaults(to: false)
                t.column("lastWatchedAt", .datetime).notNull()
                t.column("modifiedAt", .datetime).notNull()
                t.column("isDeleted", .boolean).notNull().defaults(to: false)
                t.column("syncMetadata", .blob)
            }
            try db.create(table: "refreshLog") { t in
                t.primaryKey("resource", .text)
                t.column("refreshedAt", .datetime).notNull()
            }
            try db.create(table: "manifestCache") { t in
                t.primaryKey("videoID", .text)
                t.column("payload", .blob).notNull()
                t.column("expiresAt", .datetime).notNull()
            }
        }
        return migrator
    }
}
