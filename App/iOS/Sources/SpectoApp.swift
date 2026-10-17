import SwiftUI
import UserNotifications
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

/// Background refresh, notification taps, and background URLSession events (offline downloads
/// finishing while suspended).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundRefresh.register()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// A tapped new-upload notification opens its video.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["videoID"] as? String else { return }
        await MainActor.run { AppEnvironment.shared.openVideo(VideoID(rawValue: id)) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        #if OFFLINE_DOWNLOADS
        AppEnvironment.shared.offlineAudio.setBackgroundCompletion(completionHandler)
        #else
        completionHandler()
        #endif
    }
}
