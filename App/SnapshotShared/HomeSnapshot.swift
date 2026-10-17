import Foundation

/// What Top Shelf (Apple TV) and the widgets (iPhone, iPad) show, written by the app into the App
/// Group and read by the extensions. A small JSON file rather than the database: GRDB across two
/// processes needs coordinated locking, and the extensions only need a few dozen items.
nonisolated struct HomeSnapshot: Codable, Sendable, Equatable {
    struct Item: Codable, Sendable, Equatable {
        let id: String
        let title: String
        let imageURL: URL?
        /// Watched fraction (0…1), shown as a progress bar.
        let progress: Double?
        /// A small copy of the thumbnail in the App Group (widgets can't wait on the network).
        var imageFile: String? = nil
        var channelName: String? = nil
    }

    var continueWatching: [Item]
    var latest: [Item]

    /// From each target's Info.plist, set in App/Signing.xcconfig: it follows the bundle IDs of
    /// whoever signs the build (docs/distribution.md).
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "SpectoAppGroup") as? String
        ?? "group.dev.placeholder.specto"
    /// Matches CFBundleURLSchemes in each app's project.yml.
    #if os(tvOS)
    static let urlScheme = "dev.placeholder.specto.tv"
    #else
    static let urlScheme = "dev.placeholder.specto"
    #endif
    static let maxItems = 12

    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: "Library/Caches/Home", directoryHint: .isDirectory)
    }

    static var fileURL: URL? { directory?.appending(path: "home.json") }

    static func read() -> HomeSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HomeSnapshot.self, from: data)
    }

    /// `<scheme>://watch?v=<id>`
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
