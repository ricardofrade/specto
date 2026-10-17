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
    /// On Home, but no new-upload notifications.
    public let mutesNotifications: Bool
    public var id: ChannelID { channel.id }
    public var name: String { channel.name }

    init(_ channel: ChannelSummary, hidden: Bool, muted: Bool) {
        self.channel = channel
        isHiddenFromHome = hidden
        mutesNotifications = muted
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
    @ObservationIgnored private var muted: Set<ChannelID> = []
    @ObservationIgnored private let store: SubscriptionStore
    @ObservationIgnored private var observations: [Task<Void, Never>] = []

    public init(subscriptions: SubscriptionStore) {
        store = subscriptions
        channels = (try? subscriptions.channels()) ?? []
        hidden = (try? subscriptions.hiddenFromHome()) ?? []
        muted = (try? subscriptions.mutedChannels()) ?? []
        update()
    }

    /// Observe the database. Call from `.task`.
    public func start() async {
        guard observations.isEmpty else { return }
        let changes = store.observe(), hiddenChanges = store.observeHiddenFromHome()
        let mutedChanges = store.observeMutedChannels()
        observations = [
            Task { [weak self] in
                do { for try await list in changes { self?.channels = list; self?.update() } } catch {}
            },
            Task { [weak self] in
                do { for try await set in hiddenChanges { self?.hidden = set; self?.update() } } catch {}
            },
            Task { [weak self] in
                do { for try await set in mutedChanges { self?.muted = set; self?.update() } } catch {}
            },
        ]
    }

    /// Take the channel's videos off Home, or bring them back.
    public func toggleHidden(_ row: ChannelRow) {
        try? store.setHiddenFromHome(row.id, !row.isHiddenFromHome)
    }

    /// Stop or restart new-upload notifications for the channel.
    public func toggleNotifications(_ row: ChannelRow) {
        try? store.setMutesNotifications(row.id, !row.mutesNotifications)
    }

    private func update() {
        all = channels.map { ChannelRow($0, hidden: hidden.contains($0.id), muted: muted.contains($0.id)) }   // The store sorts by name.
        total = all.count
        applyQuery()
    }

    private func applyQuery() {
        let query = query.trimmingCharacters(in: .whitespaces)
        rows = query.isEmpty ? all : all.filter { $0.name.localizedStandardContains(query) }
    }
}
