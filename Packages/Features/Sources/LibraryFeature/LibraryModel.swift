import Foundation
import Observation
import Core
import Library
import DesignSystem

/// A playlist card on Library's Playlists shelf: one of the person's, or one saved from YouTube.
public struct LibraryPlaylistCard: Identifiable, Hashable, Sendable {
    public enum Target: Hashable, Sendable {
        case own(String)
        case saved(PlaylistSummary)
    }
    public let target: Target
    public let title: String
    public let subtitle: String?
    public let thumbnailURL: URL?
    public let symbol: String
    public var id: String {
        switch target {
        case .own(let id): "own/\(id)"
        case .saved(let playlist): "saved/\(playlist.id.rawValue)"
        }
    }
}

/// A channel on Library's Channels shelf.
public struct LibraryChannelItem: Identifiable, Hashable, Sendable {
    public let channel: ChannelSummary
    public let avatar: VideoCellContent.Avatar
    public var id: ChannelID { channel.id }
}

/// What you've watched and what's next: Continue Watching, the queue and the history, live from
/// the database (cache first; nothing here needs the network).
@Observable
public final class LibraryModel {
    public private(set) var continueWatching: [FeedRow]
    public private(set) var queue: [FeedRow]
    public private(set) var history: [FeedRow]
    /// History rows matching the search field, or nil while it's empty.
    public private(set) var historyResults: [FeedRow]?
    /// How many channels the person subscribes to, for the Channels row.
    public private(set) var channelCount: Int
    /// How many playlists are saved, for the Playlists row.
    public private(set) var playlistCount: Int
    /// Watch Later (once it has something), the person's playlists, then saved ones.
    public private(set) var playlistCards: [LibraryPlaylistCard] = []
    /// Subscriptions A to Z, for the Channels shelf (the first few dozen).
    public private(set) var channelItems: [LibraryChannelItem] = []

    @ObservationIgnored private let watchState: WatchStateStore
    @ObservationIgnored private let queueStore: QueueStore
    @ObservationIgnored private let subscriptions: SubscriptionStore?
    @ObservationIgnored private let playlists: PlaylistStore?
    @ObservationIgnored private let userPlaylists: UserPlaylistStore?
    @ObservationIgnored private var savedCount = 0
    @ObservationIgnored private var ownCount = 0
    @ObservationIgnored private var ownCards: [LibraryPlaylistCard] = []
    @ObservationIgnored private var savedCards: [LibraryPlaylistCard] = []
    @ObservationIgnored private var observations: [Task<Void, Never>] = []

    public init(watchState: WatchStateStore, queue: QueueStore, subscriptions: SubscriptionStore? = nil,
                playlists: PlaylistStore? = nil, userPlaylists: UserPlaylistStore? = nil) {
        self.userPlaylists = userPlaylists
        self.watchState = watchState
        self.queueStore = queue
        self.subscriptions = subscriptions
        self.playlists = playlists
        let channels = (try? subscriptions?.channels()) ?? []
        channelCount = channels.count
        let saved = (try? playlists?.all()) ?? []
        let own = (try? userPlaylists?.all()) ?? []
        savedCount = saved.count
        ownCount = Self.countOwn(own)
        playlistCount = savedCount + ownCount
        channelItems = Self.items(channels)
        ownCards = Self.cards(own: own)
        savedCards = Self.cards(saved: saved)
        playlistCards = ownCards + savedCards
        continueWatching = (try? watchState.inProgress()) ?? []
        self.queue = (try? queue.rows()) ?? []
        history = (try? watchState.history()) ?? []
    }

    /// Observe the database. Call from `.task`.
    public func start() async {
        guard observations.isEmpty else { return }
        let inProgress = watchState.observeInProgress(), queued = queueStore.observe(), watched = watchState.observeHistory()
        observations = [
            Task { [weak self] in do { for try await rows in inProgress { self?.continueWatching = rows } } catch {} },
            Task { [weak self] in do { for try await rows in queued { self?.queue = rows } } catch {} },
            Task { [weak self] in do { for try await rows in watched { self?.history = rows } } catch {} },
        ]
        if let channels = subscriptions?.observe() {
            observations.append(Task { [weak self] in
                do {
                    for try await list in channels {
                        self?.channelCount = list.count
                        self?.channelItems = Self.items(list)
                    }
                } catch {}
            })
        }
        if let saved = playlists?.observe() {
            observations.append(Task { [weak self] in
                do {
                    for try await list in saved {
                        guard let self else { return }
                        self.savedCount = list.count
                        self.playlistCount = self.savedCount + self.ownCount
                        self.savedCards = Self.cards(saved: list)
                        self.playlistCards = self.ownCards + self.savedCards
                    }
                } catch {}
            })
        }
        if let own = userPlaylists?.observe() {
            observations.append(Task { [weak self] in
                do {
                    for try await list in own {
                        guard let self else { return }
                        self.ownCount = Self.countOwn(list)
                        self.playlistCount = self.savedCount + self.ownCount
                        self.ownCards = Self.cards(own: list)
                        self.playlistCards = self.ownCards + self.savedCards
                    }
                } catch {}
            })
        }
    }

    static let shelfChannelLimit = 40

    private static func items(_ channels: [ChannelSummary]) -> [LibraryChannelItem] {
        channels.prefix(shelfChannelLimit).map {
            LibraryChannelItem(channel: $0, avatar: .init(url: $0.avatar?.url, initial: RowFormatter.initial($0.name)))
        }
    }

    private static func cards(own: [UserPlaylist]) -> [LibraryPlaylistCard] {
        own.filter { !$0.isWatchLater || !$0.videos.isEmpty }.map { playlist in
            LibraryPlaylistCard(target: .own(playlist.id), title: playlist.displayTitle,
                                subtitle: String(localized: "\(playlist.videos.count) videos"),
                                thumbnailURL: playlist.videos.first?.thumbnails.best(forPixelWidth: 400)?.url,
                                symbol: playlist.isWatchLater ? "clock" : "list.bullet")
        }
    }

    private static func cards(saved: [PlaylistSummary]) -> [LibraryPlaylistCard] {
        saved.map { playlist in
            LibraryPlaylistCard(target: .saved(playlist), title: playlist.title,
                                subtitle: playlist.channelName,
                                thumbnailURL: playlist.thumbnails.best(forPixelWidth: 400)?.url,
                                symbol: "rectangle.stack")
        }
    }

    /// Watch Later counts once it has something in it; made playlists always.
    private static func countOwn(_ list: [UserPlaylist]) -> Int {
        list.filter { !$0.isWatchLater || !$0.videos.isEmpty }.count
    }

    public var isEmpty: Bool { continueWatching.isEmpty && queue.isEmpty && history.isEmpty && channelCount == 0 && playlistCount == 0 }

    /// Searches the whole history off the main actor; an empty query clears the results.
    public func searchHistory(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { historyResults = nil; return }
        let store = watchState
        let rows = await Task.detached(priority: .userInitiated) { (try? store.searchHistory(trimmed)) ?? [] }.value
        guard !Task.isCancelled else { return }
        historyResults = rows
    }

    public func removeFromHistory(_ id: VideoID) {
        try? watchState.removeFromHistory(id)
    }

    public func clearHistory() {
        try? watchState.clearHistory()
    }

    public func removeFromQueue(_ id: VideoID) {
        try? queueStore.remove(id)
    }

    public func moveQueue(from source: IndexSet, to destination: Int) {
        var ids = queue.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        try? queueStore.reorder(ids)
    }
}
