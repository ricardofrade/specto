import Foundation

/// The one seam between adapters and the network, so decoding is tested against
/// recorded fixtures and contract tests swap in the real thing.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SourceError.http(status: -1) }
            return (data, http)
        } catch let error as URLError {
            throw SourceError.network(error)
        }
    }
}

/// Shared request/decoding plumbing for adapters.
struct APIRequester: Sendable {
    let baseURL: URL
    let client: any HTTPClient
    /// Turns a non-2xx response into a `SourceError`; each backend reports failures differently.
    var mapError: @Sendable (_ status: Int, _ body: Data) -> SourceError = { status, _ in .http(status: status) }
    var timeout: TimeInterval = 15
    var headers: [String: String] = [:]

    init(baseURL: URL, client: any HTTPClient,
         mapError: @escaping @Sendable (_ status: Int, _ body: Data) -> SourceError = { status, _ in .http(status: status) },
         headers: [String: String] = [:]) {
        self.baseURL = baseURL
        self.client = client
        self.mapError = mapError
        self.headers = headers
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        let data = try await getData(path, query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SourceError.decoding("\(path): \(error)")
        }
    }

    func getData(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        try await send(request(path, query: query))
    }

    func post<T: Decodable>(_ path: String, json body: some Encodable, as type: T.Type = T.self) async throws -> T {
        var request = try request(path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let data = try await send(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SourceError.decoding("\(path): \(error)")
        }
    }

    func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET") throws -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw SourceError.decoding("Bad URL for \(path)") }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await client.data(for: request)
        switch response.statusCode {
        case 200..<300:
            return data
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init).map(Duration.seconds)
            throw SourceError.rateLimited(retryAfter: retryAfter)
        default:
            throw mapError(response.statusCode, data)
        }
    }
}
