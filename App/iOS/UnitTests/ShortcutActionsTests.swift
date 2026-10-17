import Foundation
import Testing
import Core
import Library
@testable import Specto

@MainActor
struct ShortcutActionsTests {
    private func video(_ id: String) -> VideoSummary {
        VideoSummary(id: VideoID(rawValue: id), title: id, channelID: ChannelID(rawValue: "UCaaaaaaaaaaaaaaaaaaaaaa"),
                     channelName: "A", duration: .seconds(600), publishedAt: .now, viewCount: 1, thumbnails: [])
    }

    @Test func continueWatchingPicksTheMostRecentVideoInProgress() throws {
        let environment = AppEnvironment(database: try .inMemory(), secrets: InMemorySecretStore())
        #expect(!ShortcutActions.continueWatching(environment))
        try FeedStore(environment.database).save([video("a"), video("b")])
        try WatchStateStore(environment.database).save(.seconds(60), duration: .seconds(600), for: VideoID(rawValue: "a"))
        try WatchStateStore(environment.database).save(.seconds(90), duration: .seconds(600), for: VideoID(rawValue: "b"))
        #expect(ShortcutActions.continueWatching(environment))
        #expect(environment.pendingVideo?.id.rawValue == "b")
    }

    @Test func playQueueStartsTheFirstQueuedVideo() throws {
        let environment = AppEnvironment(database: try .inMemory(), secrets: InMemorySecretStore())
        #expect(!ShortcutActions.playQueue(environment))
        try QueueStore(environment.database).add(video("q1"))
        try QueueStore(environment.database).add(video("q2"))
        #expect(ShortcutActions.playQueue(environment))
        #expect(environment.pendingVideo?.id.rawValue == "q1")
    }
}

@MainActor
struct HandoffTests {
    @Test func continuingSavesThePositionThenOpensTheVideo() throws {
        let environment = AppEnvironment(database: try .inMemory(), secrets: InMemorySecretStore())
        environment.continueWatching(["videoID": "aqz-KE-bpKQ", "position": 125.5, "duration": 596.0])
        #expect(environment.pendingVideo?.id.rawValue == "aqz-KE-bpKQ")
        #expect(try WatchStateStore(environment.database).position(for: VideoID(rawValue: "aqz-KE-bpKQ")) == .milliseconds(125_500))
    }

    @Test func ignoresActivitiesWithoutAVideo() throws {
        let environment = AppEnvironment(database: try .inMemory(), secrets: InMemorySecretStore())
        environment.continueWatching(["position": 10.0])
        #expect(environment.pendingVideo == nil)
    }
}
