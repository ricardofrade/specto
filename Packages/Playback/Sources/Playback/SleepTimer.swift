import Foundation
import Observation

/// Pauses playback after a while, or stops at the end of the current video (auto-advance asks
/// `stopsAtEndOfVideo` before playing the next one). The countdown is published a minute at a
/// time, pre-formatted, so the menu never does date math.
@MainActor
@Observable
public final class SleepTimer {
    public enum Choice: Hashable, Sendable {
        case minutes(Int)
        case endOfVideo
    }

    public static let choices: [Choice] = [.minutes(15), .minutes(30), .minutes(45), .minutes(60), .endOfVideo]

    public private(set) var choice: Choice?
    /// "12 min left" while counting down, "End of video", or nil when off.
    public private(set) var status: String?

    @ObservationIgnored private let session: PlaybackSession
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var countdown: Task<Void, Never>?

    /// - Parameter sleep: injectable so tests don't wait for real minutes.
    public init(session: PlaybackSession,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.session = session
        self.sleep = sleep
    }

    /// nil turns the timer off.
    public func set(_ choice: Choice?) {
        countdown?.cancel()
        countdown = nil
        self.choice = choice
        switch choice {
        case .minutes(let minutes):
            status = Self.remaining(minutes)
            countdown = Task { [weak self] in await self?.count(down: minutes) }
        case .endOfVideo:
            status = String(localized: "End of video")
        case nil:
            status = nil
        }
    }

    /// Called when a video ends: true (once) when the timer says to stop there.
    public func stopsAtEndOfVideo() -> Bool {
        guard choice == .endOfVideo else { return false }
        set(nil)
        return true
    }

    public static func label(for choice: Choice) -> String {
        switch choice {
        case .minutes(let minutes):
            Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
        case .endOfVideo:
            String(localized: "End of video")
        }
    }

    private func count(down minutes: Int) async {
        for left in stride(from: minutes, to: 0, by: -1) {
            // A cancelled countdown may first run after `set` replaced it: never write then.
            guard !Task.isCancelled else { return }
            status = Self.remaining(left)
            do { try await sleep(.seconds(60)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        session.pause()
        choice = nil
        status = nil
        countdown = nil
    }

    private static func remaining(_ minutes: Int) -> String {
        String(localized: "\(minutes) min left")
    }
}
