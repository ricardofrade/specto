import BackgroundTasks
import Library
import UserNotifications

/// Refreshes the feed in the background (so Home and the widgets are current when opened) and,
/// when the person opted in, announces new uploads.
@MainActor
enum BackgroundRefresh {
    static let identifier = "dev.placeholder.specto.refresh"

    /// At launch, before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let task = task as? BGAppRefreshTask else {
                    task.setTaskCompleted(success: false)
                    return
                }
                handle(task)
            }
        }
    }

    /// On going to the background. iOS decides when (and whether) it actually runs.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task { @MainActor in
            let environment = AppEnvironment.shared
            try? await environment.refreshFeed(force: true)
            await NewUploadNotifier.notifyIfNeeded(database: environment.database)
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}

/// Local notifications for new uploads from subscriptions (opt-in, Settings).
@MainActor
enum NewUploadNotifier {
    /// Asks for permission; false when declined.
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// The person is looking at the feed: what's there now isn't news later.
    static func markSeen() {
        AppSettings.shared.newUploadsSince = .now
    }

    static func notifyIfNeeded(database: AppDatabase) async {
        let settings = AppSettings.shared
        let since = settings.newUploadsSince ?? .now
        settings.newUploadsSince = .now
        guard settings.notifiesNewUploads else { return }
        let muted = (try? SubscriptionStore(database).mutedChannels()) ?? []
        let fresh = NewUploads.select(from: (try? FeedStore(database).rows(settings.feedOptions)) ?? [], since: since,
                                      excluding: muted)
        guard !fresh.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        if fresh.count <= 3 {
            for row in fresh {
                let content = UNMutableNotificationContent()
                content.title = row.channelName
                content.body = row.title
                content.sound = .default
                content.threadIdentifier = row.channelID.rawValue
                content.userInfo = ["videoID": row.id.rawValue]
                try? await center.add(UNNotificationRequest(identifier: row.id.rawValue, content: content, trigger: nil))
            }
        } else {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "^[\(fresh.count) new video](inflect: true)")
            content.body = fresh.prefix(3).map(\.title).joined(separator: " · ")
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: "new-uploads", content: content, trigger: nil))
        }
    }
}
