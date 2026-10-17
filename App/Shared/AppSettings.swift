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

    /// Download queued videos' audio for offline listening (builds with OFFLINE_DOWNLOADS only).
    var downloadsQueue: Bool {
        didSet { defaults.set(downloadsQueue, forKey: Keys.downloadsQueue) }
    }
    /// Storage limit for offline audio.
    var offlineLimitBytes: Int64 {
        didSet { defaults.set(offlineLimitBytes, forKey: Keys.offlineLimit) }
    }

    /// Subtitle language code ("en"), "off", or nil to follow the system's Closed Captions setting.
    var captionLanguage: String? {
        didSet { defaults.set(captionLanguage, forKey: Keys.captionLanguage) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hideShorts = defaults.object(forKey: Keys.hideShorts) as? Bool ?? true
        showsRelated = defaults.object(forKey: Keys.showsRelated) as? Bool ?? true
        skipsSponsors = defaults.object(forKey: Keys.skipsSponsors) as? Bool ?? true
        brandedTitles = defaults.object(forKey: Keys.brandedTitles) as? Bool ?? false
        brandedThumbnails = defaults.object(forKey: Keys.brandedThumbnails) as? Bool ?? false
        downloadsQueue = defaults.object(forKey: Keys.downloadsQueue) as? Bool ?? true
        offlineLimitBytes = defaults.object(forKey: Keys.offlineLimit) as? Int64 ?? 2_000_000_000
        captionLanguage = defaults.string(forKey: Keys.captionLanguage)
    }

    var feedOptions: FeedStore.Options {
        .init(hideShorts: hideShorts, brandedTitles: brandedTitles, brandedThumbnails: brandedThumbnails)
    }

    private enum Keys {
        static let hideShorts = "feed.hideShorts"
        static let captionLanguage = "playback.captionLanguage"
        static let showsRelated = "watch.showsRelated"
        static let skipsSponsors = "sponsorBlock.enabled"
        static let brandedTitles = "deArrow.titles"
        static let brandedThumbnails = "deArrow.thumbnails"
        static let downloadsQueue = "offline.downloadsQueue"
        static let offlineLimit = "offline.limitBytes"
    }
}
