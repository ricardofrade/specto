import Foundation
import MPVRuntime

/// What the core reports to `MPVEngine`. Raw mpv facts; the engine turns them into `PlaybackEvent`s.
enum MPVCoreEvent: Sendable {
    case fileLoaded
    /// The current file ended. `httpStatus` is the last HTTP error mpv logged for it, if any.
    case endFile(reason: EndReason, errorCode: Int32, httpStatus: Int?)
    case position(Double)
    case duration(Double?)
    case paused(Bool)
    case buffering(Bool)
    case seekFinished
    case video(format: String?, hwdec: String?, width: Int, height: Int)
    case stats(droppedFrames: Int, bufferedAhead: Double, bytesPerSecond: Double?)

    enum EndReason: Sendable { case eof, stop, error, other }
}

/// Owns one mpv handle. libmpv's client API is thread-safe, so commands are issued from any
/// thread; events are drained on `queue`, and every mutable field below is touched only there.
final class MPVCore: @unchecked Sendable {
    private(set) var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "player.mpv.events", qos: .userInitiated)
    private let onEvent: @Sendable (MPVCoreEvent) -> Void
    private var statsTimer: DispatchSourceTimer?

    // Queue-confined state.
    private var lastHTTPStatus: Int?
    private var videoFormat: String?
    private var hwdec: String?
    private var videoSize = (width: 0, height: 0)
    private var lastPositionEmit: UInt64 = 0

    /// - Parameter windowID: the CAMetalLayer mpv renders into, or nil for no video output.
    init(windowID: CALayerPointer?, audioOutput: Bool, cacheSeconds: Int,
         onEvent: @escaping @Sendable (MPVCoreEvent) -> Void) throws {
        self.onEvent = onEvent
        guard let handle = mpv_create() else { throw PlaybackError.other("mpv_create failed") }
        self.handle = handle

        if var wid = windowID?.value {
            mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid)
            set("vo", "gpu-next")
            set("gpu-api", "vulkan")
            set("gpu-context", "moltenvk")
        } else {
            set("vo", "null")
        }
        if !audioOutput { set("ao", "null") }
        set("hwdec", "videotoolbox")
        set("video-rotate", "no")
        set("idle", "yes")
        set("keep-open", "yes")
        set("ytdl", "no")
        set("input-default-bindings", "no")
        set("input-vo-keyboard", "no")
        // Cache tuned for instant seeks: keep 50 MiB behind the playhead so seeking back never
        // refetches, start playing before the cache fills, and resume quickly after a stall.
        set("cache", "yes")
        set("demuxer-readahead-secs", "\(cacheSeconds)")
        set("demuxer-max-bytes", "150MiB")
        set("demuxer-max-back-bytes", "50MiB")
        set("demuxer-seekable-cache", "yes")
        set("force-seekable", "yes")
        set("cache-pause-initial", "no")
        set("cache-pause-wait", "0.5")
        set("stream-buffer-size", "512KiB")
        set("network-timeout", "15")
        set("subs-fallback", "yes")
        set("audio-client-name", "Player")

        guard mpv_initialize(handle) >= 0 else {
            mpv_terminate_destroy(handle)
            self.handle = nil
            throw PlaybackError.other("mpv_initialize failed")
        }
        // Warnings carry the HTTP status of failed stream requests.
        mpv_request_log_messages(handle, "warn")

        mpv_observe_property(handle, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "video-format", MPV_FORMAT_STRING)
        mpv_observe_property(handle, 0, "hwdec-current", MPV_FORMAT_STRING)
        mpv_observe_property(handle, 0, "video-params/w", MPV_FORMAT_INT64)
        mpv_observe_property(handle, 0, "video-params/h", MPV_FORMAT_INT64)

        let context = Unmanaged.passUnretained(self).toOpaque()
        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            Unmanaged<MPVCore>.fromOpaque(context).takeUnretainedValue().scheduleDrain()
        }, context)
        startStatsTimer()
    }

    deinit {
        statsTimer?.cancel()
        if let handle {
            mpv_set_wakeup_callback(handle, nil, nil)
            mpv_terminate_destroy(handle)
        }
    }

    // MARK: Commands

    func command(_ args: [String]) {
        guard let handle else { return }
        var cStrings = args.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        var argv = cStrings.map { UnsafePointer($0) } + [nil]
        mpv_command(handle, &argv)
    }

    func setProperty(_ name: String, flag: Bool) {
        guard let handle else { return }
        var value: Int32 = flag ? 1 : 0
        mpv_set_property(handle, name, MPV_FORMAT_FLAG, &value)
    }

    func setProperty(_ name: String, double: Double) {
        guard let handle else { return }
        var value = double
        mpv_set_property(handle, name, MPV_FORMAT_DOUBLE, &value)
    }

    func setProperty(_ name: String, string: String) {
        guard let handle else { return }
        mpv_set_property_string(handle, name, string)
    }

    /// Forget the previous file's HTTP error before a new load.
    func resetLoadState() {
        queue.async { self.lastHTTPStatus = nil }
    }

    private func set(_ option: String, _ value: String) {
        guard let handle else { return }
        mpv_set_option_string(handle, option, value)
    }

    // MARK: Events

    private func scheduleDrain() {
        queue.async { self.drain() }
    }

    private func drain() {
        guard let handle else { return }
        while let event = mpv_wait_event(handle, 0)?.pointee, event.event_id != MPV_EVENT_NONE {
            process(event)
        }
    }

    private func process(_ event: mpv_event) {
        switch event.event_id {
        case MPV_EVENT_FILE_LOADED:
            onEvent(.fileLoaded)
        case MPV_EVENT_END_FILE:
            guard let end = event.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee else { return }
            let reason: MPVCoreEvent.EndReason = switch end.reason {
            case MPV_END_FILE_REASON_EOF: .eof
            case MPV_END_FILE_REASON_STOP, MPV_END_FILE_REASON_QUIT: .stop
            case MPV_END_FILE_REASON_ERROR: .error
            default: .other
            }
            onEvent(.endFile(reason: reason, errorCode: end.error, httpStatus: lastHTTPStatus))
        case MPV_EVENT_PLAYBACK_RESTART:
            onEvent(.seekFinished)
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let property = event.data?.assumingMemoryBound(to: mpv_event_property.self).pointee else { return }
            process(property)
        case MPV_EVENT_LOG_MESSAGE:
            guard let message = event.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee,
                  let text = message.text.map({ String(cString: $0) }) else { return }
            if let status = Self.httpStatus(in: text) { lastHTTPStatus = status }
        default:
            break
        }
    }

    private func process(_ property: mpv_event_property) {
        let name = String(cString: property.name)
        switch name {
        case "time-pos":
            guard let value = double(property) else { return }
            // Throttle: a few times per second, never per frame (PlaybackEvent contract).
            let now = DispatchTime.now().uptimeNanoseconds
            guard now - lastPositionEmit >= 250_000_000 else { return }
            lastPositionEmit = now
            onEvent(.position(value))
        case "duration":
            onEvent(.duration(double(property)))
        case "pause":
            onEvent(.paused(flag(property) ?? false))
        case "paused-for-cache":
            onEvent(.buffering(flag(property) ?? false))
        case "video-format":
            videoFormat = string(property)
            emitVideo()
        case "hwdec-current":
            hwdec = string(property)
            emitVideo()
        case "video-params/w":
            videoSize.width = int(property) ?? 0
            emitVideo()
        case "video-params/h":
            videoSize.height = int(property) ?? 0
            emitVideo()
        default:
            break
        }
    }

    private func emitVideo() {
        guard videoSize.width > 0, videoSize.height > 0, videoFormat != nil else { return }
        onEvent(.video(format: videoFormat, hwdec: hwdec, width: videoSize.width, height: videoSize.height))
    }

    private func startStatsTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.pollStats() }
        timer.resume()
        statsTimer = timer
    }

    private func pollStats() {
        guard let handle else { return }
        var drops: Int64 = 0, decoderDrops: Int64 = 0, speed: Int64 = 0
        var cached: Double = 0
        mpv_get_property(handle, "frame-drop-count", MPV_FORMAT_INT64, &drops)
        mpv_get_property(handle, "decoder-frame-drop-count", MPV_FORMAT_INT64, &decoderDrops)
        mpv_get_property(handle, "demuxer-cache-duration", MPV_FORMAT_DOUBLE, &cached)
        let hasSpeed = mpv_get_property(handle, "cache-speed", MPV_FORMAT_INT64, &speed) >= 0
        onEvent(.stats(droppedFrames: Int(drops + decoderDrops), bufferedAhead: cached,
                       bytesPerSecond: hasSpeed ? Double(speed) : nil))
    }

    // MARK: Decoding helpers

    private func double(_ p: mpv_event_property) -> Double? {
        guard p.format == MPV_FORMAT_DOUBLE, let data = p.data else { return nil }
        return data.assumingMemoryBound(to: Double.self).pointee
    }

    private func flag(_ p: mpv_event_property) -> Bool? {
        guard p.format == MPV_FORMAT_FLAG, let data = p.data else { return nil }
        return data.assumingMemoryBound(to: Int32.self).pointee != 0
    }

    private func int(_ p: mpv_event_property) -> Int? {
        guard p.format == MPV_FORMAT_INT64, let data = p.data else { return nil }
        return Int(data.assumingMemoryBound(to: Int64.self).pointee)
    }

    private func string(_ p: mpv_event_property) -> String? {
        guard p.format == MPV_FORMAT_STRING, let data = p.data,
              let cString = data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee else { return nil }
        return String(cString: cString)
    }

    /// "HTTP error 403 Forbidden" → 403.
    static func httpStatus(in logLine: String) -> Int? {
        guard let range = logLine.range(of: #"HTTP error (\d{3})"#, options: .regularExpression) else { return nil }
        return Int(logLine[range].suffix(3))
    }
}

/// A CAMetalLayer's address, as mpv's `wid` option expects it.
struct CALayerPointer: Sendable {
    let value: Int64
}
