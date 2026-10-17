import TVServices

/// Top Shelf: "Continue Watching" and "Latest" from the snapshot the app keeps current.
/// Selecting an item opens the app on that video; Play starts it straight away.
final class ContentProvider: TVTopShelfContentProvider {
    // The completion form: TVTopShelfContent isn't Sendable, so the async override can't return it.
    override func loadTopShelfContent(completionHandler: @escaping ((any TVTopShelfContent)?) -> Void) {
        guard let url = TopShelfSnapshot.fileURL, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(TopShelfSnapshot.self, from: data) else {
            completionHandler(nil)
            return
        }
        let sections = [
            Self.section(String(localized: "Continue Watching"), snapshot.continueWatching),
            Self.section(String(localized: "Latest"), snapshot.latest),
        ].compactMap { $0 }
        completionHandler(sections.isEmpty ? nil : TVTopShelfSectionedContent(sections: sections))
    }

    private static func section(_ title: String, _ items: [TopShelfSnapshot.Item]) -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? {
        guard !items.isEmpty else { return nil }
        let collection = TVTopShelfItemCollection(items: items.map(item))
        collection.title = title
        return collection
    }

    private static func item(_ source: TopShelfSnapshot.Item) -> TVTopShelfSectionedItem {
        let item = TVTopShelfSectionedItem(identifier: source.id)
        item.title = source.title
        item.imageShape = .hdtv
        if let image = source.imageURL {
            item.setImageURL(image, for: .screenScale1x)
            item.setImageURL(image, for: .screenScale2x)
        }
        if let progress = source.progress { item.playbackProgress = progress }
        if let url = TopShelfSnapshot.playURL(for: source.id) {
            item.displayAction = TVTopShelfAction(url: url)
            item.playAction = TVTopShelfAction(url: url)
        }
        return item
    }
}
