import Foundation
import Testing
import Core
@testable import Library

@Suite struct BackupTests {
    private let blender = ChannelSummary(id: ChannelID(rawValue: "UCSMOQeBJ2RAnuFungnQOxLg"), name: "Blender, the app", avatar: nil)
    private let other = ChannelSummary(id: ChannelID(rawValue: "UCbbbbbbbbbbbbbbbbbbbbbb"), name: "Other \"quoted\"", avatar: nil)
    private let video = VideoSummary(id: VideoID(rawValue: "aqz-KE-bpKQ"), title: "Big Buck Bunny",
                                     channelID: ChannelID(rawValue: "UCSMOQeBJ2RAnuFungnQOxLg"), channelName: "Blender",
                                     duration: .seconds(635), publishedAt: nil, viewCount: 10, thumbnails: [])

    private func filled() throws -> AppDatabase {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([blender, other])
        try SubscriptionStore(db).setHiddenFromHome(other.id, true)
        try FeedStore(db).save([video])
        try WatchStateStore(db).save(.seconds(120), duration: .seconds(635), for: video.id)
        try PlaylistStore(db).save(PlaylistSummary(id: PlaylistID(rawValue: "PLx"), title: "Talks", channelName: "Blender",
                                                   videoCount: 3, thumbnails: []))
        try InstanceStore(db).add(InstanceConfig(kind: .piped, displayName: "p", apiURL: URL(string: "https://p.example")!))
        try InstanceStore(db).add(InstanceConfig(kind: .ytZero, displayName: "z", apiURL: URL(string: "https://z.example")!))
        return db
    }

    @Test func roundTripsThroughJSONIntoAnotherDevice() throws {
        let data = try BackupStore(try filled()).encoded()
        #expect(!String(decoding: data, as: UTF8.self).contains("z.example"))   // YT Zero: paired, never exported.
        let backup = try BackupStore.decode(data)
        #expect(backup.subscriptions.count == 2 && backup.history.count == 1 && backup.instances.count == 1)

        let fresh = try AppDatabase.inMemory()
        let summary = try BackupStore(fresh).restore(backup)
        #expect(summary == Backup.Summary(subscriptions: 2, history: 1, playlists: 1, instances: 1))
        #expect(try SubscriptionStore(fresh).hiddenFromHome() == [other.id])
        #expect(try WatchStateStore(fresh).position(for: video.id) == .seconds(120))
        #expect(try WatchStateStore(fresh).history().first?.title == "Big Buck Bunny")
        #expect(try PlaylistStore(fresh).all().map(\.title) == ["Talks"])
        #expect(try InstanceStore(fresh).all().map(\.apiURL.host) == ["p.example"])

        // Restoring again changes nothing.
        #expect(try BackupStore(fresh).restore(backup) == Backup.Summary())
    }

    @Test func newerLocalProgressIsKept() throws {
        let backup = try BackupStore(try filled()).backup()
        let device = try AppDatabase.inMemory()
        Thread.sleep(forTimeInterval: 0.01)
        try WatchStateStore(device).save(.seconds(300), duration: .seconds(635), for: video.id)
        _ = try BackupStore(device).restore(backup)
        #expect(try WatchStateStore(device).position(for: video.id) == .seconds(300))
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: Backup.Failure.notABackup) { try BackupStore.decode(Data(#"{"subscriptions":[]}"#.utf8)) }
        let future = #"{"app":"Specto","version":99,"exportedAt":"2026-10-17T10:00:00Z","subscriptions":[],"history":[],"playlists":[],"instances":[]}"#
        #expect(throws: Backup.Failure.newerVersion(99)) { try BackupStore.decode(Data(future.utf8)) }
    }

    @Test func subscriptionsCSVIsTakeoutCompatible() throws {
        let csv = try BackupStore(try filled()).subscriptionsCSV()
        let lines = csv.split(separator: "\n").map(String.init)
        #expect(lines.first == "Channel Id,Channel Url,Channel Title")
        #expect(lines.contains("UCSMOQeBJ2RAnuFungnQOxLg,http://www.youtube.com/channel/UCSMOQeBJ2RAnuFungnQOxLg,\"Blender, the app\""))
        #expect(lines.contains { $0.hasSuffix(",\"Other \"\"quoted\"\"\"") })
        // And this app reads it back.
        #expect(try SubscriptionImport.parse(Data(csv.utf8)).count == 2)
    }
}
