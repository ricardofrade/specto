import Foundation
import Library
import DesignSystem
#if os(tvOS)
import TVServices
#else
import UIKit
import WidgetKit
#endif

/// Keeps Top Shelf (Apple TV) and the widgets (iPhone, iPad) current. Called after the feed
/// refreshes and when the app goes to the background; writes only when something changed.
nonisolated enum HomeSnapshotPublisher {
    static func publish(_ database: AppDatabase) {
        Task.detached(priority: .utility) {
            guard let directory = HomeSnapshot.directory, let url = HomeSnapshot.fileURL else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let continueRows = Array(((try? WatchStateStore(database).inProgress()) ?? []).prefix(HomeSnapshot.maxItems))
            let latestRows = Array(((try? FeedStore(database).rows()) ?? []).prefix(HomeSnapshot.maxItems))
            var snapshot = HomeSnapshot(continueWatching: continueRows.map(item), latest: latestRows.map(item))
            #if os(iOS)
            // Widgets draw from small local copies of the first few thumbnails.
            snapshot.continueWatching = await withImages(snapshot.continueWatching, prefix: 4, in: directory)
            snapshot.latest = await withImages(snapshot.latest, prefix: 4, in: directory)
            removeUnused(in: directory, keeping: Set((snapshot.continueWatching + snapshot.latest).compactMap(\.imageFile)))
            #endif
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            if let existing = try? Data(contentsOf: url), existing == data { return }
            try? data.write(to: url, options: .atomic)
            #if os(tvOS)
            await MainActor.run { TVTopShelfContentProvider.topShelfContentDidChange() }
            #else
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }

    private static func item(_ row: FeedRow) -> HomeSnapshot.Item {
        HomeSnapshot.Item(id: row.id.rawValue, title: row.title,
                          imageURL: row.thumbnails.best(forPixelWidth: 800)?.url, progress: row.progress,
                          channelName: row.channelName)
    }

    #if os(iOS)
    private static let thumbnailSize = CGSize(width: 480, height: 270)

    private static func withImages(_ items: [HomeSnapshot.Item], prefix: Int,
                                   in directory: URL) async -> [HomeSnapshot.Item] {
        var result = items
        for index in result.indices.prefix(prefix) {
            guard let url = result[index].imageURL else { continue }
            let name = "\(result[index].id).jpg"
            let file = directory.appending(path: name)
            if !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                guard let image = await ImagePipeline.shared.image(url, pixelSize: thumbnailSize),
                      let jpeg = image.jpegData(compressionQuality: 0.8) else { continue }
                try? jpeg.write(to: file, options: .atomic)
            }
            result[index].imageFile = name
        }
        return result
    }

    private static func removeUnused(in directory: URL, keeping names: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        for file in files where file.hasSuffix(".jpg") && !names.contains(file) {
            try? FileManager.default.removeItem(at: directory.appending(path: file))
        }
    }
    #endif
}
