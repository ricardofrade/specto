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
        case explore
        case library
        case search
        case channel(ChannelID)
    }

    /// Typed routes, pushed onto whichever stack is visible.
    enum Route: Hashable {
        case channel(ChannelID, name: String)
        /// Every subscription (Library → Channels).
        case channels
        case playlist(PlaylistSummary)
        /// Library → Playlists: the person's own, then saved ones.
        case savedPlaylists
        /// Watch Later or one of the person's playlists, by ID.
        case userPlaylist(String)
    }

    /// Routes inside Settings.
    enum SettingsRoute: Hashable {
        case instances
    }

    var section = Section.feed {
        didSet { if section != oldValue { channelPath = [] } }
    }
    /// Settings is a sheet, opened from the gear at the top of Home, Explore and Library (as in
    /// Apple's own apps), so the tab bar holds places to browse.
    var showsSettings = false
    var settingsPath: [SettingsRoute] = []
    var feedPath: [Route] = []
    var explorePath: [Route] = []
    var libraryPath: [Route] = []
    var searchPath: [Route] = []
    var watchPath: [Route] = []
    /// The open channel tab's stack (iPad sidebar); one tab shows at a time.
    var channelPath: [Route] = []
    var watching: WatchContent?
    /// An open iPhone Duo docks the player beside the tabs: channels open in the browsing half.
    var splitWatching = false
    /// "Save to Playlist" for this video (presented over whatever is on top).
    var savingToPlaylist: VideoSummary?
    /// The vertical Shorts player, over everything.
    var shorts: ShortsContent?

    /// The feed's empty-state actions (add an instance, import subscriptions) live on the
    /// instances screen, so go straight there.
    /// The gear: Settings from its first screen.
    func openSettings() {
        settingsPath = []
        showsSettings = true
    }

    func openInstances() {
        settingsPath = [.instances]
        showsSettings = true
    }

    /// The Shorts player. From inside the Watch screen (its channel page), the player closes
    /// first: one full-screen cover can't present over another.
    func openShorts(_ videos: [VideoSummary], start: Int) {
        let content = ShortsContent(videos: videos, start: start)
        guard watching != nil else {
            shorts = content
            return
        }
        watching = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))   // The cover's dismissal animation.
            shorts = content
        }
    }

    func openChannel(_ id: ChannelID, name: String) {
        push(.channel(id, name: name))
    }

    /// Onto whichever stack is showing: the player's, Search's, Library's, else Home's.
    func push(_ route: Route) {
        if watching != nil, !splitWatching {
            watchPath.append(route)
        } else if section == .search {
            searchPath.append(route)
        } else if section == .library {
            libraryPath.append(route)
        } else if section == .explore {
            explorePath.append(route)
        } else if case .channel = section {
            channelPath.append(route)
        } else {
            section = .feed
            feedPath.append(route)
        }
    }
}
