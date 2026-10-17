import SwiftUI
import Core

@main
struct SpectoApp: App {
    private let launchInterval = Signpost.begin(.launchFirstFeedFrame)
    private let harness = Harness.Screen(arguments: ProcessInfo.processInfo.arguments)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment.shared

    var body: some Scene {
        WindowGroup {
            if let harness {
                Harness(screen: harness)
            } else {
                RootView(environment: environment) {
                    FirstFrame.once { Signpost.end(launchInterval) }
                }
            }
        }
    }
}

/// Runs an action once, on the main-queue turn after the first frame is committed.
@MainActor
private enum FirstFrame {
    private static var fired = false

    static func once(_ action: @escaping @MainActor () -> Void) {
        guard !fired else { return }
        fired = true
        // onAppear runs before the commit; the next main-queue turn is after it.
        DispatchQueue.main.async { action() }
    }
}

/// Background URLSession events (offline downloads finishing while suspended).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        #if OFFLINE_DOWNLOADS
        AppEnvironment.shared.offlineAudio.setBackgroundCompletion(completionHandler)
        #else
        completionHandler()
        #endif
    }
}
