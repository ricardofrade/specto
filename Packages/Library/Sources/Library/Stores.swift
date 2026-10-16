import Foundation
import GRDB
import Core

// MARK: - Instances

public struct InstanceStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func all() throws -> [InstanceConfig] {
        try database.writer.read { db in
            try InstanceRecord.order(Column("sortOrder")).fetchAll(db).compactMap(\.config)
        }
    }

    public func add(_ instance: InstanceConfig) throws {
        try database.writer.write { db in
            let next = (try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM instance") ?? -1) + 1
            try InstanceRecord(id: instance.id.uuidString, kind: instance.kind.rawValue,
                               displayName: instance.displayName, apiURL: instance.apiURL.absoluteString,
                               sortOrder: next, addedAt: .now).save(db)
        }
    }

    public func remove(_ id: UUID) throws {
        _ = try database.writer.write { db in try InstanceRecord.deleteOne(db, key: id.uuidString) }
    }

    public func observe() -> AsyncThrowingStream<[InstanceConfig], Error> {
        database.stream { db in try InstanceRecord.order(Column("sortOrder")).fetchAll(db).compactMap(\.config) }
    }
}

// MARK: - Subscriptions

public struct SubscriptionStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func channels() throws -> [ChannelSummary] {
        try database.writer.read { db in try Self.active.fetchAll(db).map(\.summary) }
    }

    public func observe() -> AsyncThrowingStream<[ChannelSummary], Error> {
        database.stream { db in try Self.active.fetchAll(db).map(\.summary) }
    }

    public func subscribe(_ channels: [ChannelSummary]) throws {
        try database.writer.write { db in
            for channel in channels {
                var record = try SubscriptionRecord.fetchOne(db, key: channel.id.rawValue)
                    ?? SubscriptionRecord(channelID: channel.id.rawValue, channelName: channel.name, avatarURL: nil,
                                          subscribedAt: .now, modifiedAt: .now, isDeleted: false, syncMetadata: nil)
                record.channelName = channel.name.isEmpty ? record.channelName : channel.name
                record.avatarURL = channel.avatar?.url.absoluteString ?? record.avatarURL
                record.isDeleted = false
                record.modifiedAt = .now
                try record.save(db)
            }
        }
    }

    /// A tombstone, so the deletion syncs.
    public func unsubscribe(_ channel: ChannelID) throws {
        try database.writer.write { db in
            guard var record = try SubscriptionRecord.fetchOne(db, key: channel.rawValue) else { return }
            record.isDeleted = true
            record.modifiedAt = .now
            try record.update(db)
        }
    }

    /// Mirror an account's list (YT Zero is the source of truth when linked, ADR 0002).
    public func replaceAll(with channels: [ChannelSummary]) throws {
        try database.writer.write { db in
            let keep = Set(channels.map(\.id.rawValue))
            for record in try SubscriptionRecord.fetchAll(db) where !keep.contains(record.channelID) && !record.isDeleted {
                var tombstone = record
                tombstone.isDeleted = true
                tombstone.modifiedAt = .now
                try tombstone.update(db)
            }
        }
        try subscribe(channels)
    }

    private static let active = SubscriptionRecord.filter(Column("isDeleted") == false)
        .order(Column("channelName").collating(.localizedCaseInsensitiveCompare))
}

// MARK: - Videos and the feed

public struct FeedStore: Sendable {
    public struct Options: Sendable, Equatable {
        public var hideShorts: Bool
        public var hideWatched: Bool
        public var limit: Int

        public init(hideShorts: Bool = true, hideWatched: Bool = false, limit: Int = 300) {
            self.hideShorts = hideShorts
            self.hideWatched = hideWatched
            self.limit = limit
        }
    }

    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func save(_ videos: [VideoSummary]) throws {
        let now = Date.now
        try database.writer.write { db in
            for video in videos {
                var record = VideoRecord(video, fetchedAt: now)
                // Some sources omit durations (Invidious Atom feeds); never erase a known one.
                if record.durationSeconds == nil,
                   let existing = try VideoRecord.fetchOne(db, key: video.id.rawValue) {
                    record.durationSeconds = existing.durationSeconds
                }
                try record.save(db)
            }
        }
    }

    /// Rows for the subscribed channels, newest first, formatted on the database's thread.
    public func rows(_ options: Options = Options()) throws -> [FeedRow] {
        try database.writer.read { db in try Self.fetchRows(db, options: options) }
    }

    public func observe(_ options: Options = Options()) -> AsyncThrowingStream<[FeedRow], Error> {
        database.stream { db in try Self.fetchRows(db, options: options) }
    }

    /// Videos for one channel from the local cache.
    public func videos(channel: ChannelID, limit: Int = 60) throws -> [VideoSummary] {
        try database.writer.read { db in
            try VideoRecord.filter(Column("channelID") == channel.rawValue)
                .order(Column("publishedAt").desc).limit(limit).fetchAll(db).map(\.summary)
        }
    }

    /// Drop videos older than `days` that nobody started watching, to bound the cache.
    public func prune(olderThan days: Int = 120) throws {
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 86_400)
        _ = try database.writer.write { db in
            try db.execute(sql: """
                DELETE FROM video WHERE publishedAt < ? AND id NOT IN (SELECT videoID FROM watchState)
                """, arguments: [cutoff])
        }
    }

    static func fetchRows(_ db: Database, options: Options) throws -> [FeedRow] {
        var sql = """
            SELECT video.*, watchState.positionSeconds AS position, watchState.durationSeconds AS length,
                   watchState.isFinished AS finished
            FROM video
            JOIN subscription ON subscription.channelID = video.channelID AND subscription.isDeleted = 0
            LEFT JOIN watchState ON watchState.videoID = video.id AND watchState.isDeleted = 0
            """
        var conditions: [String] = []
        if options.hideShorts { conditions.append("video.isShort = 0") }
        if options.hideWatched { conditions.append("IFNULL(watchState.isFinished, 0) = 0") }
        if !conditions.isEmpty { sql += " WHERE " + conditions.joined(separator: " AND ") }
        sql += " ORDER BY video.publishedAt DESC LIMIT ?"

        let formatter = RowFormatter()
        return try Row.fetchAll(db, sql: sql, arguments: [options.limit]).map { row in
            let record = try VideoRecord(row: row)
            let finished: Bool = row["finished"] ?? false
            return formatter.row(record.summary,
                                 positionSeconds: finished ? (row["length"] ?? row["position"]) : row["position"],
                                 durationSeconds: row["length"])
        }
    }
}

// MARK: - Watch state (resume positions)

public struct WatchStateStore: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func position(for id: VideoID) throws -> Duration? {
        try database.writer.read { db in
            guard let state = try WatchStateRecord.fetchOne(db, key: id.rawValue), !state.isDeleted,
                  !state.isFinished, state.positionSeconds >= 5 else { return nil }
            return .milliseconds(Int64(state.positionSeconds * 1000))
        }
    }

    /// Positions within the last 5% (or 30 s) count as finished, so the next play starts over.
    public func save(_ position: Duration, duration: Duration?, for id: VideoID) throws {
        let seconds = Self.seconds(position)
        let length = duration.map(Self.seconds)
        let finished = length.map { seconds >= $0 - max(30, $0 * 0.05) } ?? false
        try database.writer.write { db in
            try WatchStateRecord(videoID: id.rawValue, positionSeconds: seconds, durationSeconds: length,
                                 isFinished: finished, lastWatchedAt: .now, modifiedAt: .now,
                                 isDeleted: false, syncMetadata: nil).save(db)
        }
    }

    /// Mirror positions reported by an account (YT Zero), without touching newer local ones.
    public func merge(_ entries: [AccountVideo]) throws {
        try database.writer.write { db in
            for entry in entries {
                let existing = try WatchStateRecord.fetchOne(db, key: entry.video.id.rawValue)
                guard entry.resumePosition != nil || entry.isWatched else { continue }
                if let existing, existing.lastWatchedAt > Date.now.addingTimeInterval(-60) { continue }
                try WatchStateRecord(videoID: entry.video.id.rawValue,
                                     positionSeconds: entry.resumePosition.map(Self.seconds) ?? existing?.positionSeconds ?? 0,
                                     durationSeconds: entry.video.duration.map(Self.seconds),
                                     isFinished: entry.isWatched, lastWatchedAt: existing?.lastWatchedAt ?? .now,
                                     modifiedAt: .now, isDeleted: false,
                                     syncMetadata: existing?.syncMetadata).save(db)
            }
        }
    }

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

// MARK: - Manifest cache (tap-to-play budget)

/// Watch pages fetched ahead of a tap (dwell, touch-down, top of the feed), so playback can
/// start without a network round-trip. Entries expire with their stream URLs.
public struct ManifestCache: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    /// Only entries that stay valid for at least `margin` more.
    public func page(for id: VideoID, margin: TimeInterval = 120) throws -> WatchPage? {
        try database.writer.read { db in
            guard let record = try ManifestCacheRecord.fetchOne(db, key: id.rawValue),
                  record.expiresAt > Date.now.addingTimeInterval(margin) else { return nil }
            return try? JSONDecoder().decode(WatchPage.self, from: record.payload)
        }
    }

    public func store(_ page: WatchPage) throws {
        // Without an expiry, assume YouTube's usual six hours minus a safety margin.
        let expires = page.manifest.expiresAt ?? Date.now.addingTimeInterval(5 * 3600)
        let payload = try JSONEncoder().encode(page)
        try database.writer.write { db in
            try ManifestCacheRecord(videoID: page.manifest.videoID.rawValue, payload: payload, expiresAt: expires).save(db)
            try db.execute(sql: "DELETE FROM manifestCache WHERE expiresAt < ?", arguments: [Date.now])
        }
    }
}

// MARK: - Refresh bookkeeping

public struct RefreshLog: Sendable {
    let database: AppDatabase

    public init(_ database: AppDatabase) {
        self.database = database
    }

    public func isStale(_ resource: String, after interval: TimeInterval) throws -> Bool {
        try database.writer.read { db in
            guard let record = try RefreshRecord.fetchOne(db, key: resource) else { return true }
            return record.refreshedAt < Date.now.addingTimeInterval(-interval)
        }
    }

    public func lastRefresh(_ resource: String) throws -> Date? {
        try database.writer.read { db in try RefreshRecord.fetchOne(db, key: resource)?.refreshedAt }
    }

    public func markRefreshed(_ resource: String) throws {
        try database.writer.write { db in try RefreshRecord(resource: resource, refreshedAt: .now).save(db) }
    }
}

// MARK: - Observation helper

extension AppDatabase {
    /// A GRDB `ValueObservation` as a plain async stream, so features never import GRDB.
    func stream<T: Sendable>(_ fetch: @escaping @Sendable (Database) throws -> T) -> AsyncThrowingStream<T, Error> {
        let observation = ValueObservation.tracking(fetch)
        let writer = self.writer
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in observation.values(in: writer) {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
