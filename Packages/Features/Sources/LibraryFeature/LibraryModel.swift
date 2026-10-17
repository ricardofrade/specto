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

    @ObservationIgnored private let watchState: WatchStateStore
    @ObservationIgnored private let queueStore: QueueStore
    @ObservationIgnored private var observations: [Task<Void, Never>] = []

    public init(watchState: WatchStateStore, queue: QueueStore) {
        self.watchState = watchState
        self.queueStore = queue
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
    }

    public var isEmpty: Bool { continueWatching.isEmpty && queue.isEmpty && history.isEmpty }

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
