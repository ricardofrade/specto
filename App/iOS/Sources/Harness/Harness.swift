import SwiftUI
import DesignSystem

/// Screens for UI tests and manual checks, selected with `-Harness <screen>`.
/// Unreachable in normal use.
struct Harness: View {
    enum Screen: String {
        case scroll
        case frameRate
        case glass

        init?(arguments: [String]) {
            guard let index = arguments.firstIndex(of: "-Harness"),
                  arguments.indices.contains(index + 1) else { return nil }
            self.init(rawValue: arguments[index + 1])
        }
    }

    let screen: Screen

    var body: some View {
        switch screen {
        case .scroll: ScrollBenchmark()
        case .frameRate: FrameRateCheck()
        case .glass: PlayerControlClusterShowcase()
        }
    }
}
