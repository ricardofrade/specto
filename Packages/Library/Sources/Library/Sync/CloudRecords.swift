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
        static let positionSeconds = "positionSeconds"
        static let durationSeconds = "durationSeconds"
        static let isFinished = "isFinished"
        static let lastWatchedAt = "lastWatchedAt"
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
        case let .subscription(channelName, avatarURL, subscribedAt, isDeleted):
            record[Field.channelName] = channelName
            record[Field.avatarURL] = avatarURL
            record[Field.subscribedAt] = subscribedAt
            record[Field.isDeleted] = isDeleted
        case let .watchState(position, duration, isFinished, lastWatchedAt, isDeleted):
            record[Field.positionSeconds] = position
            record[Field.durationSeconds] = duration
            record[Field.isFinished] = isFinished
            record[Field.lastWatchedAt] = lastWatchedAt
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
                                   subscribedAt: subscribedAt, isDeleted: isDeleted)
        case .watchState:
            guard let position = record[Field.positionSeconds] as? Double,
                  let lastWatchedAt = record[Field.lastWatchedAt] as? Date else { return nil }
            values = .watchState(positionSeconds: position, durationSeconds: record[Field.durationSeconds] as? Double,
                                 isFinished: record[Field.isFinished] as? Bool ?? false,
                                 lastWatchedAt: lastWatchedAt, isDeleted: isDeleted)
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
