import SwiftUI

/// Reduce Motion (Settings → Accessibility → Motion): movement and scaling become fades, and
/// zooms become the platform's plain transition. Opacity changes stay, as Apple's guidance allows.
public extension AnyTransition {
    static func motion(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }
}

public extension View {
    /// A zoom into a destination from `sourceID`, unless Reduce Motion is on.
    @ViewBuilder
    func zoomTransition(sourceID: some Hashable, in namespace: Namespace.ID, reduceMotion: Bool) -> some View {
        #if os(iOS)
        if reduceMotion {
            self
        } else {
            navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        }
        #else
        self
        #endif
    }
}
