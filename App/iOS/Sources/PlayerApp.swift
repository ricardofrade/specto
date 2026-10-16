import SwiftUI
import Core
import FeedFeature

@main
struct PlayerApp: App {
    private let launchInterval = Signpost.begin(.launchFirstFeedFrame)
    private let harness = Harness.Screen(arguments: ProcessInfo.processInfo.arguments)

    var body: some Scene {
        WindowGroup {
            if let harness {
                Harness(screen: harness)
            } else {
                FeedScreen()
                    .onFirstFrame { Signpost.end(launchInterval) }
            }
        }
    }
}

private extension View {
    /// Runs `action` once, after the frame containing this view has been committed.
    func onFirstFrame(_ action: @escaping @MainActor () -> Void) -> some View {
        modifier(FirstFrame(action: action))
    }
}

private struct FirstFrame: ViewModifier {
    let action: @MainActor () -> Void
    @State private var fired = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard !fired else { return }
            fired = true
            // onAppear runs before the commit; the next main-queue turn is after it.
            DispatchQueue.main.async { action() }
        }
    }
}
