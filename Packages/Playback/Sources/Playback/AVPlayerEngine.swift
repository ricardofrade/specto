import AVFoundation
import QuartzCore
import Core

/// AVPlayer engine: audio-only mode, CarPlay and AirPlay, and HLS. Adaptive streams play
/// through on-device HLS (`LocalHLS`); audio-only plays the AAC stream directly.
@MainActor
public final class AVPlayerEngine: PlaybackEngine {
    public let kind = EngineKind.avPlayer
    public let events: AsyncStream<PlaybackEvent>

    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private let player = AVPlayer()
    private let layer = AVPlayerLayer()
    private var prepared: LocalHLS.Prepared?
    private var timeObserver: Any?
    private var observations: [NSKeyValueObservation] = []
    private var endObserver: (any NSObjectProtocol)?
    private var statsTask: Task<Void, Never>?
    private var isLoaded = false

    public init() {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))
        layer.player = player
        layer.videoGravity = .resizeAspect
        player.allowsExternalPlayback = true          // AirPlay video.
        player.automaticallyWaitsToMinimizeStalling = true
    }

    // MARK: PlaybackEngine

    public func prewarm() {}

    public func load(_ request: PlaybackRequest) async throws {
        isLoaded = false
        tearDownItem()
        continuation.yield(.state(.loading))

        let asset: AVURLAsset
        switch request.source {
        case .adaptive(let video?, let audio):
            let prepared = try await LocalHLS.prepare(video: video, audio: audio)
            self.prepared = prepared
            asset = prepared.asset
        case .adaptive(nil, let audio):
            asset = AVURLAsset(url: audio.url)
        case .hls(let url), .progressive(let url):
            asset = AVURLAsset(url: url)
        }
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 30
        player.replaceCurrentItem(with: item)
        observe(item)

        try await waitUntilReady(item)
        if request.startAt > .zero {
            await item.seek(to: Self.time(request.startAt), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        isLoaded = true
        emitState()
    }

    public func play() { player.play() }
    public func pause() { player.pause() }

    public func seek(to position: Duration, precise: Bool) async {
        let tolerance = precise ? CMTime.zero : CMTime(seconds: 1, preferredTimescale: 600)
        await player.seek(to: Self.time(position), toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    public func setRate(_ rate: Float) {
        player.defaultRate = rate
        if player.rate > 0 { player.rate = rate }
    }

    public func stop() {
        player.pause()
        tearDownItem()
        isLoaded = false
        continuation.yield(.state(.idle))
    }

    public func attach(_ host: any RenderSurfaceHost) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.containerLayer.addSublayer(layer)
        layer.frame = host.containerLayer.bounds
        CATransaction.commit()
    }

    public func detach() {
        layer.removeFromSuperlayer()
    }

    public func layoutSurface() {
        guard let superlayer = layer.superlayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = superlayer.bounds
        CATransaction.commit()
    }

    /// Detaching the layer keeps audio playing in the background (Apple's documented approach).
    public func setVideoEnabled(_ enabled: Bool) {
        layer.player = enabled ? player : nil
    }

    /// The layer PiP and AirPlay use.
    public var playerLayer: AVPlayerLayer { layer }

    // MARK: Observation

    private func observe(_ item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) {
            [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.isLoaded else { return }
                let duration = item.duration.isNumeric ? Duration.milliseconds(Int64(item.duration.seconds * 1000)) : nil
                self.continuation.yield(.position(.milliseconds(Int64(time.seconds * 1000)), duration: duration))
            }
        }
        // KVO fires on whatever thread made the change: handlers are @Sendable and hop to the
        // main actor (an inherited main-actor closure would trap off the main thread).
        observations = [
            player.observe(\.timeControlStatus) { @Sendable [weak self] _, _ in
                Task { @MainActor in self?.emitState() }
            },
            item.observe(\.status) { @Sendable [weak self] item, _ in
                guard item.status == .failed else { return }
                let error = Self.map(item.error)
                Task { @MainActor in self?.continuation.yield(.state(.failed(error))) }
            },
        ]
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.continuation.yield(.state(.ended)) }
        }
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isLoaded, let item = self.player.currentItem else { continue }
                let event = item.accessLog()?.events.last
                let buffered = item.loadedTimeRanges.first.map { range -> Double in
                    let r = range.timeRangeValue
                    return max(0, (r.start + r.duration).seconds - self.player.currentTime().seconds)
                } ?? 0
                self.continuation.yield(.stats(PlaybackStats(
                    droppedFrames: event?.numberOfDroppedVideoFrames ?? 0,
                    bufferedAhead: .milliseconds(Int64(buffered * 1000)),
                    throughputBitsPerSecond: event.map(\.observedBitrate).flatMap { $0 > 0 ? $0 : nil })))
            }
        }
    }

    private func emitState() {
        guard isLoaded else { return }
        switch player.timeControlStatus {
        case .playing: continuation.yield(.state(.playing))
        case .waitingToPlayAtSpecifiedRate: continuation.yield(.state(.buffering))
        case .paused: continuation.yield(.state(.paused))
        @unknown default: break
        }
    }

    private func tearDownItem() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        observations = []
        statsTask?.cancel()
        statsTask = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player.replaceCurrentItem(with: nil)
        prepared = nil
    }

    private func waitUntilReady(_ item: AVPlayerItem) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while item.status == .unknown {
            guard ContinuousClock.now < deadline else { throw PlaybackError.network }
            try await Task.sleep(for: .milliseconds(20))
        }
        if item.status == .failed { throw Self.map(item.error) }
    }

    /// CoreMedia reports HTTP failures as -12660 (403) and similar; expired URLs recover by refetch.
    nonisolated static func map(_ error: Error?) -> PlaybackError {
        guard let error = error as NSError? else { return .other("Unknown playback error") }
        let codes = [error.code] + ((error.userInfo[NSUnderlyingErrorKey] as? NSError).map { [$0.code] } ?? [])
        if codes.contains(where: { [-12660, -12661, 401, 403, 410].contains($0) }) { return .streamExpired }
        if error.domain == NSURLErrorDomain { return .network }
        if codes.contains(-11828) || codes.contains(-11829) { return .unsupportedFormat(error.localizedDescription) }
        return .other(error.localizedDescription)
    }

    private static func time(_ duration: Duration) -> CMTime {
        CMTime(seconds: Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18,
               preferredTimescale: 600)
    }
}
