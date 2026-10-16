import SwiftUI
import Testing
@testable import WatchFeature

struct WatchLayoutTests {
    @Test(arguments: [
        // Folded phone / narrow split-screen slot.
        (CGSize(width: 390, height: 844), UserInterfaceSizeClass.compact, WatchLayout.compact),
        (CGSize(width: 320, height: 1000), .compact, .compact),
        // Unfolded ~4:3 phone and iPad portrait: band below the video.
        (CGSize(width: 760, height: 980), .regular, .band),
        (CGSize(width: 1032, height: 1376), .regular, .band),
        // iPad landscape / wide window: side panel.
        (CGSize(width: 1376, height: 1032), .regular, .sidePanel),
        // Regular but too narrow for anything but compact (a slim Stage Manager window).
        (CGSize(width: 500, height: 700), .regular, .compact),
    ])
    func layoutFollowsAvailableSpace(_ size: CGSize, _ sizeClass: UserInterfaceSizeClass, _ expected: WatchLayout) {
        #expect(WatchLayout.choose(width: size.width, height: size.height, horizontal: sizeClass) == expected)
    }
}
