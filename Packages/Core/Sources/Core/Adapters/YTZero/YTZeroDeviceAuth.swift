import Foundation

/// YT Zero's device-code sign-in: show a code, the user approves it in YT Zero's web UI
/// (`/tv/pair`), and the app receives a Bearer token (30 days, renewed on every request).
/// Shaped like OAuth's device grant, but pending is HTTP 428 and expiry is HTTP 400.
public struct YTZeroDeviceAuth: Sendable {
    public struct Code: Sendable, Equatable {
        public let deviceCode: String
        public let userCode: String
        public let verificationURL: URL
        /// Opens the pairing page with the code filled in; good for a QR code.
        public let verificationURLComplete: URL?
        public let expiresIn: Duration
        public let interval: Duration
    }

    public enum PollResult: Sendable, Equatable {
        case pending
        case expired
        case authorized(token: String)
    }

    private let api: APIRequester

    public init(instanceURL: URL, client: any HTTPClient = URLSessionHTTPClient()) {
        api = APIRequester(baseURL: instanceURL, client: client)
    }

    public func start(deviceName: String) async throws -> Code {
        struct Body: Encodable { let device_name: String }
        let code: YTZeroDTO.DeviceCode = try await api.post("api/auth/device/code", json: Body(device_name: deviceName))
        guard let url = URL(string: code.verification_uri) else { throw SourceError.decoding("verification_uri") }
        return Code(deviceCode: code.device_code, userCode: code.user_code, verificationURL: url,
                    verificationURLComplete: code.verification_uri_complete.flatMap(URL.init(string:)),
                    expiresIn: .seconds(code.expires_in), interval: .seconds(max(code.interval, 1)))
    }

    public func poll(_ code: Code) async throws -> PollResult {
        struct Body: Encodable { let device_code: String }
        do {
            let token: YTZeroDTO.Token = try await api.post("api/auth/device/token", json: Body(device_code: code.deviceCode))
            return .authorized(token: token.access_token)
        } catch SourceError.http(status: 428) {
            return .pending
        } catch SourceError.http(status: 400) {
            return .expired
        }
    }

    /// Polls at the server's interval until approved, expired or cancelled.
    public func waitForApproval(_ code: Code) async throws -> String? {
        let deadline = ContinuousClock.now + code.expiresIn
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: code.interval)
            switch try await poll(code) {
            case .pending: continue
            case .expired: return nil
            case .authorized(let token): return token
            }
        }
        return nil
    }
}
