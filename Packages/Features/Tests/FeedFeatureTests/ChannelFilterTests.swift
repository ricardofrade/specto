import Foundation
import Testing
import Core
import Library
@testable import FeedFeature

@MainActor
struct ChannelFilterTests {
    private let a = ChannelSummary(id: ChannelID(rawValue: "UCaaaaaaaaaaaaaaaaaaaaaa"), name: "Alpha", avatar: nil)
    private let b = ChannelSummary(id: ChannelID(rawValue: "UCbbbbbbbbbbbbbbbbbbbbbb"), name: "Beta", avatar: nil)

    private func model() throws -> FeedModel {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([a, b])
        let now = Date.now
        func video(_ id: String, _ channel: ChannelSummary, hoursAgo: Double) -> VideoSummary {
            VideoSummary(id: VideoID(rawValue: id), title: id, channelID: channel.id, channelName: channel.name,
                         duration: .seconds(60), publishedAt: now.addingTimeInterval(-hoursAgo * 3600),
                         viewCount: 1, thumbnails: [])
        }
        try FeedStore(db).save([video("b1", b, hoursAgo: 1), video("a1", a, hoursAgo: 2), video("b2", b, hoursAgo: 3)])
        return FeedModel(store: FeedStore(db)) { _ in }
    }

    @Test func stripListsChannelsByNewestUpload() throws {
        #expect(try model().channels.map(\.name) == ["Beta", "Alpha"])
    }

    @Test func filteringShowsOneChannelAndTappingAgainShowsAll() throws {
        let model = try model()
        model.filter(to: b.id)
        #expect(model.channelFilter == b.id)
        #expect(model.rows.map(\.id.rawValue) == ["b1", "b2"])
        #expect(model.channels.count == 2)   // The strip keeps every channel.

        model.filter(to: b.id)
        #expect(model.channelFilter == nil)
        #expect(model.rows.count == 3)

        model.filter(to: a.id)
        model.filter(to: nil)
        #expect(model.rows.count == 3)
    }
}
