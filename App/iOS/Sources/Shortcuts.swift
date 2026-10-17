import AppIntents
import Library

/// "Continue watching in Specto", "Play my queue in Specto": Siri, Shortcuts and Spotlight.
/// Each opens the app and hands the video to the root view (`AppEnvironment.pendingVideo`).
nonisolated struct ContinueWatchingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Watching"
    static let description = IntentDescription("Resume the video you were watching most recently.")
    static let supportedModes: IntentModes = .foreground

    func perform() async throws -> some IntentResult {
        guard await ShortcutActions.continueWatching(AppEnvironment.shared) else { throw ShortcutError.nothingInProgress }
        return .result()
    }
}

nonisolated struct PlayQueueIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Queue"
    static let description = IntentDescription("Play the first video in your queue.")
    static let supportedModes: IntentModes = .foreground

    func perform() async throws -> some IntentResult {
        guard await ShortcutActions.playQueue(AppEnvironment.shared) else { throw ShortcutError.queueEmpty }
        return .result()
    }
}

/// What Siri says when there's nothing to play.
nonisolated enum ShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case nothingInProgress, queueEmpty

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .nothingInProgress: "Nothing to continue."
        case .queueEmpty: "Your queue is empty."
        }
    }
}

nonisolated struct SpectoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ContinueWatchingIntent(),
                    phrases: ["Continue watching in \(.applicationName)", "Resume \(.applicationName)"],
                    shortTitle: "Continue Watching", systemImageName: "play.circle")
        AppShortcut(intent: PlayQueueIntent(),
                    phrases: ["Play my queue in \(.applicationName)", "Play my \(.applicationName) queue"],
                    shortTitle: "Play Queue", systemImageName: "list.bullet")
    }
}

/// What the shortcuts do, separate from App Intents so it's testable.
@MainActor
enum ShortcutActions {
    /// False when nothing is in progress.
    static func continueWatching(_ environment: AppEnvironment) -> Bool {
        guard let row = try? WatchStateStore(environment.database).inProgress(limit: 1).first else { return false }
        environment.pendingVideo = row.video
        return true
    }

    /// False when the queue is empty.
    static func playQueue(_ environment: AppEnvironment) -> Bool {
        guard let row = try? QueueStore(environment.database).rows().first else { return false }
        environment.pendingVideo = row.video
        return true
    }
}
