import Foundation
import Library

/// What CarPlay lists show, built from the same stores as the app. Plain values so it's testable
/// without CarPlay (templates are made from these in `CarPlaySceneDelegate`).
nonisolated struct CarPlayContent: Sendable {
    struct Item: Hashable, Sendable {
        let row: FeedRow
        let title: String
        let detail: String
        /// Playable offline (downloaded audio).
        let isOffline: Bool
    }

    struct Tab: Sendable {
        let title: String
        let systemImage: String
        let items: [Item]
        let emptyMessage: String
    }

    let continueListening: [FeedRow]
    let queue: [FeedRow]
    let subscriptions: [FeedRow]
    let offline: Set<String>

    /// CarPlay limits list lengths; keep the most relevant items.
    static let maxItems = 24

    var tabs: [Tab] {
        [
            Tab(title: String(localized: "Continue"), systemImage: "play.circle",
                items: items(continueListening), emptyMessage: String(localized: "Nothing in progress")),
            Tab(title: String(localized: "Queue"), systemImage: "list.bullet",
                items: items(queue), emptyMessage: String(localized: "Add videos to your queue on your iPhone")),
            Tab(title: String(localized: "Subscriptions"), systemImage: "play.square.stack",
                items: items(subscriptions), emptyMessage: String(localized: "No new videos")),
        ]
    }

    private func items(_ rows: [FeedRow]) -> [Item] {
        rows.prefix(Self.maxItems).map { row in
            let offline = offline.contains(row.id.rawValue)
            let detail = [row.channelName, row.durationText, offline ? String(localized: "Downloaded") : nil]
                .compactMap { $0 }.joined(separator: " · ")
            return Item(row: row, title: row.title, detail: detail, isOffline: offline)
        }
    }
}
