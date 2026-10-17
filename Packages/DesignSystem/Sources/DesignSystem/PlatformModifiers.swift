import SwiftUI

/// Modifiers that exist on iOS but not tvOS, applied where the platform has them.
extension View {
    /// An inline navigation title on iOS. tvOS has no title display modes.
    public func inlineNavigationTitle() -> some View {
        #if os(tvOS)
        self
        #else
        navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// Selectable text on iOS. tvOS has no text selection.
    public func selectableText() -> some View {
        #if os(tvOS)
        self
        #else
        textSelection(.enabled)
        #endif
    }
}
