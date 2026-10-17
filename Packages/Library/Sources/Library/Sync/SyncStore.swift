import Foundation
import GRDB
import Core

/// The database side of CloudKit sync, free of CloudKit types so it's testable offline:
/// which rows need uploading, applying fetched changes (last writer wins on `modifiedAt`),
/// and the sync engine's saved state. YT Zero tokens travel with their instance, from and to
/// the `SecretStore` (never the database).
public struct SyncStore: Sendable {
    public enum RecordType: String, Sendable, CaseIterable {
        case subscription = "Subscription"
        case watchState = "WatchState"
        case instance = "Instance"
        case playlist = "Playlist"
        case userPlaylist = "UserPlaylist"
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
        case subscription(channelName: String, avatarURL: String?, subscribedAt: Date, isDeleted: Bool,
                          hiddenFromHome: Bool = false)
        case watchState(positionSeconds: Double, durationSeconds: Double?, isFinished: Bool,
                        lastWatchedAt: Date, isDeleted: Bool)
        case instance(kind: String, displayName: String, apiURL: String, sortOrder: Int, addedAt: Date,
                      token: String?, isDeleted: Bool)
        case playlist(title: String, channelName: String?, videoCount: Int?, thumbnailURL: String?, savedAt: Date,
                      isDeleted: Bool)
        /// The videos as JSON, in order: the whole list syncs as one value (ADR 0012).
        case userPlaylist(title: String, videos: Data, createdAt: Date, isDeleted: Bool)
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
    /// What syncs: everything, or only instances while a YT Zero account owns the library (ADR 0002).
    public let types: Set<RecordType>
    let secrets: (any SecretStore)?

    public init(_ database: AppDatabase, types: Set<RecordType> = Set(RecordType.allCases),
                secrets: (any SecretStore)? = nil) {
        self.database = database
        self.types = types
        self.secrets = secrets
    }

    // MARK: Outgoing

    public func pendingKeys() throws -> [Key] {
        let types = self.types
        return try database.writer.read { try Self.fetchPending($0, types) }
    }

    /// Emits the pending keys whenever they change, so local edits reach the engine on their own.
    public func observePending() -> AsyncThrowingStream<[Key], Error> {
        let types = self.types
        return database.stream { try Self.fetchPending($0, types) }
    }

    public func change(for key: Key) throws -> Change? {
        let secrets = self.secrets
        return try database.writer.read { db in
            switch key.type {
            case .subscription:
                try SubscriptionRecord.fetchOne(db, key: key.id).map { record in
                    Change(key: key, values: .subscription(channelName: record.channelName, avatarURL: record.avatarURL,
                                                            subscribedAt: record.subscribedAt, isDeleted: record.isDeleted,
                                                            hiddenFromHome: record.hiddenFromHome),
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
            case .playlist:
                try SavedPlaylistRecord.fetchOne(db, key: key.id).map { record in
                    Change(key: key, values: .playlist(title: record.title, channelName: record.channelName,
                                                        videoCount: record.videoCount, thumbnailURL: record.thumbnailURL,
                                                        savedAt: record.savedAt, isDeleted: record.isDeleted),
                           modifiedAt: record.modifiedAt, systemFields: record.syncMetadata)
                }
            case .userPlaylist:
                try UserPlaylistRecord.fetchOne(db, key: key.id).map { record in
                    Change(key: key, values: .userPlaylist(title: record.title, videos: record.videos,
                                                            createdAt: record.createdAt, isDeleted: record.isDeleted),
                           modifiedAt: record.modifiedAt, systemFields: record.syncMetadata)
                }
            case .instance:
                try InstanceRecord.fetchOne(db, key: key.id).map { record in
                    let token = UUID(uuidString: record.id).flatMap { secrets?.secret(for: InstanceConfig.tokenKey(for: $0)) }
                    return Change(key: key, values: .instance(kind: record.kind, displayName: record.displayName,
                                                              apiURL: record.apiURL, sortOrder: record.sortOrder,
                                                              addedAt: record.addedAt, token: token, isDeleted: record.isDeleted),
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
    /// Types outside `types` are ignored; a later change of scope fetches them again.
    @discardableResult
    public func apply(_ change: Change) throws -> Bool {
        guard types.contains(change.key.type) else { return false }
        let secrets = self.secrets
        return try database.writer.write { db in
            let key = change.key
            switch change.values {
            case let .subscription(channelName, avatarURL, subscribedAt, isDeleted, hiddenFromHome):
                let local = try SubscriptionRecord.fetchOne(db, key: key.id)
                guard Self.remoteWins(change.modifiedAt, over: local?.modifiedAt) else {
                    try Self.keepSystemFields(change, db)
                    return false
                }
                try SubscriptionRecord(channelID: key.id, channelName: channelName, avatarURL: avatarURL,
                                       subscribedAt: subscribedAt, modifiedAt: change.modifiedAt, isDeleted: isDeleted,
                                       syncMetadata: change.systemFields, uploadedAt: change.modifiedAt,
                                       hiddenFromHome: hiddenFromHome).save(db)
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
            case let .playlist(title, channelName, videoCount, thumbnailURL, savedAt, isDeleted):
                let local = try SavedPlaylistRecord.fetchOne(db, key: key.id)
                guard Self.remoteWins(change.modifiedAt, over: local?.modifiedAt) else {
                    try Self.keepSystemFields(change, db)
                    return false
                }
                try SavedPlaylistRecord(id: key.id, title: title, channelName: channelName, videoCount: videoCount,
                                        thumbnailURL: thumbnailURL, savedAt: savedAt, modifiedAt: change.modifiedAt,
                                        isDeleted: isDeleted, syncMetadata: change.systemFields,
                                        uploadedAt: change.modifiedAt).save(db)
            case let .userPlaylist(title, videos, createdAt, isDeleted):
                let local = try UserPlaylistRecord.fetchOne(db, key: key.id)
                guard Self.remoteWins(change.modifiedAt, over: local?.modifiedAt) else {
                    try Self.keepSystemFields(change, db)
                    return false
                }
                try UserPlaylistRecord(id: key.id, title: title, videos: videos, createdAt: createdAt,
                                       modifiedAt: change.modifiedAt, isDeleted: isDeleted,
                                       syncMetadata: change.systemFields, uploadedAt: change.modifiedAt).save(db)
            case let .instance(kind, displayName, apiURL, sortOrder, addedAt, token, isDeleted):
                let local = try InstanceRecord.fetchOne(db, key: key.id)
                guard Self.remoteWins(change.modifiedAt, over: local?.modifiedAt) else {
                    try Self.keepSystemFields(change, db)
                    return false
                }
                // The token first: observers reload sources when the row commits, and need it then.
                if let secrets, let id = UUID(uuidString: key.id) {
                    secrets.setSecret(isDeleted ? nil : token, for: InstanceConfig.tokenKey(for: id))
                }
                try InstanceRecord(id: key.id, kind: kind, displayName: displayName, apiURL: apiURL,
                                   sortOrder: sortOrder, addedAt: addedAt, modifiedAt: change.modifiedAt,
                                   isDeleted: isDeleted, syncMetadata: change.systemFields,
                                   uploadedAt: change.modifiedAt).save(db)
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
        let scope = self.scope
        try database.writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO syncState (id, engineState, scope) VALUES (1, ?, ?)",
                           arguments: [data, scope])
        }
    }

    /// Call before starting the engine. Saved state for other record types (an account was
    /// linked or unlinked since) would skip the records the old scope ignored: start over,
    /// fetching everything and uploading everything (last writer wins keeps that idempotent).
    public func prepareScope() throws {
        let saved = try database.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT scope FROM syncState WHERE id = 1").map { $0["scope"] as String? }
        }
        if case .some(let scope) = saved, scope != self.scope { try resetForNewAccount() }
    }

    private var scope: String { types.map(\.rawValue).sorted().joined(separator: ",") }

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
        case .instance: ("instance", "id")
        case .playlist: ("savedPlaylist", "id")
        case .userPlaylist: ("userPlaylist", "id")
        }
    }

    private static func fetchPending(_ db: Database, _ types: Set<RecordType>) throws -> [Key] {
        try RecordType.allCases.filter(types.contains).flatMap { type in
            let table = table(type)
            let sql = "SELECT \(table.key) FROM \(table.name) WHERE uploadedAt IS NULL OR modifiedAt > uploadedAt"
            return try String.fetchAll(db, sql: sql).map { Key(type, $0) }
        }
    }
}
