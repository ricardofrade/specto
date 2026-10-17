import Foundation
import Testing
import Core
import Library
@testable import FeedFeature

struct FeedSectionTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return calendar
    }()

    private func row(_ id: String, _ date: Date?) -> FeedRow {
        RowFormatter(now: date ?? .now).row(
            VideoSummary(id: VideoID(rawValue: id), title: id, channelID: ChannelID(rawValue: "UCaaaaaaaaaaaaaaaaaaaaaa"),
                         channelName: "Blender", duration: .seconds(60), publishedAt: date, viewCount: 1, thumbnails: []),
            positionSeconds: nil, durationSeconds: nil)
    }

    @Test func groupsByPeriodKeepingOrder() {
        let now = Date.now
        let rows = [row("today", now.addingTimeInterval(-60)),
                    row("yesterday", calendar.date(byAdding: .day, value: -1, to: now)),
                    row("week", calendar.date(byAdding: .day, value: -4, to: now)),
                    row("old", calendar.date(byAdding: .day, value: -30, to: now)),
                    row("undated", nil)]
        let sections = FeedSection.group(rows, now: now, calendar: calendar)
        #expect(sections.map(\.period) == [.today, .yesterday, .thisWeek, .earlier])
        #expect(sections.last?.rows.map(\.id.rawValue) == ["old", "undated"])
        #expect(rows[0].channelInitial == "B")
    }
}
