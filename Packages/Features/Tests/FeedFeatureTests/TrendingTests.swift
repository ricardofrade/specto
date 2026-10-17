import Foundation
import Testing
import Core
import Library
@testable import FeedFeature

@MainActor
struct TrendingTests {
    @Test func loadsOnceAndLeavesShortsOut() async throws {
        let calls = Counter()
        let model = FeedModel(store: FeedStore(try AppDatabase.inMemory()), loadTrending: {
            await calls.increment()
            return [Self.video("a", false), Self.video("s", true), Self.video("b", false)]
        }) { _ in }
        await model.loadTrendingIfNeeded()
        await model.loadTrendingIfNeeded()
        #expect(model.trending.map(\.id.rawValue) == ["a", "b"])
        #expect(await calls.value == 1)
    }
}

extension TrendingTests {
    nonisolated static func video(_ id: String, _ short: Bool) -> VideoSummary {
        VideoSummary(id: VideoID(rawValue: id), title: id, channelID: ChannelID(rawValue: "UC"), channelName: "C",
                     duration: .seconds(60), publishedAt: nil, viewCount: nil, thumbnails: [], isShort: short)
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
