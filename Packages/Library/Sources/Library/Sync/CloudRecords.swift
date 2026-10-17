import CloudKit
import Foundation

/// Maps `SyncStore` changes to and from CloudKit records, in one private-database zone.
/// Record names are "<type>/<id>", so a record ID alone says which table it belongs to.
enum CloudRecords {
    static let zoneID = CKRecordZone.ID(zoneName: "Library", ownerName: CKCurrentUserDefaultName)

    enum Field {
        static let modifiedAt = "modifiedAt"
        static let isDeleted = "isDeleted"
        static let channelName = "channelName"
        static let avatarURL = "avatarURL"
        static let subscribedAt = "subscribedAt"
        static let hiddenFromHome = "hiddenFromHome"
        static let positionSeconds = "positionSeconds"
        static let durationSeconds = "durationSeconds"
        static let isFinished = "isFinished"
        static let lastWatchedAt = "lastWatchedAt"
        static let kind = "kind"
        static let displayName = "displayName"
        static let apiURL = "apiURL"
        static let sortOrder = "sortOrder"
        static let addedAt = "addedAt"
        static let title = "title"
        static let videoCount = "videoCount"
        static let thumbnailURL = "thumbnailURL"
        static let savedAt = "savedAt"
        static let videos = "videos"
        static let createdAt = "createdAt"
        /// In `encryptedValues`: end-to-end encrypted with keys in the user's iCloud Keychain.
        static let token = "token"
    }

    static func recordID(for key: SyncStore.Key) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(key.type.rawValue)/\(key.id)", zoneID: zoneID)
    }

    static func key(for recordID: CKRecord.ID) -> SyncStore.Key? {
        let parts = recordID.recordName.split(separator: "/", maxSplits: 1)
        guard parts.count == 2, let type = SyncStore.RecordType(rawValue: String(parts[0])) else { return nil }
        return SyncStore.Key(type, String(parts[1]))
    }

    /// The record to upload: the last server record's system fields (so CloudKit sees an update,
    /// not a conflict) with the local values written over them.
    static func record(for change: SyncStore.Change) -> CKRecord {
        let record = change.systemFields.flatMap(unarchive)
            ?? CKRecord(recordType: change.key.type.rawValue, recordID: recordID(for: change.key))
        record[Field.modifiedAt] = change.modifiedAt
        switch change.values {
        case let .subscription(channelName, avatarURL, subscribedAt, isDeleted, hiddenFromHome):
            record[Field.channelName] = channelName
            record[Field.avatarURL] = avatarURL
            record[Field.subscribedAt] = subscribedAt
            record[Field.hiddenFromHome] = hiddenFromHome
            record[Field.isDeleted] = isDeleted
        case let .watchState(position, duration, isFinished, lastWatchedAt, isDeleted):
            record[Field.positionSeconds] = position
            record[Field.durationSeconds] = duration
            record[Field.isFinished] = isFinished
            record[Field.lastWatchedAt] = lastWatchedAt
            record[Field.isDeleted] = isDeleted
        case let .playlist(title, channelName, videoCount, thumbnailURL, savedAt, isDeleted):
            record[Field.title] = title
            record[Field.channelName] = channelName
            record[Field.videoCount] = videoCount
            record[Field.thumbnailURL] = thumbnailURL
            record[Field.savedAt] = savedAt
            record[Field.isDeleted] = isDeleted
        case let .userPlaylist(title, videos, createdAt, isDeleted):
            record[Field.title] = title
            record[Field.videos] = videos
            record[Field.createdAt] = createdAt
            record[Field.isDeleted] = isDeleted
        case let .instance(kind, displayName, apiURL, sortOrder, addedAt, token, isDeleted):
            record[Field.kind] = kind
            record[Field.displayName] = displayName
            record[Field.apiURL] = apiURL
            record[Field.sortOrder] = sortOrder
            record[Field.addedAt] = addedAt
            record.encryptedValues[Field.token] = isDeleted ? nil : token
            record[Field.isDeleted] = isDeleted
        }
        return record
    }

    /// nil for records this version doesn't understand (another type, missing fields).
    static func change(from record: CKRecord) -> SyncStore.Change? {
        guard let key = key(for: record.recordID), key.type.rawValue == record.recordType,
              let modifiedAt = record[Field.modifiedAt] as? Date else { return nil }
        let isDeleted = record[Field.isDeleted] as? Bool ?? false
        let values: SyncStore.Values
        switch key.type {
        case .subscription:
            guard let name = record[Field.channelName] as? String,
                  let subscribedAt = record[Field.subscribedAt] as? Date else { return nil }
            values = .subscription(channelName: name, avatarURL: record[Field.avatarURL] as? String,
                                   subscribedAt: subscribedAt, isDeleted: isDeleted,
                                   hiddenFromHome: record[Field.hiddenFromHome] as? Bool ?? false)
        case .watchState:
            guard let position = record[Field.positionSeconds] as? Double,
                  let lastWatchedAt = record[Field.lastWatchedAt] as? Date else { return nil }
            values = .watchState(positionSeconds: position, durationSeconds: record[Field.durationSeconds] as? Double,
                                 isFinished: record[Field.isFinished] as? Bool ?? false,
                                 lastWatchedAt: lastWatchedAt, isDeleted: isDeleted)
        case .playlist:
            guard let title = record[Field.title] as? String, let savedAt = record[Field.savedAt] as? Date else { return nil }
            values = .playlist(title: title, channelName: record[Field.channelName] as? String,
                               videoCount: record[Field.videoCount] as? Int,
                               thumbnailURL: record[Field.thumbnailURL] as? String, savedAt: savedAt, isDeleted: isDeleted)
        case .userPlaylist:
            guard let title = record[Field.title] as? String, let videos = record[Field.videos] as? Data,
                  let createdAt = record[Field.createdAt] as? Date else { return nil }
            values = .userPlaylist(title: title, videos: videos, createdAt: createdAt, isDeleted: isDeleted)
        case .instance:
            guard let kind = record[Field.kind] as? String, let displayName = record[Field.displayName] as? String,
                  let apiURL = record[Field.apiURL] as? String, let addedAt = record[Field.addedAt] as? Date else { return nil }
            values = .instance(kind: kind, displayName: displayName, apiURL: apiURL,
                               sortOrder: record[Field.sortOrder] as? Int ?? 0, addedAt: addedAt,
                               token: record.encryptedValues[Field.token] as? String, isDeleted: isDeleted)
        }
        return SyncStore.Change(key: key, values: values, modifiedAt: modifiedAt, systemFields: systemFields(of: record))
    }

    static func systemFields(of record: CKRecord) -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    static func unarchive(_ data: Data) -> CKRecord? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }
}
