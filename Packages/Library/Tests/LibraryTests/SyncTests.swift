import CloudKit
import Foundation
import Testing
import Core
@testable import Library

private let channel = ChannelSummary(id: ChannelID(rawValue: "UCaaaaaaaaaaaaaaaaaaaaaa"), name: "A", avatar: nil)
private let video = VideoID(rawValue: "aqz-KE-bpKQ")

@Suite struct SyncStoreTests {
    @Test func localEditsArePendingUntilUploaded() throws {
        let db = try AppDatabase.inMemory()
        let sync = SyncStore(db)
        try SubscriptionStore(db).subscribe([channel])
        try WatchStateStore(db).save(.seconds(42), duration: .seconds(600), for: video)
        let keys = try sync.pendingKeys()
        #expect(Set(keys) == [SyncStore.Key(.subscription, channel.id.rawValue), SyncStore.Key(.watchState, video.rawValue)])

        for key in keys {
            let change = try #require(try sync.change(for: key))
            try sync.markUploaded(key, modifiedAt: change.modifiedAt, systemFields: Data([1]))
        }
        #expect(try sync.pendingKeys().isEmpty)

        // A later edit is pending again, and keeps the server's change tag.
        try WatchStateStore(db).save(.seconds(50), duration: .seconds(600), for: video)
        #expect(try sync.pendingKeys() == [SyncStore.Key(.watchState, video.rawValue)])
        #expect(try sync.change(for: SyncStore.Key(.watchState, video.rawValue))?.systemFields == Data([1]))
    }

    @Test func resubscribingWithoutChangesIsNotAnEdit() throws {
        let db = try AppDatabase.inMemory()
        let sync = SyncStore(db)
        try SubscriptionStore(db).subscribe([channel])
        let key = SyncStore.Key(.subscription, channel.id.rawValue)
        let change = try #require(try sync.change(for: key))
        try sync.markUploaded(key, modifiedAt: change.modifiedAt, systemFields: Data())
        try SubscriptionStore(db).subscribe([channel])
        #expect(try sync.pendingKeys().isEmpty)
    }

    @Test func newerRemoteChangeWinsAndIsNotReuploaded() throws {
        let db = try AppDatabase.inMemory()
        let sync = SyncStore(db)
        try SubscriptionStore(db).subscribe([channel])
        let key = SyncStore.Key(.subscription, channel.id.rawValue)
        let remote = SyncStore.Change(key: key, values: .subscription(channelName: "A", avatarURL: nil,
                                                                       subscribedAt: .now, isDeleted: true),
                                      modifiedAt: .now.addingTimeInterval(60), systemFields: Data([9]))
        #expect(try sync.apply(remote))
        #expect(try SubscriptionStore(db).channels().isEmpty)   // Unsubscribed on another device.
        #expect(try sync.pendingKeys().isEmpty)
    }

    @Test func olderRemoteChangeLosesButLeavesItsChangeTag() throws {
        let db = try AppDatabase.inMemory()
        let sync = SyncStore(db)
        try WatchStateStore(db).save(.seconds(300), duration: .seconds(600), for: video)
        let key = SyncStore.Key(.watchState, video.rawValue)
        let remote = SyncStore.Change(key: key, values: .watchState(positionSeconds: 10, durationSeconds: 600, isFinished: false,
                                                                     lastWatchedAt: .distantPast, isDeleted: false),
                                      modifiedAt: .distantPast, systemFields: Data([7]))
        #expect(try !sync.apply(remote))
        #expect(try WatchStateStore(db).position(for: video) == .seconds(300))
        #expect(try sync.change(for: key)?.systemFields == Data([7]))
        #expect(try sync.pendingKeys() == [key])
    }

    @Test func newAccountUploadsEverythingAgain() throws {
        let db = try AppDatabase.inMemory()
        let sync = SyncStore(db)
        try SubscriptionStore(db).subscribe([channel])
        let key = SyncStore.Key(.subscription, channel.id.rawValue)
        let change = try #require(try sync.change(for: key))
        try sync.markUploaded(key, modifiedAt: change.modifiedAt, systemFields: Data([1]))
        try sync.saveEngineState(Data([2]))
        try sync.resetForNewAccount()
        #expect(try sync.pendingKeys() == [key])
        #expect(try sync.change(for: key)?.systemFields == nil)
        #expect(try sync.engineState() == nil)
    }
}

@Suite struct CloudRecordsTests {
    @Test func recordsRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let changes = [
            SyncStore.Change(key: SyncStore.Key(.subscription, channel.id.rawValue),
                             values: .subscription(channelName: "A", avatarURL: "https://example.com/a.jpg",
                                                   subscribedAt: date, isDeleted: false),
                             modifiedAt: date, systemFields: nil),
            SyncStore.Change(key: SyncStore.Key(.watchState, video.rawValue),
                             values: .watchState(positionSeconds: 42.5, durationSeconds: nil, isFinished: false,
                                                 lastWatchedAt: date, isDeleted: false),
                             modifiedAt: date, systemFields: nil),
        ]
        for change in changes {
            let record = CloudRecords.record(for: change)
            let back = try #require(CloudRecords.change(from: record))
            #expect(back.key == change.key)
            #expect(back.values == change.values)
            #expect(back.modifiedAt == change.modifiedAt)
        }
    }

    @Test func uploadsReuseTheServerRecordsSystemFields() throws {
        let key = SyncStore.Key(.watchState, video.rawValue)
        let server = CKRecord(recordType: "WatchState", recordID: CloudRecords.recordID(for: key))
        let fields = CloudRecords.systemFields(of: server)
        let change = SyncStore.Change(key: key, values: .watchState(positionSeconds: 1, durationSeconds: 2, isFinished: false,
                                                                     lastWatchedAt: .now, isDeleted: false),
                                      modifiedAt: .now, systemFields: fields)
        let record = CloudRecords.record(for: change)
        #expect(record.recordID == server.recordID)
        #expect(record.recordID.zoneID == CloudRecords.zoneID)
    }

    @Test func unknownRecordsAreIgnored() {
        let record = CKRecord(recordType: "Playlist", recordID: CKRecord.ID(recordName: "Playlist/x", zoneID: CloudRecords.zoneID))
        #expect(CloudRecords.change(from: record) == nil)
        #expect(CloudRecords.key(for: CKRecord.ID(recordName: "no-slash", zoneID: CloudRecords.zoneID)) == nil)
    }
}
