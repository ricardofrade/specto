import Foundation
import Testing
import Core
import Library
@testable import SearchFeature

@MainActor
struct SearchModelTests {
    private let video = VideoSummary(id: VideoID(rawValue: "aaaaaaaaaaa"), title: "A video", channelID: ChannelID(rawValue: "UC1"),
                                     channelName: "Channel", duration: nil, publishedAt: nil, viewCount: nil, thumbnails: [])
    private let channel = ChannelSummary(id: ChannelID(rawValue: "UC1"), name: "blender", avatar: nil)

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func eachFilterAsksForItsKind() async throws {
        let filters = Recorder<SearchFilter>()
        let (video, channel) = (self.video, self.channel)
        let model = SearchModel(search: { _, filter, _ in
            await filters.add(filter)
            return Page(items: filter == .channels ? [.channel(channel)] : [.video(video)], nextCursor: nil)
        })
        model.query = "blender"
        await model.submit()
        #expect(model.rows.map(\.id) == ["video/aaaaaaaaaaa"])

        model.filter = .channels   // Searches the same query again.
        await waitUntil { model.rows.first?.id == "channel/UC1" }
        guard case .channel(_, let avatar) = try #require(model.rows.first) else {
            Issue.record("Not a channel row")
            return
        }
        #expect(avatar.initial == "B")
        #expect(await filters.values == [.videos, .channels])
    }

    @Test func suggestionsWaitForTypingToStop() async {
        let asked = Recorder<String>()
        let model = SearchModel(search: { _, _, _ in Page(items: [], nextCursor: nil) },
                                suggest: { query in
                                    await asked.add(query)
                                    return ["\(query) tutorial", "\(query) guru"]
                                })
        model.query = "b"
        model.query = "bl"
        model.query = "ble"
        await waitUntil { !model.suggestions.isEmpty }
        #expect(model.suggestions == ["ble tutorial", "ble guru"])
        #expect(await asked.values == ["ble"])
        #expect(model.completions == model.suggestions)
    }

    @Test func recentSearchesComeFirstAndCanBeCleared() async throws {
        let store = RecentSearchStore(try AppDatabase.inMemory())
        let model = SearchModel(search: { _, _, _ in Page(items: [], nextCursor: nil) }, recent: store)
        await model.start()
        model.query = "first"
        await model.submit()
        await model.search("second")
        await waitUntil { model.recent.count == 2 }
        #expect(model.recent == ["second", "first"])
        model.query = ""
        #expect(model.completions == ["second", "first"])
        #expect(model.phase == .idle && model.rows.isEmpty)   // Back to the recent list.
        model.clearRecent()
        await waitUntil { model.recent.isEmpty }
        #expect(model.recent.isEmpty)
    }
}

private actor Recorder<Value: Sendable> {
    private(set) var values: [Value] = []
    func add(_ value: Value) { values.append(value) }
}
