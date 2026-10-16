import Foundation
import Network
import Observation

/// A Chromecast found on the local network.
public struct CastDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    let endpoint: NWEndpoint

    public static func == (lhs: CastDevice, rhs: CastDevice) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Finds Cast receivers with Bonjour (`_googlecast._tcp`). Needs `NSBonjourServices` and
/// the local-network permission.
@MainActor
@Observable
public final class CastDiscovery {
    public private(set) var devices: [CastDevice] = []
    @ObservationIgnored private var browser: NWBrowser?

    public init() {}

    public func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let devices = results.compactMap { result -> CastDevice? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                var friendly = name
                if case .bonjour(let txt) = result.metadata, let fn = txt["fn"] { friendly = fn }
                return CastDevice(id: name, name: friendly, endpoint: result.endpoint)
            }
            Task { @MainActor in self?.devices = devices.sorted { $0.name < $1.name } }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
    }
}

/// Plays a URL on a Chromecast's default media receiver over the Cast v2 protocol, without
/// Google's SDK. The receiver fetches the media itself, so the URL must be reachable from it
/// (the instance's HLS/DASH or YT Zero ticket URL, not an in-app playlist).
@MainActor
@Observable
public final class CastSession {
    public enum State: Equatable, Sendable {
        case idle
        case connecting
        case loading
        case playing
        case paused
        case buffering
        case failed(String)
    }

    public struct Media: Sendable {
        public let url: URL
        /// "application/x-mpegURL", "application/dash+xml" or "video/mp4".
        public let contentType: String
        public let title: String
        public let subtitle: String
        public let imageURL: URL?
        public let startTime: Double

        public init(url: URL, contentType: String, title: String, subtitle: String, imageURL: URL?, startTime: Double) {
            self.url = url
            self.contentType = contentType
            self.title = title
            self.subtitle = subtitle
            self.imageURL = imageURL
            self.startTime = startTime
        }
    }

    /// The default media receiver app.
    static let defaultReceiverAppID = "CC1AD845"

    public private(set) var state = State.idle
    public private(set) var position: Double = 0
    public private(set) var device: CastDevice?

    @ObservationIgnored private var connection: NWConnection?
    @ObservationIgnored private var buffer = Data()
    @ObservationIgnored private var transportID: String?
    @ObservationIgnored private var mediaSessionID: Int?
    @ObservationIgnored private var pendingMedia: Media?
    @ObservationIgnored private var requestID = 0
    @ObservationIgnored private var heartbeat: Task<Void, Never>?

    public init() {}

    public func cast(_ media: Media, to device: CastDevice) {
        disconnect()
        self.device = device
        pendingMedia = media
        state = .connecting

        // Receivers present self-signed certificates; trust is the local network itself.
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) }, .main)
        let connection = NWConnection(to: device.endpoint, using: NWParameters(tls: tls))
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.handle(state) }
        }
        connection.start(queue: .main)
        self.connection = connection
        receive()
    }

    public func play() { sendMedia(["type": "PLAY"]) }
    public func pause() { sendMedia(["type": "PAUSE"]) }
    public func seek(to seconds: Double) { sendMedia(["type": "SEEK", "currentTime": seconds]) }

    public func stop() {
        sendMedia(["type": "STOP"])
        disconnect()
    }

    public func disconnect() {
        heartbeat?.cancel()
        connection?.cancel()
        connection = nil
        buffer = Data()
        transportID = nil
        mediaSessionID = nil
        device = nil
        state = .idle
    }

    /// Connects and asks for the receiver's status without launching anything (nothing shows
    /// on the TV). Returns the raw RECEIVER_STATUS payload. Used to check a device is reachable.
    public static func probe(_ device: CastDevice, timeout: Duration = .seconds(10)) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await Probe(device: device).run() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: Protocol flow

    private func handle(_ connectionState: NWConnection.State) {
        switch connectionState {
        case .ready:
            send(CastMessage(destinationID: "receiver-0", namespace: CastMessage.Namespace.connection,
                             payload: #"{"type":"CONNECT"}"#))
            send(json: ["type": "LAUNCH", "appId": Self.defaultReceiverAppID, "requestId": nextRequestID()],
                 to: "receiver-0", namespace: CastMessage.Namespace.receiver)
            startHeartbeat()
        case .failed(let error):
            state = .failed(error.localizedDescription)
        default:
            break
        }
    }

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self else { return }
                if let data { self.buffer.append(data) }
                if let messages = try? CastMessage.takeFrames(from: &self.buffer) {
                    messages.forEach(self.handle)
                }
                if error == nil, !done { self.receive() }
            }
        }
    }

    func handle(_ message: CastMessage) {
        guard let json = try? JSONSerialization.jsonObject(with: Data(message.payload.utf8)) as? [String: Any],
              let type = json["type"] as? String else { return }
        switch (message.namespace, type) {
        case (CastMessage.Namespace.heartbeat, "PING"):
            send(CastMessage(destinationID: message.sourceID, namespace: CastMessage.Namespace.heartbeat,
                             payload: #"{"type":"PONG"}"#))
        case (CastMessage.Namespace.receiver, "RECEIVER_STATUS"):
            let apps = (json["status"] as? [String: Any])?["applications"] as? [[String: Any]] ?? []
            guard transportID == nil,
                  let app = apps.first(where: { $0["appId"] as? String == Self.defaultReceiverAppID }),
                  let transport = app["transportId"] as? String else { return }
            transportID = transport
            send(CastMessage(destinationID: transport, namespace: CastMessage.Namespace.connection,
                             payload: #"{"type":"CONNECT"}"#))
            if let media = pendingMedia { load(media, on: transport) }
        case (CastMessage.Namespace.media, "MEDIA_STATUS"):
            guard let status = (json["status"] as? [[String: Any]])?.first else { return }
            mediaSessionID = status["mediaSessionId"] as? Int ?? mediaSessionID
            if let time = status["currentTime"] as? Double { position = time }
            switch status["playerState"] as? String {
            case "PLAYING": state = .playing
            case "PAUSED": state = .paused
            case "BUFFERING": state = .buffering
            case "IDLE":
                if status["idleReason"] as? String == "ERROR" { state = .failed("The Chromecast couldn't play this video.") }
            default: break
            }
        case (CastMessage.Namespace.media, "LOAD_FAILED"), (CastMessage.Namespace.receiver, "LAUNCH_ERROR"):
            state = .failed("The Chromecast couldn't play this video.")
        default:
            break
        }
    }

    private func load(_ media: Media, on transport: String) {
        state = .loading
        var metadata: [String: Any] = ["metadataType": 0, "title": media.title, "subtitle": media.subtitle]
        if let image = media.imageURL { metadata["images"] = [["url": image.absoluteString]] }
        send(json: ["type": "LOAD", "requestId": nextRequestID(), "autoplay": true, "currentTime": media.startTime,
                    "media": ["contentId": media.url.absoluteString, "contentType": media.contentType,
                              "streamType": "BUFFERED", "metadata": metadata]],
             to: transport, namespace: CastMessage.Namespace.media)
        pendingMedia = nil
    }

    private func sendMedia(_ command: [String: Any]) {
        guard let transportID, let mediaSessionID else { return }
        var body = command
        body["requestId"] = nextRequestID()
        body["mediaSessionId"] = mediaSessionID
        send(json: body, to: transportID, namespace: CastMessage.Namespace.media)
    }

    private func startHeartbeat() {
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.send(CastMessage(destinationID: "receiver-0", namespace: CastMessage.Namespace.heartbeat,
                                       payload: #"{"type":"PING"}"#))
            }
        }
    }

    private func send(json: [String: Any], to destination: String, namespace: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        send(CastMessage(destinationID: destination, namespace: namespace, payload: String(decoding: data, as: UTF8.self)))
    }

    private func send(_ message: CastMessage) {
        connection?.send(content: message.framed(), completion: .contentProcessed { _ in })
    }

    private func nextRequestID() -> Int {
        requestID += 1
        return requestID
    }
}

/// One read-only exchange: CONNECT, GET_STATUS, wait for RECEIVER_STATUS.
private final class Probe: @unchecked Sendable {
    private let connection: NWConnection
    // Touched only on `queue`.
    private var buffer = Data()
    private var continuation: CheckedContinuation<String, Error>?
    private let queue = DispatchQueue(label: "cast.probe")

    init(device: CastDevice) {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, complete in complete(true) },
                                              DispatchQueue(label: "cast.probe.tls"))
        connection = NWConnection(to: device.endpoint, using: NWParameters(tls: tls))
    }

    func run() async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.continuation = continuation
                    self.connection.stateUpdateHandler = { [self] state in
                        switch state {
                        case .ready:
                            send(CastMessage(destinationID: "receiver-0", namespace: CastMessage.Namespace.connection,
                                             payload: #"{"type":"CONNECT"}"#))
                            send(CastMessage(destinationID: "receiver-0", namespace: CastMessage.Namespace.receiver,
                                             payload: #"{"type":"GET_STATUS","requestId":1}"#))
                            receive()
                        case .failed(let error):
                            finish(.failure(error))
                        default:
                            break
                        }
                    }
                    self.connection.start(queue: self.queue)
                }
            }
        } onCancel: {
            queue.async { self.finish(.failure(CancellationError())) }
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self] data, _, done, error in
            if let data { buffer.append(data) }
            if let status = (try? CastMessage.takeFrames(from: &buffer))?
                .first(where: { $0.namespace == CastMessage.Namespace.receiver && $0.payload.contains("RECEIVER_STATUS") }) {
                finish(.success(status.payload))
            } else if error == nil, !done {
                receive()
            } else {
                finish(.failure(error ?? CastMessage.DecodeError.truncated))
            }
        }
    }

    private func send(_ message: CastMessage) {
        connection.send(content: message.framed(), completion: .contentProcessed { _ in })
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        connection.cancel()
        continuation.resume(with: result)
    }
}
