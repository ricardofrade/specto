import Foundation
import GRDB

/// The database side of CloudKit sync, free of CloudKit types so it's testable offline:
/// which rows need uploading, applying fetched changes (last writer wins on `modifiedAt`),
/// and the sync engine's saved state.
public struct SyncStore: Sendable {
    public enum RecordType: String, Sendable, CaseIterable {
        case subscription = "Subscription"
        case watchState = "WatchState"
    }

    public struct Key: Hashable, Sendable {
        public let type: RecordType
        public let id: String

        public init(_ type: RecordType, _ id: String) {
            self.type = type
            self.id = id
        }
    }

    /// A synced row's values. Deletions are tombstones (`isDeleted`), so they carry a timestamp
    /// and win or lose like any other edit.
    public enum Values: Sendable, Equatable {
        case subscription(channelName: String, avatarURL: String?, subscribedAt: Date, isDeleted: Bool)
        case watchState(positionSeconds: Double, durationSeconds: Double?, isFinished: Bool,
                        lastWatchedAt: Date, isDeleted: Bool)
    }

    public struct Change: Sendable, Equatable {
        public let key: Key
        public let values: Values
        public let modifiedAt: Date
        /// Archived CloudKit system fields of the last known server record.
        public let systemFields: Data?

        public init(key: Key, values: Values, modifiedAt: Date, systemFields: Data?) {
            self.key = key
            self.values = values
            self.modifiedAt = modifiedAt
            self.systemFields = systemFields
        }
    }

    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    // MARK: Outgoing

    public func pendingKeys() throws -> [Key] {
        try database.writer.read(Self.fetchPending)
    }

    /// Emits the pending keys whenever they change, so local edits reach the engine on their own.
    public func observePending() -> AsyncThrowingStream<[Key], Error> {
        database.stream(Self.fetchPending)
    }

    public func change(for key: Key) throws -> Change? {
        try database.writer.read { db in
            switch key.type {
            case .subscription:
                try SubscriptionRecord.fetchOne(db, key: key.id).map { record in
                    Change(key: key, values: .subscription(channelName: record.channelName, avatarURL: record.avatarURL,
                                                            subscribedAt: record.subscribedAt, isDeleted: record.isDeleted),
                           modifiedAt: record.modifiedAt, systemFields: record.syncMetadata)
                }
            case .watchState:
                try WatchStateRecord.fetchOne(db, key: key.id).map { record in
                    Change(key: key, values: .watchState(positionSeconds: record.positionSeconds,
                                                          durationSeconds: record.durationSeconds,
                                                          isFinished: record.isFinished,
                                                          lastWatchedAt: record.lastWatchedAt, isDeleted: record.isDeleted),
                           modifiedAt: record.modifiedAt, systemFields: record.syncMetadata)
                }
            }
        }
    }

    /// The server accepted `modifiedAt`'s version. A newer local edit stays pending.
    public func markUploaded(_ key: Key, modifiedAt: Date, systemFields: Data) throws {
        try database.writer.write { db in
            let table = Self.table(key.type)
            try db.execute(sql: """
                UPDATE \(table.name) SET uploadedAt = ?, syncMetadata = ? WHERE \(table.key) = ?
                """, arguments: [modifiedAt, systemFields, key.id])
        }
    }

    /// Keep the server's change tag but upload our newer values again (a conflict we won).
    public func updateSystemFields(_ key: Key, _ systemFields: Data?) throws {
        try database.writer.write { db in
            let table = Self.table(key.type)
            try db.execute(sql: "UPDATE \(table.name) SET syncMetadata = ? WHERE \(table.key) = ?",
                           arguments: [systemFields, key.id])
        }
    }

    // MARK: Incoming

    /// Applies a fetched change unless the local row is newer. Applied changes aren't pending.
    @discardableResult
    public func apply(_ change: Change) throws -> Bool {
        try database.writer.write { db in
            let key = change.key
            switch change.values {
            case let .subscription(channelName, avatarURL, subscribedAt, isDeleted):
                let local = try SubscriptionRecord.fetchOne(db, key: key.id)
                guard Self.remoteWins(change.modifiedAt, over: local?.modifiedAt) else {
                    try Self.keepSystemFields(change, db)
                    return false
                }
                try SubscriptionRecord(channelID: key.id, channelName: channelName, avatarURL: avatarURL,
                                       subscribedAt: subscribedAt, modifiedAt: change.modifiedAt, isDeleted: isDeleted,
                                       syncMetadata: change.systemFields, uploadedAt: change.modifiedAt).save(db)
            case let .watchState(position, duration, isFinished, lastWatchedAt, isDeleted):
                let local = try WatchStateRecord.fetchOne(db, key: key.id)
                guard Self.remoteWins(change.modifiedAt, over: local?.modifiedAt) else {
                    try Self.keepSystemFields(change, db)
                    return false
                }
                try WatchStateRecord(videoID: key.id, positionSeconds: position, durationSeconds: duration,
                                     isFinished: isFinished, lastWatchedAt: lastWatchedAt,
                                     modifiedAt: change.modifiedAt, isDeleted: isDeleted,
                                     syncMetadata: change.systemFields, uploadedAt: change.modifiedAt).save(db)
            }
            return true
        }
    }

    /// The record is gone from the server (its zone was deleted, or iCloud data was reset).
    /// Keep the local row and upload it again from scratch.
    public func forgetServerRecord(_ key: Key) throws {
        try database.writer.write { db in
            let table = Self.table(key.type)
            try db.execute(sql: "UPDATE \(table.name) SET syncMetadata = NULL, uploadedAt = NULL WHERE \(table.key) = ?",
                           arguments: [key.id])
        }
    }

    /// Another iCloud account, or none: nothing on this device has been uploaded to it yet.
    public func resetForNewAccount() throws {
        try database.writer.write { db in
            for type in RecordType.allCases {
                try db.execute(sql: "UPDATE \(Self.table(type).name) SET syncMetadata = NULL, uploadedAt = NULL")
            }
            try db.execute(sql: "DELETE FROM syncState")
        }
    }

    // MARK: Engine state

    public func engineState() throws -> Data? {
        try database.writer.read { db in try Data.fetchOne(db, sql: "SELECT engineState FROM syncState WHERE id = 1") }
    }

    public func saveEngineState(_ data: Data) throws {
        try database.writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO syncState (id, engineState) VALUES (1, ?)", arguments: [data])
        }
    }

    // MARK: Private

    /// Equal timestamps keep the local row: re-applying our own upload is a no-op.
    static func remoteWins(_ remote: Date, over local: Date?) -> Bool {
        guard let local else { return true }
        return remote > local
    }

    /// A losing remote change still carries the newest change tag, which our next upload needs.
    private static func keepSystemFields(_ change: Change, _ db: Database) throws {
        let table = table(change.key.type)
        try db.execute(sql: "UPDATE \(table.name) SET syncMetadata = ? WHERE \(table.key) = ?",
                       arguments: [change.systemFields, change.key.id])
    }

    private static func table(_ type: RecordType) -> (name: String, key: String) {
        switch type {
        case .subscription: ("subscription", "channelID")
        case .watchState: ("watchState", "videoID")
        }
    }

    private static func fetchPending(_ db: Database) throws -> [Key] {
        let pending = "uploadedAt IS NULL OR modifiedAt > uploadedAt"
        let subscriptions = try String.fetchAll(db, sql: "SELECT channelID FROM subscription WHERE \(pending)")
        let states = try String.fetchAll(db, sql: "SELECT videoID FROM watchState WHERE \(pending)")
        return subscriptions.map { Key(.subscription, $0) } + states.map { Key(.watchState, $0) }
    }
}
