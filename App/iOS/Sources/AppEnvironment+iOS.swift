import AVFoundation
import SwiftUI
import Core
import Playback
import PlaybackUI
import Cast
import WatchFeature

/// iPhone and iPad only: PiP handoff, AirPlay engine switching and the Cast sender.
extension AppEnvironment {
    /// AirPlay video needs AVPlayer; leaving AirPlay returns to mpv. Same position either way.
    func observeAudioRoute() {
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = Task { await self?.routeChanged() } }
        }
    }

    // MARK: Picture-in-Picture

    /// mpv video only: AVPlayer takes over through on-device HLS (docs/spikes/pip.md).
    var canStartPictureInPicture: Bool {
        session.engineKind == .mpv && session.mode == .video && pictureInPictureStreams != nil
    }

    private var pictureInPictureStreams: (VideoStream, AudioStream)? {
        guard let manifest = currentPage?.manifest,
              let video = manifest.videoStreams
                .filter({ $0.container == .mp4 && ($0.codec == .h264 || $0.codec == .av1) && $0.height <= 1080 })
                .filter({ $0.codec != .av1 || DecodeCapabilities().av1Hardware })
                .max(by: { $0.height < $1.height }),
              let audio = manifest.audioStreams.first(where: { $0.codec == .aac && $0.isOriginal }) else { return nil }
        return (video, audio)
    }

    func startPictureInPicture() {
        guard let (video, audio) = pictureInPictureStreams, let layer = session.hostLayer else { return }
        let position = session.position
        pictureInPicture.onStop = { [weak self] stoppedAt in
            Task {
                await self?.session.seek(to: stoppedAt, precise: true)
                self?.session.resume()
            }
        }
        Task {
            do {
                try await pictureInPicture.start(video: video, audio: audio, at: position, in: layer)
                session.pause()
            } catch {
                // PiP unsupported or not ready: playback simply continues inline.
            }
        }
    }

    // MARK: AirPlay

    private func routeChanged() async {
        let airPlaying = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
        guard let page = currentPage, let item = session.item, session.mode == .video else { return }
        let engine: EngineKind = airPlaying ? .avPlayer : .mpv
        guard session.engineKind != engine else { return }
        // AVPlayer needs MP4 renditions (on-device HLS); without them, stay on mpv.
        let selector = FormatSelector(capabilities: DecodeCapabilities())
        guard let audio = selector.selectAudio(from: page.manifest.audioStreams, for: engine, preferredLanguage: nil) else { return }
        let video = selector.select(from: page.manifest.videoStreams, for: engine, maxDisplayHeight: airPlaying ? 2160 : surfaceHeight,
                                    throughputBitsPerSecond: session.stats?.throughputBitsPerSecond, allowHDR: false)
        guard let video else { return }
        let request = PlaybackRequest(videoID: item.videoID, source: .adaptive(video: video, audio: audio),
                                      startAt: session.position, mode: .video, engine: engine)
        await session.play(item, request)
    }

    // MARK: Cast

    var castTargets: [PlayerActions.CastTarget] {
        castDiscovery.devices.map { PlayerActions.CastTarget(id: $0.id, name: $0.name) }
    }

    /// The receiver fetches media itself, so it needs a URL served by the instance: HLS (Piped,
    /// YT Zero), DASH (Invidious) or a muxed file.
    func cast(to target: PlayerActions.CastTarget) {
        guard let device = castDiscovery.devices.first(where: { $0.id == target.id }),
              let page = currentPage, let item = session.item else { return }
        let manifest = page.manifest
        let (url, type): (URL?, String) =
            if let hls = manifest.hlsURL { (hls, "application/x-mpegURL") }
            else if let dash = manifest.dashURL { (dash, "application/dash+xml") }
            else if let muxed = manifest.muxedURL { (muxed, "video/mp4") }
            else { (nil, "") }
        guard let url else { return }
        let media = CastSession.Media(url: url, contentType: type, title: item.title, subtitle: item.channelName,
                                      imageURL: item.artworkURL, startTime: Self.seconds(session.position))
        session.pause()
        castSession.cast(media, to: device)
    }

    func stopCasting() {
        let position = Duration.milliseconds(Int64(castSession.position * 1000))
        castSession.stop()
        Task {
            if position > .zero { await session.seek(to: position, precise: true) }
            session.resume()
        }
    }

    var casting: PlayerActions.Casting? {
        guard let device = castSession.device else { return nil }
        return PlayerActions.Casting(
            deviceName: device.name, isPlaying: castSession.state == .playing,
            togglePlayback: { [castSession] in castSession.state == .playing ? castSession.pause() : castSession.play() },
            stop: { [weak self] in self?.stopCasting() })
    }
}
