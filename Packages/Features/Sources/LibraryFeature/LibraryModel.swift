import Foundation
import Observation
import Core
import Library

/// What you've watched and what's next: Continue Watching, the queue and the history, live from
/// the database (cache first; nothing here needs the network).
@Observable
public final class LibraryModel {
    public private(set) var continueWatching: [FeedRow]
    public private(set) var queue: [FeedRow]
    public private(set) var history: [FeedRow]
    /// How many channels the person subscribes to, for the Channels row.
    public private(set) var channelCount: Int
    /// How many playlists are saved, for the Playlists row.
    public private(set) var playlistCount: Int

    @ObservationIgnored private let watchState: WatchStateStore
    @ObservationIgnored private let queueStore: QueueStore
    @ObservationIgnored private let subscriptions: SubscriptionStore?
    @ObservationIgnored private let playlists: PlaylistStore?
    @ObservationIgnored private let userPlaylists: UserPlaylistStore?
    @ObservationIgnored private var savedCount = 0
    @ObservationIgnored private var ownCount = 0
    @ObservationIgnored private var observations: [Task<Void, Never>] = []

    public init(watchState: WatchStateStore, queue: QueueStore, subscriptions: SubscriptionStore? = nil,
                playlists: PlaylistStore? = nil, userPlaylists: UserPlaylistStore? = nil) {
        self.userPlaylists = userPlaylists
        self.watchState = watchState
        self.queueStore = queue
        self.subscriptions = subscriptions
        self.playlists = playlists
        channelCount = (try? subscriptions?.channels().count) ?? 0
        savedCount = (try? playlists?.all().count) ?? 0
        ownCount = Self.countOwn((try? userPlaylists?.all()) ?? [])
        playlistCount = savedCount + ownCount
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
                do { for try await list in channels { self?.channelCount = list.count } } catch {}
            })
        }
        if let saved = playlists?.observe() {
            observations.append(Task { [weak self] in
                do {
                    for try await list in saved {
                        guard let self else { return }
                        self.savedCount = list.count
                        self.playlistCount = self.savedCount + self.ownCount
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
                    }
                } catch {}
            })
        }
    }

    /// Watch Later counts once it has something in it; made playlists always.
    private static func countOwn(_ list: [UserPlaylist]) -> Int {
        list.filter { !$0.isWatchLater || !$0.videos.isEmpty }.count
    }

    public var isEmpty: Bool { continueWatching.isEmpty && queue.isEmpty && history.isEmpty && channelCount == 0 && playlistCount == 0 }

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
