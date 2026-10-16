import Foundation
@testable import Core

/// Serves recorded responses: each route is "path" (or "path?query-substring") → (status, file or body).
final class FixtureClient: HTTPClient, @unchecked Sendable {
    struct Response {
        let status: Int
        let body: Data
    }

    // Guarded by `lock`.
    private var routes: [(match: String, response: Response)] = []
    private(set) var requests: [URLRequest] = []
    private let lock = NSLock()

    func on(_ match: String, status: Int = 200, fixture: String) {
        on(match, status: status, body: Self.fixture(fixture))
    }

    func on(_ match: String, status: Int = 200, body: Data) {
        lock.withLock { routes.append((match, Response(status: status, body: body))) }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let path = url.path
        let full = path + (url.query.map { "?" + $0 } ?? "")
        let response: Response? = lock.withLock {
            requests.append(request)
            // A route the path ends with beats one it merely contains; then the longest wins.
            func rank(_ match: String) -> (Int, Int) { (path.hasSuffix(match) ? 1 : 0, match.count) }
            return routes.filter { full.contains($0.match) }
                .max { rank($0.match) < rank($1.match) }?.response
        }
        guard let response else { throw URLError(.fileDoesNotExist, userInfo: [NSURLErrorFailingURLErrorKey: url]) }
        return (response.body, HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1",
                                               headerFields: ["Content-Type": "application/json"])!)
    }

    var requestedPaths: [String] {
        lock.withLock { requests.compactMap { $0.url?.path } }
    }

    static func fixture(_ name: String) -> Data {
        let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
        return try! Data(contentsOf: url)
    }
}

func instance(_ kind: SourceKind, _ url: String = "https://instance.example") -> InstanceConfig {
    InstanceConfig(kind: kind, displayName: kind.rawValue, apiURL: URL(string: url)!)
}
