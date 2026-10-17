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
    }

    /// Routes inside Settings.
    enum SettingsRoute: Hashable {
        case instances
    }

    var section = Section.feed
    var settingsPath: [SettingsRoute] = []
    var feedPath: [Route] = []
    var libraryPath: [Route] = []
    var searchPath: [Route] = []
    var watchPath: [Route] = []
    var watching: WatchContent?

    /// The feed's empty-state actions (add an instance, import subscriptions) live on the
    /// instances screen, so go straight there.
    func openInstances() {
        section = .settings
        settingsPath = [.instances]
    }

    func openChannel(_ id: ChannelID, name: String) {
        if watching != nil {
            watchPath.append(.channel(id, name: name))
        } else if section == .search {
            searchPath.append(.channel(id, name: name))
        } else if section == .library {
            libraryPath.append(.channel(id, name: name))
        } else {
            section = .feed
            feedPath.append(.channel(id, name: name))
        }
    }
}
