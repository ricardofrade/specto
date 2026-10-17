import Foundation

/// What Top Shelf shows, written by the app into the App Group and read by the extension.
/// A small JSON file rather than the database: GRDB across two processes needs coordinated
/// locking, and the extension only ever needs a few dozen items.
nonisolated struct TopShelfSnapshot: Codable, Sendable, Equatable {
    struct Item: Codable, Sendable, Equatable {
        let id: String
        let title: String
        let imageURL: URL?
        /// Watched fraction (0…1), shown as Top Shelf's progress bar.
        let progress: Double?
    }

    var continueWatching: [Item]
    var latest: [Item]

    /// Placeholder until the owner's real team ID and bundle ID (docs/distribution.md).
    static let appGroup = "group.dev.placeholder.player"
    /// Matches CFBundleURLSchemes in project.yml.
    static let urlScheme = "dev.placeholder.player.tv"
    static let maxItems = 12

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "Library/Caches/topshelf.json")
    }

    /// `dev.placeholder.player.tv://watch?v=<id>`
    static func playURL(for id: String) -> URL? {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "watch"
        components.queryItems = [URLQueryItem(name: "v", value: id)]
        return components.url
    }

    /// The video ID in a URL from `playURL(for:)`, else nil.
    static func videoID(in url: URL) -> String? {
        guard url.scheme == urlScheme, url.host() == "watch",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value, !id.isEmpty else { return nil }
        return id
    }
}
