import SwiftUI
import Playback
import PlaybackUI

/// What the Playback menu can do while the Watch screen is showing (iPad menu bar and hardware
/// keyboards). Published by the root view as a focused scene value only while a video is open,
/// so space acts on the player only then, never while typing in Search.
struct PlayerCommandsTarget {
    let session: PlaybackSession
    let toggleCaptions: () -> Void
    let toggleAudioOnly: () -> Void
}

extension FocusedValues {
    @Entry var player: PlayerCommandsTarget?
}

struct PlaybackCommands: Commands {
    @FocusedValue(\.player) private var player

    var body: some Commands {
        CommandMenu(Text("Playback")) {
            Button {
                guard let session = player?.session else { return }
                session.state == .playing ? session.pause() : session.resume()
            } label: { Text("Play/Pause") }
            .keyboardShortcut(.space, modifiers: [])

            // ←/→ belong to keyboard navigation as menu shortcuts; the player handles them itself
            // while it has keyboard focus (PlayerArea).
            Button { skip(-10) } label: { Text("Back 10 Seconds") }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
            Button { skip(10) } label: { Text("Forward 10 Seconds") }
                .keyboardShortcut(.rightArrow, modifiers: [.command])

            Divider()

            Button { changeSpeed(by: 1) } label: { Text("Faster") }
                .keyboardShortcut("]", modifiers: [])
            Button { changeSpeed(by: -1) } label: { Text("Slower") }
                .keyboardShortcut("[", modifiers: [])

            Divider()

            Button { player?.toggleCaptions() } label: { Text("Subtitles") }
                .keyboardShortcut("c", modifiers: [.option])
            Button { player?.toggleAudioOnly() } label: { Text("Audio Only") }
                .keyboardShortcut("a", modifiers: [.option])
        }
    }

    private func skip(_ seconds: Int64) {
        guard let session = player?.session else { return }
        let target = max(.zero, session.position + .seconds(seconds))
        Task { await session.seek(to: target, precise: true) }
    }

    /// One step along the speed menu's options.
    private func changeSpeed(by step: Int) {
        guard let session = player?.session else { return }
        let rates = SpeedOptions.all.map(\.rate)
        let index = rates.firstIndex(of: session.rate) ?? rates.firstIndex(of: 1) ?? 0
        session.setRate(rates[min(max(0, index + step), rates.count - 1)])
    }
}
