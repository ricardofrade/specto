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

/// ADR 0006: instances sync (so the TV gets the phone's), with the YT Zero token alongside.
@Suite struct InstanceSyncTests {
    private let zero = InstanceConfig(kind: .ytZero, displayName: "zero", apiURL: URL(string: "https://zero.example")!)

    @Test func theTokenTravelsWithTheInstance() throws {
        let phone = try AppDatabase.inMemory(), phoneSecrets = InMemorySecretStore()
        phoneSecrets.setSecret("secret-token", for: InstanceConfig.tokenKey(for: zero.id))
        try InstanceStore(phone).add(zero)
        let key = SyncStore.Key(.instance, zero.id.uuidString)
        #expect(try SyncStore(phone).pendingKeys() == [key])
        let change = try #require(try SyncStore(phone, secrets: phoneSecrets).change(for: key))

        // Through a CloudKit record, the token in its encrypted values.
        let record = CloudRecords.record(for: change)
        #expect(record["token"] == nil)
        #expect(record.encryptedValues["token"] as? String == "secret-token")
        let fetched = try #require(CloudRecords.change(from: record))

        let tv = try AppDatabase.inMemory(), tvSecrets = InMemorySecretStore()
        #expect(try SyncStore(tv, secrets: tvSecrets).apply(fetched))
        #expect(try InstanceStore(tv).all() == [zero])
        #expect(tvSecrets.secret(for: InstanceConfig.tokenKey(for: zero.id)) == "secret-token")
        #expect(try SyncStore(tv).pendingKeys().isEmpty)
    }

    @Test func removalIsATombstoneThatTakesTheTokenAlong() throws {
        let phone = try AppDatabase.inMemory(), tv = try AppDatabase.inMemory(), tvSecrets = InMemorySecretStore()
        try InstanceStore(phone).add(zero)
        let key = SyncStore.Key(.instance, zero.id.uuidString)
        let added = try #require(try SyncStore(phone).change(for: key))
        try SyncStore(tv, secrets: tvSecrets).apply(added)
        tvSecrets.setSecret("secret-token", for: InstanceConfig.tokenKey(for: zero.id))

        Thread.sleep(forTimeInterval: 0.01)   // A later modifiedAt than the add.
        try InstanceStore(phone).remove(zero.id)
        #expect(try InstanceStore(phone).all().isEmpty)
        #expect(try SyncStore(phone).pendingKeys() == [key])
        let removed = try #require(try SyncStore(phone).change(for: key))
        #expect(try SyncStore(tv, secrets: tvSecrets).apply(removed))
        #expect(try InstanceStore(tv).all().isEmpty)
        #expect(tvSecrets.secret(for: InstanceConfig.tokenKey(for: zero.id)) == nil)
    }

    @Test func theSameInstanceAddedOnTwoDevicesShowsOnce() throws {
        let db = try AppDatabase.inMemory()
        let piped = InstanceConfig(kind: .piped, displayName: "p", apiURL: URL(string: "https://p.example")!)
        try InstanceStore(db).add(piped)
        let other = InstanceConfig(kind: .piped, displayName: "p", apiURL: piped.apiURL)
        try SyncStore(db).apply(SyncStore.Change(
            key: SyncStore.Key(.instance, other.id.uuidString),
            values: .instance(kind: "piped", displayName: "p", apiURL: piped.apiURL.absoluteString, sortOrder: 0,
                              addedAt: .now, token: nil, isDeleted: false),
            modifiedAt: .now, systemFields: nil))
        #expect(try InstanceStore(db).all().map(\.apiURL) == [piped.apiURL])
        #expect(try InstanceStore(db).contains(piped.apiURL))
        try InstanceStore(db).add(other)   // A no-op.
        #expect(try InstanceStore(db).all().count == 1)
    }

    /// A linked YT Zero account owns the library (ADR 0002): only instances sync.
    @Test func outOfScopeTypesNeitherUploadNorApply() throws {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([channel])
        try InstanceStore(db).add(zero)
        let sync = SyncStore(db, types: [.instance])
        #expect(try sync.pendingKeys() == [SyncStore.Key(.instance, zero.id.uuidString)])
        let remote = SyncStore.Change(key: SyncStore.Key(.subscription, "UCbbbbbbbbbbbbbbbbbbbbbb"),
                                      values: .subscription(channelName: "B", avatarURL: nil, subscribedAt: .now,
                                                            isDeleted: false),
                                      modifiedAt: .now, systemFields: nil)
        #expect(try !sync.apply(remote))
        #expect(try SubscriptionStore(db).channels() == [channel])
    }

    @Test func aChangeOfScopeStartsOver() throws {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([channel])
        let full = SyncStore(db)
        let key = SyncStore.Key(.subscription, channel.id.rawValue)
        try full.markUploaded(key, modifiedAt: try #require(try full.change(for: key)).modifiedAt, systemFields: Data([1]))
        try full.saveEngineState(Data([2]))

        try full.prepareScope()   // Same scope: carry on.
        #expect(try full.engineState() == Data([2]))

        try SyncStore(db, types: [.instance]).prepareScope()
        #expect(try full.engineState() == nil)
        #expect(try full.pendingKeys() == [key])
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
            SyncStore.Change(key: SyncStore.Key(.instance, UUID().uuidString),
                             values: .instance(kind: "invidious", displayName: "I", apiURL: "https://i.example",
                                               sortOrder: 3, addedAt: date, token: nil, isDeleted: false),
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
