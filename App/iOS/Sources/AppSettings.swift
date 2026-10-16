import SwiftUI
import Library

/// Simple preferences (UserDefaults; CLAUDE.md keeps GRDB for user data only).
@MainActor
@Observable
final class AppSettings {
    /// One per app: every scene and the environment read the same preferences.
    static let shared = AppSettings()

    var hideShorts: Bool {
        didSet { defaults.set(hideShorts, forKey: Keys.hideShorts) }
    }
    /// YouTube's own "Up next" suggestions on the Watch screen.
    var showsRelated: Bool {
        didSet { defaults.set(showsRelated, forKey: Keys.showsRelated) }
    }

    /// SponsorBlock auto-skip (hash-prefix lookups, private by design). On by default.
    var skipsSponsors: Bool {
        didSet { defaults.set(skipsSponsors, forKey: Keys.skipsSponsors) }
    }
    /// DeArrow community titles (hash-prefix lookups). Off by default.
    var brandedTitles: Bool {
        didSet { defaults.set(brandedTitles, forKey: Keys.brandedTitles) }
    }
    /// DeArrow thumbnails: its thumbnail service is asked for the specific video. Off by default.
    var brandedThumbnails: Bool {
        didSet { defaults.set(brandedThumbnails, forKey: Keys.brandedThumbnails) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hideShorts = defaults.object(forKey: Keys.hideShorts) as? Bool ?? true
        showsRelated = defaults.object(forKey: Keys.showsRelated) as? Bool ?? true
        skipsSponsors = defaults.object(forKey: Keys.skipsSponsors) as? Bool ?? true
        brandedTitles = defaults.object(forKey: Keys.brandedTitles) as? Bool ?? false
        brandedThumbnails = defaults.object(forKey: Keys.brandedThumbnails) as? Bool ?? false
    }

    var feedOptions: FeedStore.Options {
        .init(hideShorts: hideShorts, brandedTitles: brandedTitles, brandedThumbnails: brandedThumbnails)
    }

    private enum Keys {
        static let hideShorts = "feed.hideShorts"
        static let showsRelated = "watch.showsRelated"
        static let skipsSponsors = "sponsorBlock.enabled"
        static let brandedTitles = "deArrow.titles"
        static let brandedThumbnails = "deArrow.thumbnails"
    }
}
