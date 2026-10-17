import Foundation
import Observation
import Core
import Library
import DesignSystem

/// One subscribed channel, ready to draw.
public struct ChannelRow: Identifiable, Hashable, Sendable {
    public let channel: ChannelSummary
    public let avatar: VideoCellContent.Avatar
    public var id: ChannelID { channel.id }
    public var name: String { channel.name }

    init(_ channel: ChannelSummary) {
        self.channel = channel
        avatar = VideoCellContent.Avatar(url: channel.avatar?.url, initial: RowFormatter.initial(channel.name))
    }
}

/// Subscriptions, A to Z, filtered as you type (in the model, never in `body`).
@Observable
public final class ChannelsModel {
    public var query = "" {
        didSet { applyQuery() }
    }
    public private(set) var rows: [ChannelRow] = []
    public private(set) var total = 0

    @ObservationIgnored private var all: [ChannelRow] = []
    @ObservationIgnored private let store: SubscriptionStore
    @ObservationIgnored private var observation: Task<Void, Never>?

    public init(subscriptions: SubscriptionStore) {
        store = subscriptions
        update((try? subscriptions.channels()) ?? [])
    }

    /// Observe the database. Call from `.task`.
    public func start() async {
        guard observation == nil else { return }
        let changes = store.observe()
        observation = Task { [weak self] in
            do { for try await channels in changes { self?.update(channels) } } catch {}
        }
    }

    private func update(_ channels: [ChannelSummary]) {
        all = channels.map(ChannelRow.init)   // The store sorts by name.
        total = all.count
        applyQuery()
    }

    private func applyQuery() {
        let query = query.trimmingCharacters(in: .whitespaces)
        rows = query.isEmpty ? all : all.filter { $0.name.localizedStandardContains(query) }
    }
}
