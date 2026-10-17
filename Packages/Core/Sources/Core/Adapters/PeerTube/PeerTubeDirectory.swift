import Foundation

/// The public PeerTube servers in joinpeertube.org's index (the list at
/// instances.joinpeertube.org), read live, so it's never out of date: for people without a server
/// of their own (ADR 0016). Healthy and non-NSFW only; sortable, searchable and paged.
public struct PeerTubeDirectory: Sendable {
    public struct Server: Identifiable, Hashable, Sendable {
        public let host: String
        public let name: String
        public let summary: String?
        public let videoCount: Int
        public let languages: [String]
        /// "1,234 videos", formatted once.
        public let videoCountText: String
        public var id: String { host }

        init(host: String, name: String, summary: String?, videoCount: Int, languages: [String]) {
            self.host = host
            self.name = name
            self.summary = summary
            self.videoCount = videoCount
            self.languages = languages
            videoCountText = String(localized: "\(videoCount) videos")
        }
    }

    private let client: any HTTPClient
    static let index = URL(string: "https://instances.joinpeertube.org/api/v1/instances")!

    public init(client: any HTTPClient = URLSessionHTTPClient()) {
        self.client = client
    }

    /// How the index orders its list.
    public enum Sort: String, CaseIterable, Sendable {
        case mostVideos = "-totalLocalVideos"
        case mostUsers = "-totalUsers"
        case newest = "-createdAt"
    }

    /// One page of the index: healthy, non-NSFW servers matching `search`, in `sort` order, the
    /// person's language first within the page. `total` is what the index has in all.
    public func servers(sort: Sort = .mostVideos, search: String? = nil, start: Int = 0, count: Int = 40,
                        language: String? = Locale.current.language.languageCode?.identifier)
        async throws -> (servers: [Server], total: Int) {
        var components = URLComponents(url: Self.index, resolvingAgainstBaseURL: false)!
        var query: [URLQueryItem] = [.init(name: "start", value: String(start)), .init(name: "count", value: String(count)),
                                     .init(name: "sort", value: sort.rawValue), .init(name: "healthy", value: "true")]
        if let search = search?.trimmingCharacters(in: .whitespaces), !search.isEmpty {
            query.append(.init(name: "search", value: search))
        }
        components.queryItems = query
        let (data, response) = try await client.data(for: URLRequest(url: components.url!, timeoutInterval: 15))
        guard (200..<300).contains(response.statusCode) else { throw SourceError.http(status: response.statusCode) }
        struct Entry: Decodable {
            let host: String?
            let name: String?
            let shortDescription: String?
            let totalLocalVideos: Int?
            let languages: [String]?
            let isNSFW: Bool?
        }
        let list = try JSONDecoder().decode(PeerTubeDTO.List<Entry>.self, from: data)
        let servers = (list.data ?? []).compactMap { entry -> Server? in
            guard let host = entry.host, entry.isNSFW != true, (entry.totalLocalVideos ?? 0) > 0 else { return nil }
            return Server(host: host, name: entry.name ?? host,
                          summary: entry.shortDescription.flatMap { $0.isEmpty ? nil : $0 },
                          videoCount: entry.totalLocalVideos ?? 0, languages: entry.languages ?? [])
        }
        // A stable partition: the person's language first, the index's order kept.
        let speaks = servers.filter { language != nil && $0.languages.contains(language!) }
        let others = servers.filter { language == nil || !$0.languages.contains(language!) }
        return (speaks + others, list.total ?? 0)
    }
}
