import SwiftUI

/// How the Watch screen arranges itself, from the space it has (never from the device model).
/// A folded phone and a narrow split-screen slot are compact; an unfolded 4:3 phone or an iPad
/// in portrait get the band below the video; a wide window gets a side panel.
public enum WatchLayout: Equatable, Sendable {
    /// Video on top, everything else scrolls below.
    case compact
    /// Video on top, a tabbed band (details, comments, chapters) filling the rest.
    case band
    /// Video beside a tabbed side panel.
    case sidePanel

    public static func choose(width: CGFloat, height: CGFloat, horizontal: UserInterfaceSizeClass?) -> WatchLayout {
        guard horizontal == .regular, width >= 600 else { return .compact }
        // Side panel only when the video keeps most of the width at a useful height.
        return width / max(height, 1) >= 1.25 && width >= 900 ? .sidePanel : .band
    }
}
