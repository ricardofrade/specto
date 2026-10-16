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

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif
        // Schema arrives with the first feature that stores data; M0 ships it empty.
        return migrator
    }
}
