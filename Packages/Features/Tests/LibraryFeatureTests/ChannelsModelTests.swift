import Foundation
import Testing
import Core
import Library
@testable import LibraryFeature

@MainActor
struct ChannelsModelTests {
    private func channel(_ id: String, _ name: String) -> ChannelSummary {
        ChannelSummary(id: ChannelID(rawValue: id), name: name, avatar: nil)
    }

    @Test func listsAToZAndFiltersAsYouType() throws {
        let db = try AppDatabase.inMemory()
        try SubscriptionStore(db).subscribe([channel("UC1", "veritasium"), channel("UC2", "Blender"),
                                             channel("UC3", "Linus Tech Tips")])
        let model = ChannelsModel(subscriptions: SubscriptionStore(db))
        #expect(model.rows.map(\.name) == ["Blender", "Linus Tech Tips", "veritasium"])
        #expect(model.rows.first?.avatar.initial == "B")

        model.query = "tech"
        #expect(model.rows.map(\.name) == ["Linus Tech Tips"])
        #expect(model.total == 3)
        model.query = "  "
        #expect(model.rows.count == 3)
    }
}
