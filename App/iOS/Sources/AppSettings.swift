import SwiftUI

/// Simple preferences (UserDefaults; CLAUDE.md keeps GRDB for user data only).
@MainActor
@Observable
final class AppSettings {
    var hideShorts: Bool {
        didSet { defaults.set(hideShorts, forKey: Keys.hideShorts) }
    }
    /// YouTube's own "Up next" suggestions on the Watch screen.
    var showsRelated: Bool {
        didSet { defaults.set(showsRelated, forKey: Keys.showsRelated) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hideShorts = defaults.object(forKey: Keys.hideShorts) as? Bool ?? true
        showsRelated = defaults.object(forKey: Keys.showsRelated) as? Bool ?? true
    }

    private enum Keys {
        static let hideShorts = "feed.hideShorts"
        static let showsRelated = "watch.showsRelated"
    }
}
