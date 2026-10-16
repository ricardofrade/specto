import SwiftUI
import Core
import WatchFeature

/// Navigation for one scene (window). Each iPad window gets its own router, so two windows can
/// browse independently while sharing the app's single `PlaybackSession`.
@MainActor
@Observable
final class SceneRouter {
    enum Section: Hashable {
        case feed
        case search
        case settings
        case channel(ChannelID)
    }

    /// Typed routes, pushed onto whichever stack is visible.
    enum Route: Hashable {
        case channel(ChannelID, name: String)
    }

    var section = Section.feed
    var feedPath: [Route] = []
    var searchPath: [Route] = []
    var watchPath: [Route] = []
    var watching: WatchContent?

    func openChannel(_ id: ChannelID, name: String) {
        if watching != nil {
            watchPath.append(.channel(id, name: name))
        } else if section == .search {
            searchPath.append(.channel(id, name: name))
        } else {
            section = .feed
            feedPath.append(.channel(id, name: name))
        }
    }
}
