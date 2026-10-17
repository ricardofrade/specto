import Foundation

/// Adapter for a Piped backend (`docs/adr/0002`; shapes in `Tests/CoreTests/Fixtures/piped`).
public struct PipedSource: VideoSource {
    public let instance: InstanceConfig
    public let capabilities: SourceCapabilities = [.search, .trending, .channel, .comments, .streams,
                                                   .subscriptions, .playlists]
    private let api: APIRequester

    public init(instance: InstanceConfig, client: any HTTPClient = URLSessionHTTPClient()) {
        self.instance = instance
        self.api = APIRequester(baseURL: instance.apiURL, client: client, mapError: PipedSource.mapError)
    }

    // MARK: VideoSource

    public func search(_ query: String, cursor: String?) async throws -> Page<VideoSummary> {
        let page = try await search(query, filter: .videos, cursor: cursor)
        return Page(items: page.items.compactMap { if case .video(let video) = $0 { video } else { nil } },
                    nextCursor: page.nextCursor)
    }

    public func search(_ query: String, filter: SearchFilter, cursor: String?) async throws -> Page<SearchResult> {
        var parameters = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "filter", value: filter.rawValue)]
        if let cursor { parameters.append(.init(name: "nextpage", value: cursor)) }
        let page: PipedDTO.SearchResults = try await api.get(cursor == nil ? "search" : "nextpage/search", query: parameters)
        return Page(items: (page.items ?? []).compactMap(\.searchResult), nextCursor: Self.cursor(page.nextpage))
    }

    public func suggestions(for query: String) async throws -> [String] {
        try await api.get("suggestions", query: [.init(name: "query", value: query)])
    }

    public func trending(region: String?) async throws -> [VideoSummary] {
        let region = region ?? Locale.current.region?.identifier ?? "US"
        let items: [PipedDTO.ContentItem] = try await api.get("trending", query: [.init(name: "region", value: region)])
        return items.compactMap(\.videoSummary)
    }

    public func channel(_ id: ChannelID, cursor: String?) async throws -> ChannelPage {
        if let cursor {
            let page: PipedDTO.StreamsPage = try await api.get("nextpage/channel/\(id.rawValue)",
                                                               query: [.init(name: "nextpage", value: cursor)])
            return ChannelPage(id: id, name: "", avatar: nil,
                               videos: Page(items: (page.relatedStreams ?? []).compactMap(\.videoSummary),
                                            nextCursor: Self.cursor(page.nextpage)))
        }
        let channel: PipedDTO.Channel = try await api.get("channel/\(id.rawValue)")
        return ChannelPage(id: id, name: channel.name ?? "", avatar: channel.avatarUrl.flatMap(Thumbnail.unsized),
                           videos: Page(items: (channel.relatedStreams ?? []).compactMap(\.videoSummary),
                                        nextCursor: Self.cursor(channel.nextpage)))
    }

    public func watchPage(for id: VideoID) async throws -> WatchPage {
        let streams: PipedDTO.Streams = try await api.get("streams/\(id.rawValue)")
        return streams.watchPage(id: id)
    }

    public func feed(for channels: [ChannelID]) async throws -> [VideoSummary] {
        // The instance only returns channels it already tracks, newest first; chunk long lists
        // to keep URLs short. A channel new to the instance fills in on a later refresh.
        let chunks = stride(from: 0, to: channels.count, by: 50).map { Array(channels[$0..<min($0 + 50, channels.count)]) }
        let pages = try await withThrowingTaskGroup(of: [VideoSummary].self) { group in
            for chunk in chunks {
                group.addTask {
                    let ids = chunk.map(\.rawValue).joined(separator: ",")
                    let items: [PipedDTO.ContentItem] = try await api.get("feed/unauthenticated",
                                                                          query: [.init(name: "channels", value: ids)])
                    return items.compactMap(\.videoSummary)
                }
            }
            return try await group.reduce(into: []) { $0 += $1 }
        }
        return pages.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    public func comments(for id: VideoID, cursor: String?) async throws -> Page<Comment> {
        let page: PipedDTO.CommentsPage = if let cursor {
            try await api.get("nextpage/comments/\(id.rawValue)", query: [.init(name: "nextpage", value: cursor)])
        } else {
            try await api.get("comments/\(id.rawValue)")
        }
        return Page(items: (page.comments ?? []).map(\.comment), nextCursor: Self.cursor(page.nextpage))
    }

    public func playlist(_ id: PlaylistID, cursor: String?) async throws -> PlaylistPage {
        if let cursor {
            let page: PipedDTO.StreamsPage = try await api.get("nextpage/playlists/\(id.rawValue)",
                                                               query: [.init(name: "nextpage", value: cursor)])
            return PlaylistPage(id: id, title: "", channelName: nil, videoCount: nil,
                                videos: Page(items: (page.relatedStreams ?? []).compactMap(\.videoSummary),
                                             nextCursor: Self.cursor(page.nextpage)))
        }
        let playlist: PipedDTO.Playlist = try await api.get("playlists/\(id.rawValue)")
        return PlaylistPage(id: id, title: playlist.name ?? "", channelName: playlist.uploader,
                            videoCount: playlist.videos.flatMap { $0 >= 0 ? $0 : nil },
                            videos: Page(items: (playlist.relatedStreams ?? []).compactMap(\.videoSummary),
                                         nextCursor: Self.cursor(playlist.nextpage)))
    }

    /// The playlists tab needs the channel's tab `data` on every page, so the cursor carries it
    /// along with Piped's `nextpage`.
    public func channelPlaylists(_ id: ChannelID, cursor: String?) async throws -> Page<PlaylistSummary> {
        let state: TabCursor
        if let cursor, let decoded = try? JSONDecoder().decode(TabCursor.self, from: Data(cursor.utf8)) {
            state = decoded
        } else {
            let channel: PipedDTO.Channel = try await api.get("channel/\(id.rawValue)")
            guard let tab = channel.tabs?.first(where: { $0.name == "playlists" }) else { return Page(items: [], nextCursor: nil) }
            state = TabCursor(data: tab.data, nextpage: nil)
        }
        var query = [URLQueryItem(name: "data", value: state.data)]
        if let nextpage = state.nextpage { query.append(.init(name: "nextpage", value: nextpage)) }
        let page: PipedDTO.TabPage = try await api.get("channels/tabs", query: query)
        let next = Self.cursor(page.nextpage).flatMap { nextpage in
            (try? JSONEncoder().encode(TabCursor(data: state.data, nextpage: nextpage))).map { String(decoding: $0, as: UTF8.self) }
        }
        return Page(items: (page.content ?? []).compactMap(\.playlistSummary), nextCursor: next)
    }

    private struct TabCursor: Codable {
        let data: String
        let nextpage: String?
    }

    public func healthCheck() async -> HealthSample {
        let start = ContinuousClock.now
        do {
            let body = try await api.getData("healthcheck")
            let healthy = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "OK"
            return HealthSample(instanceID: instance.id, isHealthy: healthy, latency: ContinuousClock.now - start)
        } catch {
            return HealthSample(instanceID: instance.id, isHealthy: false, latency: nil)
        }
    }

    // MARK: Helpers

    /// Piped sends the opaque token back as-is; search's last page may be the string "null".
    static func cursor(_ token: String?) -> String? {
        guard let token, !token.isEmpty, token != "null" else { return nil }
        return token
    }

    /// Piped has no error codes: 400 `{error}` for bad requests, 500 `{error: <Java trace>, message}`
    /// for every upstream failure, so classify by the exception class on the trace's first line.
    static func mapError(status: Int, body: Data) -> SourceError {
        guard status == 500, let error = try? JSONDecoder().decode(PipedDTO.ErrorBody.self, from: body) else {
            return .http(status: status)
        }
        let trace = error.error ?? ""
        let reason = error.message ?? trace.components(separatedBy: "\n").first
        let blocked = ["SignInConfirmNotBotException", "ReCaptchaException"]
        let unavailable = ["ContentNotAvailableException", "PrivateContentException", "AgeRestrictedContentException",
                           "GeographicRestrictionException", "PaidContentException", "AccountTerminatedException",
                           "UnsupportedContentInCountryException", "YoutubeMusicPremiumContentException",
                           "ParsingException: JSON response is too short"]
        if blocked.contains(where: trace.contains) { return .blockedUpstream }
        if unavailable.contains(where: trace.contains) { return .unavailable(reason: reason) }
        return .http(status: status)
    }
}
