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
        case library
        case search
        case settings
        case channel(ChannelID)
    }

    /// Typed routes, pushed onto whichever stack is visible.
    enum Route: Hashable {
        case channel(ChannelID, name: String)
        /// Every subscription (Library → Channels).
        case channels
        case playlist(PlaylistSummary)
        /// Saved playlists (Library → Playlists).
        case savedPlaylists
    }

    /// Routes inside Settings.
    enum SettingsRoute: Hashable {
        case instances
    }

    var section = Section.feed {
        didSet { if section != oldValue { channelPath = [] } }
    }
    var settingsPath: [SettingsRoute] = []
    var feedPath: [Route] = []
    var libraryPath: [Route] = []
    var searchPath: [Route] = []
    var watchPath: [Route] = []
    /// The open channel tab's stack (iPad sidebar); one tab shows at a time.
    var channelPath: [Route] = []
    var watching: WatchContent?

    /// The feed's empty-state actions (add an instance, import subscriptions) live on the
    /// instances screen, so go straight there.
    func openInstances() {
        section = .settings
        settingsPath = [.instances]
    }

    func openChannel(_ id: ChannelID, name: String) {
        push(.channel(id, name: name))
    }

    /// Onto whichever stack is showing: the player's, Search's, Library's, else Home's.
    func push(_ route: Route) {
        if watching != nil {
            watchPath.append(route)
        } else if section == .search {
            searchPath.append(route)
        } else if section == .library {
            libraryPath.append(route)
        } else if case .channel = section {
            channelPath.append(route)
        } else {
            section = .feed
            feedPath.append(route)
        }
    }
}
