import SwiftUI

/// Design tokens. Colors are semantic and lean on system colors, so Liquid Glass,
/// dark mode, Increase Contrast and Reduce Transparency adapt without extra work.
public enum Tokens {
    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        /// Horizontal inset of screen content.
        public static let screenInset: CGFloat = 16
        /// Between a screen's sections (hero, shelves, grid).
        public static let section: CGFloat = 36
    }

    public enum Radius {
        public static let thumbnail: CGFloat = 12
        public static let card: CGFloat = 16
        public static let sheet: CGFloat = 24
    }

    public enum Colors {
        #if os(tvOS)
        // tvOS has no system background colours: the system draws the backdrop.
        public static let background = Color.clear
        public static let surface = Color.white.opacity(0.08)
        #else
        public static let background = Color(uiColor: .systemBackground)
        public static let surface = Color(uiColor: .secondarySystemBackground)
        #endif
        public static let textPrimary = Color.primary
        public static let textSecondary = Color.secondary
        public static let separator = Color(uiColor: .separator)
        public static let accent = Color.accentColor
        /// The icon's violet-to-coral, for the few brand moments (the welcome screen).
        public static let brand = LinearGradient(colors: [Color(.displayP3, red: 0.302, green: 0.137, blue: 0.784),
                                                          Color(.displayP3, red: 0.941, green: 0.337, blue: 0.478)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)
        /// Placeholder behind thumbnails while they load.
        #if os(tvOS)
        public static let thumbnailPlaceholder = Color.gray.opacity(0.2)
        #else
        public static let thumbnailPlaceholder = Color(uiColor: .tertiarySystemFill)
        #endif
        public static let liveBadge = Color.red
        /// PeerTube's orange, darkened so white caption text on it stays readable (4.5:1).
        public static let peerTube = Color(red: 0.76, green: 0.32, blue: 0.04)
        /// Progress bar of a partly watched video.
        public static let watchProgress = Color.red
    }

    /// Dynamic Type styles only; never fixed point sizes.
    public enum Typography {
        public static let screenTitle = Font.largeTitle.bold()
        /// Shelf and section headings ("Continue Watching").
        public static let sectionTitle = Font.title2.bold()
        /// The featured video's title over its artwork.
        public static let heroTitle = Font.title.bold()
        public static let cellTitle = Font.headline
        public static let cellMeta = Font.subheadline
        public static let body = Font.body
        public static let caption = Font.caption
        /// Durations and timestamps: digits don't jiggle while counting.
        public static let timecode = Font.caption.monospacedDigit().weight(.semibold)
    }

    public enum Motion {
        /// Player controls fade after this long without interaction.
        public static let controlsAutoHide: Duration = .seconds(3)
        public static let standard = Animation.smooth(duration: 0.3)
        public static let snappy = Animation.snappy(duration: 0.2)
    }
}
