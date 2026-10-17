import AVFoundation
import MediaPlayer
import Observation
import UIKit
import Core
import Playback

/// Lock Screen, Control Center, headphones and CarPlay controls for the shared session:
/// publishes Now Playing info and routes remote commands back to the session.
@MainActor
public final class NowPlayingController {
    /// Loads artwork (the app's image pipeline, with any instance auth).
    public typealias ArtworkLoader = @Sendable (URL) async -> UIImage?

    private let session: PlaybackSession
    private let loadArtwork: ArtworkLoader
    private var artwork: (url: URL, image: MPMediaItemArtwork)?
    private var lastPublished: (id: VideoID?, state: PlaybackState, second: Int64) = (nil, .idle, -1)

    public init(session: PlaybackSession, loadArtwork: @escaping ArtworkLoader) {
        self.session = session
        self.loadArtwork = loadArtwork
        configureCommands()
        track()
    }

    /// Audio keeps playing in the background, with the ring switch off and through AirPlay.
    public static func configureAudioSession() {
        let audio = AVAudioSession.sharedInstance()
        #if os(tvOS)
        try? audio.setCategory(.playback, mode: .moviePlayback)
        #else
        try? audio.setCategory(.playback, mode: .moviePlayback, policy: .longFormVideo)
        #endif
    }

    // MARK: Remote commands

    /// Handlers are @Sendable and hop to the main actor: MediaPlayer doesn't promise to call
    /// them on the main thread, and an inherited main-actor closure would trap elsewhere.
    private func configureCommands() {
        let center = MPRemoteCommandCenter.shared()
        let session = self.session
        center.playCommand.addTarget { @Sendable _ in
            Task { @MainActor in session.resume() }
            return .success
        }
        center.pauseCommand.addTarget { @Sendable _ in
            Task { @MainActor in session.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { @Sendable _ in
            Task { @MainActor in session.state == .playing ? session.pause() : session.resume() }
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipForwardCommand.addTarget { @Sendable _ in
            Task { @MainActor in await session.seek(to: session.position + .seconds(15)) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { @Sendable _ in
            Task { @MainActor in await session.seek(to: max(.zero, session.position - .seconds(15))) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { @Sendable event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let target = Duration.milliseconds(Int64(event.positionTime * 1000))
            Task { @MainActor in await session.seek(to: target, precise: true) }
            return .success
        }
    }

    // MARK: Now Playing info

    /// Re-publishes when the item or state changes, or position moves by a second; the system
    /// interpolates elapsed time from the rate in between.
    private func track() {
        withObservationTracking {
            _ = session.item
            _ = session.state
            _ = session.position
            _ = session.duration
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.publish()
                self?.track()
            }
        }
    }

    private func publish() {
        let center = MPNowPlayingInfoCenter.default()
        guard let item = session.item else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            lastPublished = (nil, .idle, -1)
            return
        }
        let second = session.position.components.seconds
        guard lastPublished.id != item.videoID || lastPublished.state != session.state
                || abs(lastPublished.second - second) >= 1 else { return }
        lastPublished = (item.videoID, session.state, second)

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.channelName,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Self.seconds(session.position),
            MPNowPlayingInfoPropertyPlaybackRate: session.state == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: session.mode == .audioOnly
                ? MPNowPlayingInfoMediaType.audio.rawValue : MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let duration = session.duration { info[MPMediaItemPropertyPlaybackDuration] = Self.seconds(duration) }
        if let artwork, artwork.url == item.artworkURL { info[MPMediaItemPropertyArtwork] = artwork.image }
        center.nowPlayingInfo = info
        center.playbackState = session.state == .playing ? .playing : .paused

        if let url = item.artworkURL, artwork?.url != url {
            Task {
                guard let image = await loadArtwork(url) else { return }
                self.artwork = (url, Self.artwork(image))
                self.lastPublished.second = -1     // Force a refresh with the artwork.
                self.publish()
            }
        }
    }

    /// MediaPlayer calls the handler on its own queue: it must not inherit main-actor isolation
    /// (a closure created in a `@MainActor` method would, and the runtime traps when it runs).
    nonisolated static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { @Sendable _ in image }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
