import SwiftUI
import Core

@main
struct SpectoTVApp: App {
    private let launchInterval = Signpost.begin(.launchFirstFeedFrame)
    @State private var environment = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            TVRootView(environment: environment) {
                DispatchQueue.main.async { [launchInterval] in Signpost.end(launchInterval) }
            }
        }
    }
}

/// Sizes for a 1920-point-wide TV screen, from Apple's tvOS layout guidance.
enum TVMetrics {
    /// Four cards across inside the 80-point side margins.
    static let cardWidth: CGFloat = 410
    static let gridSpacing: CGFloat = 40
    static let rowSpacing: CGFloat = 60
    static let sectionSpacing: CGFloat = 70
}
