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
            SyncStore.Change(key: SyncStore.Key(.subscription, "UCbbbbbbbbbbbbbbbbbbbbbb"),
                             values: .subscription(channelName: "B", avatarURL: nil, subscribedAt: date, isDeleted: false,
                                                   hiddenFromHome: true, mutesNotifications: true),
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

@Suite struct PlaylistStoreTests {
    private let playlist = PlaylistSummary(id: PlaylistID(rawValue: "PLabc"), title: "Talks", channelName: "Blender",
                                           videoCount: 12,
                                           thumbnails: [Thumbnail(url: URL(string: "https://proxy.example/vi/x/mq.jpg")!,
                                                                  width: 320, height: 180)])

    @Test func savesNewestFirstAndRemovesWithATombstone() throws {
        let db = try AppDatabase.inMemory()
        let store = PlaylistStore(db)
        try store.save(playlist)
        Thread.sleep(forTimeInterval: 0.01)
        let other = PlaylistSummary(id: PlaylistID(rawValue: "PLdef"), title: "Shorts", channelName: nil,
                                    videoCount: nil, thumbnails: [])
        try store.save(other)
        #expect(try store.all().map(\.id) == [other.id, playlist.id])
        let saved = try #require(try store.all().last)
        #expect(saved.title == "Talks" && saved.channelName == "Blender" && saved.videoCount == 12)
        #expect(saved.thumbnails.first?.url == playlist.thumbnails.first?.url)   // Stored without its size.
        #expect(try store.isSaved(playlist.id))

        try store.remove(playlist.id)
        #expect(try !store.isSaved(playlist.id))
        #expect(try store.all() == [other])
        #expect(try SyncStore(db).pendingKeys().contains(SyncStore.Key(.playlist, "PLabc")))
    }

    @Test func savingAgainUnchangedIsNotAnEdit() throws {
        let db = try AppDatabase.inMemory()
        try PlaylistStore(db).save(playlist)
        let key = SyncStore.Key(.playlist, playlist.id.rawValue)
        let sync = SyncStore(db)
        try sync.markUploaded(key, modifiedAt: try #require(try sync.change(for: key)).modifiedAt, systemFields: Data())
        try PlaylistStore(db).save(playlist)
        #expect(try sync.pendingKeys().isEmpty)
    }

    @Test func syncsThroughACloudKitRecord() throws {
        let phone = try AppDatabase.inMemory(), tv = try AppDatabase.inMemory()
        try PlaylistStore(phone).save(playlist)
        let change = try #require(try SyncStore(phone).change(for: SyncStore.Key(.playlist, playlist.id.rawValue)))
        let fetched = try #require(CloudRecords.change(from: CloudRecords.record(for: change)))
        #expect(try SyncStore(tv, types: [.instance, .playlist]).apply(fetched))
        #expect(try PlaylistStore(tv).all().map(\.id) == [playlist.id])
        #expect(try PlaylistStore(tv).all().first?.title == "Talks")
    }
}

@Suite struct UserPlaylistTests {
    private func video(_ id: String) -> VideoSummary {
        VideoSummary(id: VideoID(rawValue: id), title: "Video \(id)", channelID: ChannelID(rawValue: "UC"),
                     channelName: "C", duration: .seconds(60), publishedAt: nil, viewCount: nil, thumbnails: [])
    }

    @Test func watchLaterIsAlwaysFirstAndAppearsOnFirstUse() throws {
        let store = UserPlaylistStore(try AppDatabase.inMemory())
        #expect(try store.all().map(\.id) == [UserPlaylist.watchLaterID])
        #expect(try store.all().first?.videos.isEmpty == true)
        try store.toggleWatchLater(video("a"))
        let mine = try store.create(title: "Trips")
        #expect(try store.all().map(\.id) == [UserPlaylist.watchLaterID, mine.id])
        #expect(try store.playlist(UserPlaylist.watchLaterID)?.contains(VideoID(rawValue: "a")) == true)
        try store.toggleWatchLater(video("a"))
        #expect(try store.playlist(UserPlaylist.watchLaterID)?.videos.isEmpty == true)
        try store.delete(UserPlaylist.watchLaterID)     // Can't be deleted.
        #expect(try store.all().first?.isWatchLater == true)
    }

    @Test func addOnceReorderRemoveRenameDelete() throws {
        let db = try AppDatabase.inMemory()
        let store = UserPlaylistStore(db)
        let list = try store.create(title: "Mix", with: video("a"))
        try store.add(video("b"), to: list.id)
        try store.add(video("c"), to: list.id)
        try store.add(video("a"), to: list.id)          // Already there: stays first.
        #expect(try store.playlist(list.id)?.videos.map(\.id.rawValue) == ["a", "b", "c"])
        try store.move(in: list.id, from: [2], to: 0)
        #expect(try store.playlist(list.id)?.videos.map(\.id.rawValue) == ["c", "a", "b"])
        try store.remove(VideoID(rawValue: "a"), from: list.id)
        try store.rename(list.id, to: "Road trip")
        #expect(try store.playlist(list.id)?.title == "Road trip")
        #expect(try store.playlist(list.id)?.videos.count == 2)
        try store.delete(list.id)
        #expect(try store.playlist(list.id) == nil)
        #expect(try SyncStore(db).pendingKeys().contains(SyncStore.Key(.userPlaylist, list.id)))
    }

    @Test func syncsAsOneRecordWithItsOrder() throws {
        let phone = try AppDatabase.inMemory(), tv = try AppDatabase.inMemory()
        let list = try UserPlaylistStore(phone).create(title: "Mix", with: video("b"))
        try UserPlaylistStore(phone).add(video("a"), to: list.id)
        let change = try #require(try SyncStore(phone).change(for: SyncStore.Key(.userPlaylist, list.id)))
        let fetched = try #require(CloudRecords.change(from: CloudRecords.record(for: change)))
        #expect(try SyncStore(tv).apply(fetched))
        #expect(try UserPlaylistStore(tv).playlist(list.id)?.videos.map(\.id.rawValue) == ["b", "a"])
    }

    @Test func backupCarriesThem() throws {
        let phone = try AppDatabase.inMemory()
        try UserPlaylistStore(phone).toggleWatchLater(video("w"))
        let list = try UserPlaylistStore(phone).create(title: "Mix", with: video("m"))
        let backup = try BackupStore.decode(try BackupStore(phone).encoded())
        let fresh = try AppDatabase.inMemory()
        let summary = try BackupStore(fresh).restore(backup)
        #expect(summary.userPlaylists == 2)
        #expect(try UserPlaylistStore(fresh).playlist(list.id)?.title == "Mix")
        #expect(try UserPlaylistStore(fresh).playlist(UserPlaylist.watchLaterID)?.videos.map(\.id.rawValue) == ["w"])
    }
}
