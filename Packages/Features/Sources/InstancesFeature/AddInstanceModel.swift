import Foundation
import Observation
import Core
import Library

/// Paste a URL → detect what it is → (YT Zero: pair this device) → save.
@Observable
public final class AddInstanceModel {
    public enum Step: Equatable {
        case enterURL
        case detecting
        case pairing(YTZeroDeviceAuth.Code)
        case done(InstanceConfig)
    }

    public var urlText = ""
    public private(set) var step: Step = .enterURL
    public private(set) var error: String?

    @ObservationIgnored private let instances: InstanceStore
    @ObservationIgnored private let secrets: any SecretStore
    @ObservationIgnored private let detector: InstanceDetector
    @ObservationIgnored private let deviceName: String
    @ObservationIgnored private let onAdded: (InstanceConfig) -> Void

    public init(instances: InstanceStore, secrets: any SecretStore, detector: InstanceDetector = InstanceDetector(),
                deviceName: String, onAdded: @escaping (InstanceConfig) -> Void) {
        self.instances = instances
        self.secrets = secrets
        self.detector = detector
        self.deviceName = deviceName
        self.onAdded = onAdded
    }

    public static func tokenKey(for instance: UUID) -> String { "ytzero.token.\(instance.uuidString)" }

    public func submit() async {
        error = nil
        step = .detecting
        do {
            let found = try await detector.detect(urlText)
            let config = InstanceConfig(kind: found.kind, displayName: found.apiURL.host() ?? found.apiURL.absoluteString,
                                        apiURL: found.apiURL)
            if found.kind == .ytZero {
                try await pair(config)
            } else {
                try save(config)
            }
        } catch {
            self.error = Self.message(for: error)
            step = .enterURL
        }
    }

    public func cancelPairing() {
        step = .enterURL
    }

    private func pair(_ config: InstanceConfig) async throws {
        let auth = YTZeroDeviceAuth(instanceURL: config.apiURL)
        let code = try await auth.start(deviceName: deviceName)
        step = .pairing(code)
        guard let token = try await auth.waitForApproval(code) else {
            // Cancelled (step changed) or expired.
            if case .pairing = step {
                error = String(localized: "The pairing code expired. Try again.")
                step = .enterURL
            }
            return
        }
        guard case .pairing = step else { return }
        secrets.setSecret(token, for: Self.tokenKey(for: config.id))
        try save(config)
    }

    private func save(_ config: InstanceConfig) throws {
        try instances.add(config)
        step = .done(config)
        onAdded(config)
    }

    static func message(for error: Error) -> String {
        switch error {
        case InstanceDetector.Failure.invalidURL:
            String(localized: "That doesn't look like a web address.")
        case InstanceDetector.Failure.unreachable:
            String(localized: "Couldn't reach that address. Check it and your connection.")
        case InstanceDetector.Failure.unrecognised:
            String(localized: "That isn't a Piped API, Invidious or YT Zero instance. For Piped, use the API address, not the website.")
        default:
            String(localized: "Something went wrong: \(error.localizedDescription)")
        }
    }
}
