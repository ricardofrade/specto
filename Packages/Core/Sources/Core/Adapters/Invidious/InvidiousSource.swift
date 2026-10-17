import Foundation

/// Adapter for an Invidious instance (`/api/v1`, always `local=true` so streams are proxied).
/// Shapes and quirks: `Tests/CoreTests/Fixtures/invidious` and `docs/adr/0002`.
public struct InvidiousSource: VideoSource {
    public let instance: InstanceConfig
    public let capabilities: SourceCapabilities = [.search, .trending, .channel, .comments, .streams,
                                                   .subscriptions, .playlists]
    private let api: APIRequester

    public init(instance: InstanceConfig, client: any HTTPClient = URLSessionHTTPClient()) {
        self.instance = instance
        self.api = APIRequester(baseURL: instance.apiURL, client: client, mapError: InvidiousSource.mapError)
    }

    public func search(_ query: String, cursor: String?) async throws -> Page<VideoSummary> {
        let page = try await search(query, filter: .videos, cursor: cursor)
        return Page(items: page.items.compactMap { if case .video(let video) = $0 { video } else { nil } },
                    nextCursor: page.nextCursor)
    }

    public func search(_ query: String, filter: SearchFilter, cursor: String?) async throws -> Page<SearchResult> {
        let page = cursor.flatMap(Int.init) ?? 1
        let type = switch filter {
        case .videos: "video"
        case .channels: "channel"
        case .playlists: "playlist"
        }
        let items: [InvidiousDTO.Item] = try await api.get("api/v1/search", query: [
            .init(name: "q", value: query), .init(name: "type", value: type), .init(name: "page", value: "\(page)"),
        ])
        let instance = self.instance.apiURL
        return Page(items: items.compactMap { $0.searchResult(instance: instance) },
                    nextCursor: items.isEmpty ? nil : "\(page + 1)")
    }

    public func suggestions(for query: String) async throws -> [String] {
        let result: InvidiousDTO.Suggestions = try await api.get("api/v1/search/suggestions", query: [.init(name: "q", value: query)])
        return result.suggestions ?? []
    }

    public func trending(region: String?) async throws -> [VideoSummary] {
        let region = region ?? Locale.current.region?.identifier ?? "US"
        let items: [InvidiousDTO.Item] = try await api.get("api/v1/trending", query: [.init(name: "region", value: region)])
        return items.compactMap(\.videoSummary)
    }

    public func channel(_ id: ChannelID, cursor: String?) async throws -> ChannelPage {
        var query: [URLQueryItem] = []
        if let cursor { query.append(.init(name: "continuation", value: cursor)) }
        async let videosPage: InvidiousDTO.ChannelVideos = api.get("api/v1/channels/\(id.rawValue)/videos", query: query)
        // Name and avatar live on the channel home; only needed for the first page.
        async let home: InvidiousDTO.ChannelHome? = cursor == nil ? api.get("api/v1/channels/\(id.rawValue)") : nil
        let (videos, channel) = try await (videosPage, home)
        return ChannelPage(id: id, name: channel?.author ?? "",
                           avatar: channel?.authorThumbnails?.map { $0.thumbnail(instance: instance.apiURL) }
                               .max { $0.width < $1.width },
                           videos: Page(items: (videos.videos ?? []).compactMap(\.videoSummary),
                                        nextCursor: videos.continuation))
    }

    public func watchPage(for id: VideoID) async throws -> WatchPage {
        let video: InvidiousDTO.Video = try await api.get("api/v1/videos/\(id.rawValue)",
                                                          query: [.init(name: "local", value: "true")])
        return video.watchPage(id: id, instance: instance.apiURL)
    }

    /// No batched feed without an account: one Atom feed per channel (one cheap upstream
    /// request each, exact timestamps, no durations), a few at a time.
    public func feed(for channels: [ChannelID]) async throws -> [VideoSummary] {
        var videos: [VideoSummary] = []
        var failures = 0
        try await withThrowingTaskGroup(of: [VideoSummary]?.self) { group in
            var pending = channels.makeIterator()
            func next() -> Bool {
                guard let channel = pending.next() else { return false }
                group.addTask {
                    do {
                        let xml = try await api.getData("feed/channel/\(channel.rawValue)")
                        return ChannelFeedParser.parse(xml)
                    } catch let error as SourceError where !error.isRetryableElsewhere {
                        return []      // A removed channel shouldn't sink the whole feed.
                    } catch {
                        return nil
                    }
                }
                return true
            }
            for _ in 0..<6 where next() {}
            while let result = try await group.next() {
                if let result { videos += result } else { failures += 1 }
                _ = next()
            }
        }
        if failures == channels.count, !channels.isEmpty { throw SourceError.http(status: 502) }
        return videos.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    public func comments(for id: VideoID, cursor: String?) async throws -> Page<Comment> {
        var query: [URLQueryItem] = []
        if let cursor { query.append(.init(name: "continuation", value: cursor)) }
        let page: InvidiousDTO.CommentsPage = try await api.get("api/v1/comments/\(id.rawValue)", query: query)
        return Page(items: (page.comments ?? []).map(\.comment), nextCursor: page.continuation)
    }

    /// Pages overlap (each holds up to 200 items plus 50 of look-back), so the cursor is the next
    /// index and earlier items are dropped.
    public func playlist(_ id: PlaylistID, cursor: String?) async throws -> PlaylistPage {
        let start = cursor.flatMap(Int.init) ?? 0
        let playlist: InvidiousDTO.Playlist = try await api.get("api/v1/playlists/\(id.rawValue)",
                                                                query: [.init(name: "index", value: "\(start)")])
        let fresh = (playlist.videos ?? []).filter { ($0.index ?? 0) >= start }
        let last = fresh.compactMap(\.index).max()
        let next = last.map { $0 + 1 }.flatMap { $0 < (playlist.videoCount ?? 0) ? "\($0)" : nil }
        return PlaylistPage(id: id, title: playlist.title ?? "", channelName: playlist.author,
                            videoCount: playlist.videoCount, videos: Page(items: fresh.compactMap(\.videoSummary),
                                                                          nextCursor: next))
    }

    public func channelPlaylists(_ id: ChannelID, cursor: String?) async throws -> Page<PlaylistSummary> {
        var query: [URLQueryItem] = []
        if let cursor { query.append(.init(name: "continuation", value: cursor)) }
        let page: InvidiousDTO.ChannelPlaylists = try await api.get("api/v1/channels/\(id.rawValue)/playlists", query: query)
        let instance = self.instance.apiURL
        return Page(items: (page.playlists ?? []).compactMap { $0.playlistSummary(instance: instance) },
                    nextCursor: page.continuation.flatMap { $0.isEmpty ? nil : $0 })
    }

    /// `/stats` makes no upstream call, so it shows the instance is up, not that YouTube answers.
    public func healthCheck() async -> HealthSample {
        let start = ContinuousClock.now
        do {
            let stats: InvidiousDTO.Stats = try await api.get("api/v1/stats")
            return HealthSample(instanceID: instance.id, isHealthy: stats.software?.name == "invidious",
                                latency: ContinuousClock.now - start)
        } catch {
            return HealthSample(instanceID: instance.id, isHealthy: false, latency: nil)
        }
    }

    /// Errors are `{"error": "…"}`: 404 for missing content, 500 for upstream failures with
    /// YouTube's reason in the text.
    static func mapError(status: Int, body: Data) -> SourceError {
        let message = (try? JSONDecoder().decode(InvidiousDTO.ErrorBody.self, from: body))?.error
        let text = message.map(HTMLText.plain)
        if status == 404 { return .unavailable(reason: text) }
        guard let lower = text?.lowercased() else { return .http(status: status) }
        if lower.contains("not a bot") || lower.contains("status code 429") || lower.contains("trying to block") {
            return .blockedUpstream
        }
        if lower.contains("private") || lower.contains("unavailable") || lower.contains("confirm your age")
            || lower.contains("not available in your country") {
            return .unavailable(reason: text)
        }
        return .http(status: status)
    }
}
