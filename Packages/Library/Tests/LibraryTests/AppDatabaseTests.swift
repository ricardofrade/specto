import Foundation
import Testing
import GRDB
@testable import Library

struct AppDatabaseTests {
    @Test func onDiskDatabaseUsesWAL() throws {
        let url = URL.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "app.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let database = try AppDatabase.onDisk(at: url)
        let mode = try database.writer.read { try String.fetchOne($0, sql: "PRAGMA journal_mode") }
        #expect(mode == "wal")
    }

    @Test func inMemoryDatabaseOpens() throws {
        let database = try AppDatabase.inMemory()
        let one = try database.writer.read { try Int.fetchOne($0, sql: "SELECT 1") }
        #expect(one == 1)
    }
}
