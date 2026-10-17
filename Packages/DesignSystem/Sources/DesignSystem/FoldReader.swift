import SwiftUI

/// What a view needs to know about an iPhone Duo's fold (`ReservedRegion.Kind.division`,
/// iOS 27.1). Elsewhere, and before 27.1, there is no fold.
public struct FoldState: Equatable, Sendable {
    /// The device can fold here, folded or not: grids prefer an even number of columns.
    public var isPresent = false
    /// The fold's frame while partly folded; nil when flat or closed.
    public var active: CGRect?

    public init(isPresent: Bool = false, active: CGRect? = nil) {
        self.isPresent = isPresent
        self.active = active
    }
}

extension View {
    /// Reports this view's fold state as the device opens, folds and closes.
    public func onFoldChange(_ action: @escaping (FoldState) -> Void) -> some View {
        modifier(FoldReader(action: action))
    }
}

private struct FoldReader: ViewModifier {
    let action: (FoldState) -> Void

    func body(content: Content) -> some View {
        // The fold APIs are in the iOS 27 SDK (Xcode 27, Swift 6.4); older Xcodes (CI's hosted
        // runners) build without them, as if there were no fold.
        #if os(iOS) && compiler(>=6.4)
        if #available(iOS 27.1, *) {
            content.onGeometryChange(for: FoldState.self) { proxy in
                let regions = proxy.reservedRegions(kind: .division, options: .includeInactive)
                return FoldState(isPresent: !regions.isEmpty, active: regions.first(where: \.isActive)?.frame)
            } action: { action($0) }
        } else {
            content
        }
        #else
        content     // No fold on Apple TV.
        #endif
    }
}
