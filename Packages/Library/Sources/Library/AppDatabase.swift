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

    /// `Application Support/Library/app.sqlite`. On tvOS, `Caches/Library/app.sqlite`: tvOS
    /// keeps no persistent local storage, so there the database is a cache that sync refills.
    public static func defaultURL() throws -> URL {
        #if os(tvOS)
        let directory = FileManager.SearchPathDirectory.cachesDirectory
        #else
        let directory = FileManager.SearchPathDirectory.applicationSupportDirectory
        #endif
        return try FileManager.default.url(for: directory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "Library/app.sqlite")
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        // Synced tables (`subscription`, `watchState`, and `instance` since v5) carry `modifiedAt`, a tombstone and the
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
        // DeArrow branding lives beside videos, so refreshing a video never loses it.
        migrator.registerMigration("v2-branding") { db in
            try db.create(table: "branding") { t in
                t.primaryKey("videoID", .text)
                t.column("title", .text)
                t.column("thumbnailTime", .double)
                t.column("fetchedAt", .datetime).notNull()
            }
        }
        // Listening queue (CarPlay, "play next") and offline audio downloads (M6).
        migrator.registerMigration("v3-queue-downloads") { db in
            try db.create(table: "queueItem") { t in
                t.primaryKey("videoID", .text)
                t.column("position", .double).notNull()
                t.column("addedAt", .datetime).notNull()
            }
            try db.create(table: "download") { t in
                t.primaryKey("videoID", .text)
                t.column("state", .text).notNull()
                t.column("fileName", .text)
                t.column("bytes", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("completedAt", .datetime)
                t.column("lastPlayedAt", .datetime)
            }
        }
        // CloudKit sync (M7): a row needs uploading while `modifiedAt > uploadedAt`, and the
        // sync engine's own state is kept here so it resumes where it left off.
        migrator.registerMigration("v4-sync") { db in
            try db.alter(table: "subscription") { t in t.add(column: "uploadedAt", .datetime) }
            try db.alter(table: "watchState") { t in t.add(column: "uploadedAt", .datetime) }
            try db.create(table: "syncState") { t in
                t.primaryKey("id", .integer)
                t.column("engineState", .blob)
            }
        }
        // Instances sync too, so the Apple TV gets the phone's (ADR 0006). `scope` records which
        // record types the saved engine state covers; a different scope re-syncs from scratch.
        migrator.registerMigration("v5-instance-sync") { db in
            try db.alter(table: "instance") { t in
                t.add(column: "modifiedAt", .datetime)
                t.add(column: "isDeleted", .boolean).notNull().defaults(to: false)
                t.add(column: "syncMetadata", .blob)
                t.add(column: "uploadedAt", .datetime)
            }
            try db.execute(sql: "UPDATE instance SET modifiedAt = addedAt")
            try db.alter(table: "syncState") { t in t.add(column: "scope", .text) }
        }
        return migrator
    }
}
