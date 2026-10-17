import Foundation
import QuartzCore
import os
import Core
import MPVRuntime

/// Video engine on libmpv. mpv renders through Metal (gpu-next + MoltenVK) into a layer the
/// engine owns, so attaching to a new `RenderSurfaceHost` only moves that layer: fold,
/// rotation and split-screen never reload playback.
@MainActor
public final class MPVEngine: PlaybackEngine {
    public struct Configuration: Sendable {
        /// False runs mpv with no video output (headless tests).
        public var rendersVideo: Bool
        public var playsAudio: Bool
        public var cacheSeconds: Int

        public init(rendersVideo: Bool = true, playsAudio: Bool = true, cacheSeconds: Int = 120) {
            self.rendersVideo = rendersVideo
            self.playsAudio = playsAudio
            self.cacheSeconds = cacheSeconds
        }
    }

    public let kind = EngineKind.mpv
    public let events: AsyncStream<PlaybackEvent>

    private let configuration: Configuration
    private let continuation: AsyncStream<PlaybackEvent>.Continuation
    private let layer = MPVMetalLayer()
    private var core: MPVCore?
    private var coreEvents: Task<Void, Never>?
    private var pendingLoad: CheckedContinuation<Void, Error>?
    private var isLoaded = false
    private var isPaused = false
    private var isBuffering = false
    private var duration: Duration?
    private var lastDecoder: DecoderInfo?
    private let log = Logger(subsystem: "dev.placeholder.specto", category: "mpv")

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(64))
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        layer.framebufferOnly = true
    }

    // MARK: PlaybackEngine

    public func prewarm() {
        _ = try? ensureCore()
    }

    public func load(_ request: PlaybackRequest) async throws {
        let core = try ensureCore()
        finishPendingLoad(.failure(PlaybackError.other("Superseded by a newer load")))
        isLoaded = false
        isBuffering = false
        duration = nil
        lastDecoder = nil
        emit(.state(.loading))
        core.resetLoadState()

        let (url, options) = Self.loadArguments(for: request)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingLoad = continuation
            core.command(["loadfile", url, "replace", "-1", options])
        }
    }

    public func play() {
        core?.setProperty("pause", flag: false)
    }

    public func pause() {
        core?.setProperty("pause", flag: true)
    }

    public func seek(to position: Duration, precise: Bool) async {
        core?.command(["seek", Self.seconds(position), precise ? "absolute+exact" : "absolute+keyframes"])
    }

    public func setRate(_ rate: Float) {
        core?.setProperty("speed", double: Double(rate))
    }

    public func stop() {
        finishPendingLoad(.failure(PlaybackError.other("Stopped")))
        core?.command(["stop"])
        isLoaded = false
        emit(.state(.idle))
    }

    public func attach(_ host: any RenderSurfaceHost) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.containerLayer.addSublayer(layer)
        layer.contentsScale = host.containerLayer.contentsScale
        layer.frame = host.containerLayer.bounds
        CATransaction.commit()
    }

    public func detach() {
        layer.removeFromSuperlayer()
    }

    public func setVideoEnabled(_ enabled: Bool) {
        core?.setProperty("vid", string: enabled ? "auto" : "no")
    }

    public func layoutSurface() {
        guard let superlayer = layer.superlayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = superlayer.bounds
        CATransaction.commit()
    }

    // MARK: Core

    private func ensureCore() throws -> MPVCore {
        if let core { return core }
        let (stream, sink) = AsyncStream.makeStream(of: MPVCoreEvent.self)
        let windowID = configuration.rendersVideo
            ? CALayerPointer(value: Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque())))
            : nil
        let created = try MPVCore(windowID: windowID, audioOutput: configuration.playsAudio,
                                  cacheSeconds: configuration.cacheSeconds) { sink.yield($0) }
        core = created
        coreEvents = Task { [weak self] in
            for await event in stream {
                self?.handle(event)
            }
        }
        return created
    }

    private func handle(_ event: MPVCoreEvent) {
        switch event {
        case .fileLoaded:
            isLoaded = true
            finishPendingLoad(.success(()))
            emitState()
        case .endFile(let reason, let errorCode, let httpStatus):
            switch reason {
            case .stop, .other:
                // The replaced or stopped file; never reported (engine contract).
                break
            case .eof:
                emit(.state(.ended))
            case .error:
                let error = Self.error(code: errorCode, httpStatus: httpStatus)
                log.error("Load failed: \(String(describing: error), privacy: .public)")
                if pendingLoad != nil {
                    finishPendingLoad(.failure(error))
                } else {
                    emit(.state(.failed(error)))
                }
            }
        case .position(let seconds):
            guard isLoaded else { return }
            emit(.position(.milliseconds(Int64(seconds * 1000)), duration: duration))
        case .duration(let seconds):
            duration = seconds.map { .milliseconds(Int64($0 * 1000)) }
        case .paused(let paused):
            isPaused = paused
            emitState()
        case .buffering(let buffering):
            isBuffering = buffering
            emitState()
        case .seekFinished:
            emitState()
        case .video(let format, let hwdec, let width, let height):
            guard let codec = Self.codec(format) else { return }
            let isHardware = hwdec.map { !$0.isEmpty && $0 != "no" } ?? false
            let info = DecoderInfo(codec: codec, isHardware: isHardware, width: width, height: height)
            guard info != lastDecoder else { return }
            lastDecoder = info
            log.info("Decoder: \(codec.rawValue, privacy: .public) \(width)x\(height) hwdec=\(hwdec ?? "no", privacy: .public)")
            emit(.decoder(info))
        case .stats(let dropped, let buffered, let bytesPerSecond):
            guard isLoaded else { return }
            emit(.stats(PlaybackStats(droppedFrames: dropped,
                                      bufferedAhead: .milliseconds(Int64(buffered * 1000)),
                                      throughputBitsPerSecond: bytesPerSecond.map { $0 * 8 })))
        }
    }

    private func emitState() {
        guard isLoaded else { return }
        emit(.state(isBuffering ? .buffering : isPaused ? .paused : .playing))
    }

    private func emit(_ event: PlaybackEvent) {
        continuation.yield(event)
    }

    private func finishPendingLoad(_ result: Result<Void, Error>) {
        guard let pending = pendingLoad else { return }
        pendingLoad = nil
        pending.resume(with: result)
    }

    // MARK: Mapping

    static func loadArguments(for request: PlaybackRequest) -> (url: String, options: String) {
        // A live stream starts at the live edge; `start=0` would seek to the oldest part of
        // its DVR window (an hour back on YouTube).
        var options = request.isLive ? [] : ["start=\(seconds(request.startAt))"]
        let url: String
        switch request.source {
        case .adaptive(let video, let audio):
            if let video {
                url = video.url.absoluteString
                options.append("audio-file=\(escaped(audio.url.absoluteString))")
            } else {
                url = audio.url.absoluteString
            }
        case .hls(let single), .progressive(let single):
            url = single.absoluteString
        }
        if request.mode == .audioOnly { options.append("vid=no") }
        if let caption = request.caption { options.append("sub-file=\(escaped(caption.url.absoluteString))") }
        return (url, options.joined(separator: ","))
    }

    /// mpv's `%length%value` quoting, so commas and equals signs in URLs survive option parsing.
    static func escaped(_ value: String) -> String {
        "%\(value.utf8.count)%\(value)"
    }

    static func seconds(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return String(format: "%.3f", Double(seconds) + Double(attoseconds) / 1e18)
    }

    static func codec(_ mpvFormat: String?) -> VideoCodec? {
        switch mpvFormat?.lowercased() {
        case "av1": .av1
        case "vp9": .vp9
        case "h264": .h264
        default: nil
        }
    }

    static func error(code: Int32, httpStatus: Int?) -> PlaybackError {
        // 403/410: expired or IP-bound googlevideo URLs; 401: an expired YT Zero playback ticket.
        if let httpStatus, [401, 403, 410].contains(httpStatus) { return .streamExpired }
        if httpStatus != nil { return .network }
        switch code {
        case MPV_ERROR_UNKNOWN_FORMAT.rawValue: return .unsupportedFormat("mpv could not identify the stream")
        case MPV_ERROR_LOADING_FAILED.rawValue: return .network
        default: return .other(String(cString: mpv_error_string(code)))
        }
    }
}

/// Works around MoltenVK briefly setting a 1×1 drawable to force presentation, which
/// flickers and can leave the layer at 1×1 (mpv-player/mpv#13651).
final class MPVMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }
}
