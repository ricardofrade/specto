import SwiftUI
import Core
import Library
import Playback

/// What SponsorBlock does with a category of segment.
enum SponsorAction: String, CaseIterable, Sendable {
    /// Skip it automatically, with a brief notice.
    case skip
    /// Offer a Skip button while it plays.
    case ask
    /// Mark it on the timeline, in its colour, and play it.
    case show
    /// Play it.
    case off

    var title: LocalizedStringKey {
        switch self {
        case .skip: "Skip"
        case .ask: "Show a Skip button"
        case .show: "Only show on the timeline"
        case .off: "Don't skip"
        }
    }
}

/// Simple preferences (UserDefaults; CLAUDE.md keeps GRDB for user data only).
@MainActor
@Observable
final class AppSettings {
    /// One per app: every scene and the environment read the same preferences.
    static let shared = AppSettings()

    var hideShorts: Bool {
        didSet { defaults.set(hideShorts, forKey: Keys.hideShorts) }
    }

    /// Live streams off Home and the trending lists (a channel's page still has them).
    var hideLive: Bool {
        didSet { defaults.set(hideLive, forKey: Keys.hideLive) }
    }
    /// Finished videos leave Home (they stay in Library → History). Off by default.
    var hideWatched: Bool {
        didSet { defaults.set(hideWatched, forKey: Keys.hideWatched) }
    }
    /// YouTube's own "Up next" suggestions on the Watch screen.
    var showsRelated: Bool {
        didSet { defaults.set(showsRelated, forKey: Keys.showsRelated) }
    }

    /// SponsorBlock auto-skip (hash-prefix lookups, private by design). On by default.
    var skipsSponsors: Bool {
        didSet { defaults.set(skipsSponsors, forKey: Keys.skipsSponsors) }
    }
    /// Per category; categories not stored take `SponsorAction.defaults`.
    var sponsorActions: [SkipSegment.Category: SponsorAction] {
        didSet {
            defaults.set(Dictionary(uniqueKeysWithValues: sponsorActions.map { ($0.key.rawValue, $0.value.rawValue) }),
                         forKey: Keys.sponsorActions)
        }
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

    /// Local notifications for new uploads (iPhone and iPad). Off until the person turns it on.
    var notifiesNewUploads: Bool {
        didSet { defaults.set(notifiesNewUploads, forKey: Keys.notifiesNewUploads) }
    }
    /// Uploads after this are "new": the last time the feed was seen or notified about.
    var newUploadsSince: Date? {
        didSet { defaults.set(newUploadsSince, forKey: Keys.newUploadsSince) }
    }

    /// Data saver (ADR 0007): the tallest video on Wi-Fi, and on cellular or a hotspot; nil for
    /// no limit beyond the screen. Low Data Mode caps at 480p on top of these.
    var wifiQualityLimit: Int? {
        didSet { defaults.set(wifiQualityLimit ?? 0, forKey: Keys.wifiQualityLimit) }
    }
    var cellularQualityLimit: Int? {
        didSet { defaults.set(cellularQualityLimit ?? 0, forKey: Keys.cellularQualityLimit) }
    }

    /// The audio track to prefer on multi-language videos ("es"); nil plays the original.
    /// Remembered across videos; a video without that language plays its original.
    var audioLanguage: String? {
        didSet { defaults.set(audioLanguage, forKey: Keys.audioLanguage) }
    }

    /// When a video ends with nothing queued, play the first suggestion after a countdown. On.
    var autoplay: Bool {
        didSet { defaults.set(autoplay, forKey: Keys.autoplay) }
    }

    /// The featured video plays muted behind its title on Home (Wi-Fi only). On by default.
    var homePreviews: Bool {
        didSet { defaults.set(homePreviews, forKey: Keys.homePreviews) }
    }

    /// The format to play when the person hasn't picked one for a video (ADR 0017). Auto.
    /// The YouTube instance to ask first ("Prefer"); nil lets the fastest go first.
    var preferredInstance: UUID? {
        didSet { defaults.set(preferredInstance?.uuidString, forKey: Keys.preferredInstance) }
    }

    /// Search's last network, with YouTube and PeerTube both set up.
    var searchNetwork: ContentNetwork {
        didSet { defaults.set(searchNetwork.rawValue, forKey: Keys.searchNetwork) }
    }

    /// The country for trending lists (ISO code); nil follows the device's region.
    var trendingRegion: String? {
        didSet { defaults.set(trendingRegion, forKey: Keys.trendingRegion) }
    }

    var preferredFormat: StreamFormat {
        didSet { defaults.set(preferredFormat.rawValue, forKey: Keys.preferredFormat) }
    }

    /// Search suggestions while typing (from the instances). On by default.
    var searchSuggestions: Bool {
        didSet { defaults.set(searchSuggestions, forKey: Keys.searchSuggestions) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hideShorts = Self.flag(defaults, Keys.hideShorts, default: true)
        hideLive = Self.flag(defaults, Keys.hideLive, default: false)
        hideWatched = defaults.bool(forKey: Keys.hideWatched)
        showsRelated = Self.flag(defaults, Keys.showsRelated, default: true)
        skipsSponsors = Self.flag(defaults, Keys.skipsSponsors, default: true)
        sponsorActions = Self.sponsorActions(defaults.dictionary(forKey: Keys.sponsorActions) as? [String: String] ?? [:])
        brandedTitles = Self.flag(defaults, Keys.brandedTitles, default: false)
        brandedThumbnails = Self.flag(defaults, Keys.brandedThumbnails, default: false)
        downloadsQueue = Self.flag(defaults, Keys.downloadsQueue, default: true)
        offlineLimitBytes = defaults.object(forKey: Keys.offlineLimit) as? Int64 ?? 2_000_000_000
        captionLanguage = defaults.string(forKey: Keys.captionLanguage)
        notifiesNewUploads = defaults.bool(forKey: Keys.notifiesNewUploads)
        newUploadsSince = defaults.object(forKey: Keys.newUploadsSince) as? Date
        audioLanguage = defaults.string(forKey: Keys.audioLanguage).flatMap { $0.isEmpty ? nil : $0 }
        autoplay = Self.flag(defaults, Keys.autoplay, default: true)
        searchSuggestions = Self.flag(defaults, Keys.searchSuggestions, default: true)
        homePreviews = Self.flag(defaults, Keys.homePreviews, default: true)
        preferredFormat = defaults.string(forKey: Keys.preferredFormat).flatMap(StreamFormat.init) ?? .auto
        trendingRegion = defaults.string(forKey: Keys.trendingRegion)
        preferredInstance = defaults.string(forKey: Keys.preferredInstance).flatMap(UUID.init)
        searchNetwork = defaults.string(forKey: Keys.searchNetwork).flatMap(ContentNetwork.init) ?? .youTube
        wifiQualityLimit = Self.limit(defaults.integer(forKey: Keys.wifiQualityLimit))
        cellularQualityLimit = Self.limit(defaults.integer(forKey: Keys.cellularQualityLimit))
    }

    /// The limit for the network playback is on now.
    func qualityLimit(onExpensiveNetwork: Bool) -> Int? {
        onExpensiveNetwork ? cellularQualityLimit : wifiQualityLimit
    }

    private static func limit(_ stored: Int) -> Int? { stored > 0 ? stored : nil }

    /// Sponsors, self-promotion and "subscribe" reminders skip; the rest play until chosen.
    private static func sponsorActions(_ stored: [String: String]) -> [SkipSegment.Category: SponsorAction] {
        let automatic: Set<SkipSegment.Category> = [.sponsor, .selfpromo, .interaction]
        return Dictionary(uniqueKeysWithValues: SkipSegment.Category.allCases.map { category in
            (category, stored[category.rawValue].flatMap(SponsorAction.init) ?? (automatic.contains(category) ? .skip : .off))
        })
    }

    /// `bool(forKey:)` also reads "YES"/"NO" from launch arguments (`-feed.hideShorts NO`),
    /// which arrive as strings; a missing key takes the default.
    private static func flag(_ defaults: UserDefaults, _ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? value : defaults.bool(forKey: key)
    }

    var feedOptions: FeedStore.Options {
        .init(hideShorts: hideShorts, hideWatched: hideWatched, hideLive: hideLive, brandedTitles: brandedTitles,
              brandedThumbnails: brandedThumbnails)
    }

    private enum Keys {
        static let hideShorts = "feed.hideShorts"
        static let hideLive = "feed.hideLive"
        static let hideWatched = "feed.hideWatched"
        static let captionLanguage = "playback.captionLanguage"
        static let notifiesNewUploads = "notifications.newUploads"
        static let newUploadsSince = "notifications.newUploadsSince"
        static let showsRelated = "watch.showsRelated"
        static let wifiQualityLimit = "playback.wifiQualityLimit"
        static let searchSuggestions = "search.suggestions"
        static let homePreviews = "home.previews"
        static let preferredFormat = "playback.format"
        static let trendingRegion = "explore.region"
        static let preferredInstance = "instances.preferred"
        static let searchNetwork = "search.network"
        static let autoplay = "playback.autoplay"
        static let audioLanguage = "playback.audioLanguage"
        static let cellularQualityLimit = "playback.cellularQualityLimit"
        static let skipsSponsors = "sponsorBlock.enabled"
        static let sponsorActions = "sponsorBlock.actions"
        static let brandedTitles = "deArrow.titles"
        static let brandedThumbnails = "deArrow.thumbnails"
        static let downloadsQueue = "offline.downloadsQueue"
        static let offlineLimit = "offline.limitBytes"
    }
}
