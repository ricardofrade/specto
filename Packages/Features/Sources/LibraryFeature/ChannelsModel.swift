import Foundation
import Observation
import Core
import Library
import DesignSystem

/// One subscribed channel, ready to draw.
public struct ChannelRow: Identifiable, Hashable, Sendable {
    public let channel: ChannelSummary
    public let avatar: VideoCellContent.Avatar
    /// Subscribed, but kept off Home.
    public let isHiddenFromHome: Bool
    public var id: ChannelID { channel.id }
    public var name: String { channel.name }

    init(_ channel: ChannelSummary, hidden: Bool) {
        self.channel = channel
        isHiddenFromHome = hidden
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
    @ObservationIgnored private var channels: [ChannelSummary] = []
    @ObservationIgnored private var hidden: Set<ChannelID> = []
    @ObservationIgnored private let store: SubscriptionStore
    @ObservationIgnored private var observations: [Task<Void, Never>] = []

    public init(subscriptions: SubscriptionStore) {
        store = subscriptions
        channels = (try? subscriptions.channels()) ?? []
        hidden = (try? subscriptions.hiddenFromHome()) ?? []
        update()
    }

    /// Observe the database. Call from `.task`.
    public func start() async {
        guard observations.isEmpty else { return }
        let changes = store.observe(), hiddenChanges = store.observeHiddenFromHome()
        observations = [
            Task { [weak self] in
                do { for try await list in changes { self?.channels = list; self?.update() } } catch {}
            },
            Task { [weak self] in
                do { for try await set in hiddenChanges { self?.hidden = set; self?.update() } } catch {}
            },
        ]
    }

    /// Take the channel's videos off Home, or bring them back.
    public func toggleHidden(_ row: ChannelRow) {
        try? store.setHiddenFromHome(row.id, !row.isHiddenFromHome)
    }

    private func update() {
        all = channels.map { ChannelRow($0, hidden: hidden.contains($0.id)) }   // The store sorts by name.
        total = all.count
        applyQuery()
    }

    private func applyQuery() {
        let query = query.trimmingCharacters(in: .whitespaces)
        rows = query.isEmpty ? all : all.filter { $0.name.localizedStandardContains(query) }
    }
}
