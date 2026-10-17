import Foundation
import TVServices
import Library

/// Keeps Top Shelf current: called after feed changes and when the app goes to the background.
enum TopShelfPublisher {
    static func publish(_ database: AppDatabase) {
        Task.detached(priority: .utility) {
            guard let url = TopShelfSnapshot.fileURL else { return }
            func items(_ rows: [FeedRow]) -> [TopShelfSnapshot.Item] {
                rows.prefix(TopShelfSnapshot.maxItems).map {
                    TopShelfSnapshot.Item(id: $0.id.rawValue, title: $0.title,
                                          imageURL: $0.thumbnails.best(forPixelWidth: 800)?.url, progress: $0.progress)
                }
            }
            let snapshot = TopShelfSnapshot(
                continueWatching: items((try? WatchStateStore(database).inProgress()) ?? []),
                latest: items((try? FeedStore(database).rows()) ?? []))
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            if let existing = try? Data(contentsOf: url), existing == data { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
            await MainActor.run { TVTopShelfContentProvider.topShelfContentDidChange() }
        }
    }
}
