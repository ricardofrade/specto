import Foundation

/// Works out what a pasted URL is, so onboarding never asks "which kind of instance?".
public struct InstanceDetector: Sendable {
    public struct Detected: Sendable, Equatable {
        public let kind: SourceKind
        /// The API base to store (may differ from what was pasted, e.g. trailing paths removed).
        public let apiURL: URL
        public let version: String?
    }

    public enum Failure: Error, Equatable {
        case invalidURL
        /// Reachable, but not a Piped API, Invidious, YT Zero or PeerTube. A Piped *frontend* URL lands here.
        case unrecognised
        case unreachable
    }

    private let client: any HTTPClient

    public init(client: any HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    /// Accepts "host", "host/path" or full URLs; assumes https when no scheme is given.
    public static func normalise(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard var components = URLComponents(string: trimmed), let host = components.host, !host.isEmpty,
              components.scheme == "https" || components.scheme == "http" else { return nil }
        components.query = nil
        components.fragment = nil
        while components.path.hasSuffix("/") { components.path.removeLast() }
        return components.url
    }

    public func detect(_ text: String) async throws -> Detected {
        guard let url = Self.normalise(text) else { throw Failure.invalidURL }
        // All three probes run together; the first recognised answer wins.
        async let ytZero = probeYTZero(url)
        async let invidious = probeInvidious(url)
        async let piped = probePiped(url)
        async let peerTube = probePeerTube(url)
        let results = await [ytZero, invidious, piped, peerTube]
        if let found = results.compactMap({ $0.detected }).first { return found }
        if results.allSatisfy({ $0.unreachable }) { throw Failure.unreachable }
        throw Failure.unrecognised
    }

    private struct Probe: Sendable {
        var detected: Detected?
        var unreachable = false
    }

    private func probeYTZero(_ url: URL) async -> Probe {
        await probe(url, path: "api/health") { data in
            let health = try JSONDecoder().decode(YTZeroDTO.Health.self, from: data)
            return health.app == "ytzero" ? Detected(kind: .ytZero, apiURL: url, version: health.version) : nil
        }
    }

    private func probeInvidious(_ url: URL) async -> Probe {
        await probe(url, path: "api/v1/stats") { data in
            let stats = try JSONDecoder().decode(InvidiousDTO.Stats.self, from: data)
            return stats.software?.name == "invidious"
                ? Detected(kind: .invidious, apiURL: url, version: stats.software?.version) : nil
        }
    }

    /// PeerTube's `/api/v1/config` has its version and the server's name.
    private func probePeerTube(_ url: URL) async -> Probe {
        await probe(url, path: "api/v1/config") { data in
            let config = try JSONDecoder().decode(PeerTubeDTO.Config.self, from: data)
            return config.serverVersion != nil && config.instance != nil
                ? Detected(kind: .peerTube, apiURL: url, version: config.serverVersion) : nil
        }
    }

    /// Piped's API answers `/healthcheck` with "OK" and `/config` with its proxy settings.
    private func probePiped(_ url: URL) async -> Probe {
        let health = await probe(url, path: "healthcheck") { data in
            String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "OK"
                ? Detected(kind: .piped, apiURL: url, version: nil) : nil
        }
        guard health.detected != nil else { return health }
        struct Config: Decodable { let imageProxyUrl: String? }
        return await probe(url, path: "config") { data in
            (try JSONDecoder().decode(Config.self, from: data)).imageProxyUrl != nil
                ? Detected(kind: .piped, apiURL: url, version: nil) : nil
        }
    }

    private func probe(_ url: URL, path: String, _ recognise: (Data) throws -> Detected?) async -> Probe {
        var request = URLRequest(url: url.appending(path: path), timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await client.data(for: request)
            guard (200..<300).contains(response.statusCode) else { return Probe() }
            return Probe(detected: try? recognise(data))
        } catch {
            return Probe(unreachable: true)
        }
    }
}
