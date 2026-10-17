import SwiftUI

/// What a view needs to know about an iPhone Duo's fold (`ReservedRegion.Kind.division`,
/// iOS 27.1). Elsewhere, and before 27.1, there is no fold.
public struct FoldState: Equatable, Sendable {
    /// The device can fold here, folded or not: grids prefer an even number of columns.
    public var isPresent = false
    /// The fold's frame while partly folded; nil when flat or closed.
    public var active: CGRect?
    /// Where the crease runs on this view, folded or flat; nil without one (closed, or no fold).
    public var crease: CGRect?

    /// Set by UI tests' simulated fold: layouts use their own split, not `ArrangementView`.
    public var isSimulated = false

    public init(isPresent: Bool = false, active: CGRect? = nil, crease: CGRect? = nil, isSimulated: Bool = false) {
        self.isPresent = isPresent
        self.active = active
        self.crease = crease
        self.isSimulated = isSimulated
    }

    /// The crease runs top to bottom (the halves sit side by side).
    public var isVerticalCrease: Bool {
        guard let crease else { return false }
        return crease.height > crease.width
    }
}

extension View {
    /// Reports this view's fold state as the device opens, folds and closes.
    public func onFoldChange(_ action: @escaping (FoldState) -> Void) -> some View {
        modifier(FoldReader(action: action))
    }
}

/// UI tests only: `-SimulateFold flat|bent` with `-FoldAxis vertical|horizontal` puts a crease
/// through the middle of the view, so fold layouts can be checked on a simulator that can't
/// change pose from the command line. Never set outside tests.
enum SimulatedFold {
    enum Pose: String { case flat, bent }
    static let pose: Pose? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-SimulateFold"), arguments.indices.contains(index + 1) else { return nil }
        return Pose(rawValue: arguments[index + 1])
    }()
    static let vertical: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-FoldAxis"), arguments.indices.contains(index + 1) else { return true }
        return arguments[index + 1] != "horizontal"
    }()

    static func state(in frame: CGRect, pose: Pose) -> FoldState {
        let crease = vertical
            ? CGRect(x: frame.midX - 1, y: frame.minY, width: 2, height: frame.height)
            : CGRect(x: frame.minX, y: frame.midY - 1, width: frame.width, height: 2)
        return FoldState(isPresent: true, active: pose == .bent ? crease : nil, crease: crease, isSimulated: true)
    }
}

private struct FoldReader: ViewModifier {
    let action: (FoldState) -> Void

    func body(content: Content) -> some View {
        if let pose = SimulatedFold.pose {
            content.onGeometryChange(for: FoldState.self) { proxy in
                SimulatedFold.state(in: proxy.frame(in: .local), pose: pose)
            } action: { action($0) }
        } else {
            system(content)
        }
    }

    @ViewBuilder
    private func system(_ content: Content) -> some View {
        // The fold APIs are in the iOS 27 SDK (Xcode 27, Swift 6.4); older Xcodes (CI's hosted
        // runners) build without them, as if there were no fold.
        #if os(iOS) && compiler(>=6.4)
        if #available(iOS 27.1, *) {
            content.onGeometryChange(for: FoldState.self) { proxy in
                let regions = proxy.reservedRegions(kind: .division, options: .includeInactive)
                return FoldState(isPresent: !regions.isEmpty, active: regions.first(where: \.isActive)?.frame,
                                 crease: regions.first?.frame)
            } action: { action($0) }
        } else {
            content
        }
        #else
        content     // No fold on Apple TV.
        #endif
    }
}
