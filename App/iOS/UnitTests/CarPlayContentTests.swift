import Foundation
import Testing
import Core
import Library
@testable import Specto

private func row(_ id: String, duration: Duration? = .seconds(754)) -> FeedRow {
    let video = VideoSummary(id: VideoID(rawValue: id), title: "Video \(id)",
                             channelID: ChannelID(rawValue: "UCaaaaaaaaaaaaaaaaaaaaaa"), channelName: "Channel",
                             duration: duration, publishedAt: nil, viewCount: nil, thumbnails: [], isShort: false)
    return RowFormatter().row(video, positionSeconds: nil, durationSeconds: nil)
}

@Suite struct CarPlayContentTests {
    @Test func tabsAreContinueQueueSubscriptionsInOrder() {
        let content = CarPlayContent(continueListening: [], queue: [], subscriptions: [], offline: [])
        #expect(content.tabs.map(\.title) == ["Continue", "Queue", "Subscriptions"])
        #expect(content.tabs.allSatisfy { $0.items.isEmpty && !$0.emptyMessage.isEmpty })
    }

    @Test func listsAreCappedForCarPlay() {
        let many = (0..<100).map { row("v\($0)") }
        let content = CarPlayContent(continueListening: [], queue: [], subscriptions: many, offline: [])
        let subscriptions = content.tabs[2].items
        #expect(subscriptions.count == CarPlayContent.maxItems)
        #expect(subscriptions.first?.row.id.rawValue == "v0")
    }

    @Test func detailJoinsChannelDurationAndOfflineMark() {
        let content = CarPlayContent(continueListening: [], queue: [row("a"), row("b", duration: nil)],
                                     subscriptions: [], offline: ["a"])
        let queue = content.tabs[1].items
        #expect(queue[0].detail == "Channel · 12:34 · Downloaded")
        #expect(queue[0].isOffline)
        #expect(queue[1].detail == "Channel")
        #expect(!queue[1].isOffline)
    }
}
