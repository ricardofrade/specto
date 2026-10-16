import Foundation

/// Adapter for a YT Zero instance: a subscriptions inbox with its own accounts, feed, watch
/// state and H.264/AAC playback (`docs/adr/0002`). Needs a Bearer token from `YTZeroDeviceAuth`.
public struct YTZeroSource: VideoSource, SubscriptionAccount {
    public let instance: InstanceConfig
    /// No `.subscriptions` (the batched public feed): its feed is the account's, via `accountFeed`.
    public let capabilities: SourceCapabilities = [.search, .channel, .comments, .streams]
    private let api: APIRequester
    private let images: YTZeroDTO.ImageProxy

    public init(instance: InstanceConfig, token: String, client: any HTTPClient = URLSessionHTTPClient()) {
        self.instance = instance
        self.api = APIRequester(baseURL: instance.apiURL, client: client, mapError: YTZeroSource.mapError,
                                headers: ["Authorization": "Bearer \(token)"])
        self.images = YTZeroDTO.ImageProxy(base: instance.apiURL)
    }

    // MARK: VideoSource

    /// YouTube search through the instance; one page only.
    public func search(_ query: String, cursor: String?) async throws -> Page<VideoSummary> {
        guard cursor == nil else { return Page(items: [], nextCursor: nil) }
        let response: YTZeroDTO.SearchResponse = try await api.get("api/search/youtube",
                                                                   query: [.init(name: "q", value: query)])
        let videos = (response.results ?? []).map { result in
            VideoSummary(id: VideoID(rawValue: result.videoId), title: result.title ?? "",
                         channelID: ChannelID(rawValue: result.channelId ?? ""),
                         channelName: result.channelTitle ?? "",
                         duration: result.duration.flatMap { YTZeroDTO.seconds($0.value) }.map { .seconds($0) },
                         publishedAt: nil, viewCount: result.viewCount,
                         thumbnails: result.thumbnail.flatMap(images.thumbnail).map { [$0] } ?? [])
        }
        return Page(items: videos, nextCursor: nil)
    }

    /// The instance's stored videos for one channel. Pages are 0-based offsets of 40.
    public func channel(_ id: ChannelID, cursor: String?) async throws -> ChannelPage {
        let page = cursor.flatMap(Int.init) ?? 0
        async let feed: YTZeroDTO.FeedResponse = api.get("api/feed", query: [
            .init(name: "channel", value: id.rawValue), .init(name: "status", value: "all"),
            .init(name: "shorts", value: "1"), .init(name: "page", value: "\(page)"), .init(name: "limit", value: "40"),
        ])
        async let info: YTZeroDTO.ChannelResponse? = page == 0 ? try? api.get("api/channels/\(id.rawValue)") : nil
        let (videos, channel) = try await (feed, info)
        let items = (videos.videos ?? []).map { $0.summary(images: images) }
        return ChannelPage(id: id, name: channel?.channel?.title ?? "",
                           avatar: channel?.channel?.thumbnail.flatMap(images.thumbnail),
                           videos: Page(items: items, nextCursor: items.count == 40 ? "\(page + 1)" : nil))
    }

    /// Details, then a playback ticket (HLS or a downloaded file, valid 15 minutes). A video the
    /// instance hasn't stored yet is imported first.
    public func watchPage(for id: VideoID) async throws -> WatchPage {
        let response: YTZeroDTO.VideoResponse
        do {
            response = try await api.get("api/videos/\(id.rawValue)")
        } catch SourceError.unavailable {
            var importRequest = try api.request("api/videos/\(id.rawValue)/info")
            importRequest.timeoutInterval = 45
            _ = try await api.send(importRequest)
            response = try await api.get("api/videos/\(id.rawValue)")
        }
        let ticket = try await playbackTicket(for: id)
        let summary = response.video.summary(images: images)
        let details = VideoDetails(summary: summary, description: response.video.description ?? "",
                                   likeCount: response.video.likes,
                                   related: (response.related ?? []).map { $0.summary(images: images) })
        guard let url = ticket.url.flatMap({ URL(string: $0, relativeTo: instance.apiURL)?.absoluteURL }) else {
            throw SourceError.decoding("Playback ticket without a URL")
        }
        let manifest = StreamManifest(
            videoID: id, videoStreams: [], audioStreams: [],
            hlsURL: ticket.content_type == "hls" ? url : nil,
            muxedURL: ticket.content_type == "progressive" ? url : nil,
            chapters: [],
            expiresAt: Date.now.addingTimeInterval(TimeInterval(ticket.expires_in ?? 900)))
        return WatchPage(details: details, manifest: manifest)
    }

    public func comments(for id: VideoID, cursor: String?) async throws -> Page<Comment> {
        guard cursor == nil else { return Page(items: [], nextCursor: nil) }
        let response: YTZeroDTO.CommentsResponse = try await api.get("api/videos/\(id.rawValue)/comments",
                                                                     query: [.init(name: "sort", value: "top")])
        let comments = (response.comments ?? []).filter { ($0.parent ?? "").isEmpty }.map { item in
            Comment(id: item.id ?? UUID().uuidString, authorName: item.author ?? "",
                    authorChannelID: item.authorId.map(ChannelID.init(rawValue:)), text: item.text ?? "",
                    likeCount: item.likeCount, publishedAt: nil, publishedText: item.timeText,
                    isPinned: item.isPinned?.value ?? false, replyCount: 0, repliesCursor: nil)
        }
        return Page(items: comments, nextCursor: nil)
    }

    public func healthCheck() async -> HealthSample {
        let start = ContinuousClock.now
        do {
            let health: YTZeroDTO.Health = try await api.get("api/health")
            return HealthSample(instanceID: instance.id, isHealthy: health.app == "ytzero" && health.status == "ok",
                                latency: ContinuousClock.now - start)
        } catch {
            return HealthSample(instanceID: instance.id, isHealthy: false, latency: nil)
        }
    }

    // MARK: SubscriptionAccount

    public func subscriptions() async throws -> [ChannelSummary] {
        let response: YTZeroDTO.ChannelsResponse = try await api.get("api/channels")
        return (response.channels ?? []).map {
            ChannelSummary(id: ChannelID(rawValue: $0.channel_id), name: $0.title ?? "",
                           avatar: $0.thumbnail.flatMap(images.thumbnail))
        }
    }

    public func follow(_ channel: ChannelID) async throws {
        try await setFollowed(true, channel)
    }

    public func unfollow(_ channel: ChannelID) async throws {
        try await setFollowed(false, channel)
    }

    public func accountFeed(page: Int) async throws -> Page<AccountVideo> {
        let limit = 100
        let response: YTZeroDTO.FeedResponse = try await api.get("api/feed", query: [
            .init(name: "page", value: "\(page)"), .init(name: "limit", value: "\(limit)"),
        ])
        let videos = (response.videos ?? []).map { video in
            let state = video.accountVideoState
            return AccountVideo(video: video.summary(images: images), resumePosition: state.resume,
                                isWatched: state.watched)
        }
        // Offset pages with no total: a full page means there may be more.
        return Page(items: videos, nextCursor: videos.count == limit ? "\(page + 1)" : nil)
    }

    public func saveProgress(_ position: Duration, duration: Duration, for id: VideoID) async throws {
        struct Body: Encodable { let position: Double; let duration: Double }
        let seconds = { (d: Duration) in Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }
        guard seconds(duration) > 0 else { return }
        var request = try api.request("api/videos/\(id.rawValue)/progress", method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(position: max(0, seconds(position)), duration: seconds(duration)))
        _ = try await api.send(request)
    }

    public func setWatched(_ watched: Bool, for id: VideoID) async throws {
        var request = try api.request("api/videos/\(id.rawValue)/complete", method: watched ? "POST" : "DELETE")
        if watched {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
        }
        _ = try await api.send(request)
    }

    // MARK: Private

    private func setFollowed(_ followed: Bool, _ channel: ChannelID) async throws {
        struct Body: Encodable { let followed: Bool }
        var request = try api.request("api/channels/\(channel.rawValue)/follow", method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(followed: followed))
        _ = try await api.send(request)
    }

    /// A downloaded file may still be converting: the server answers 202 `preparing` for a while.
    private func playbackTicket(for id: VideoID) async throws -> YTZeroDTO.Ticket {
        struct Empty: Encodable {}
        for _ in 0..<15 {
            let ticket: YTZeroDTO.Ticket = try await api.post("api/videos/\(id.rawValue)/playback-ticket", json: Empty())
            if ticket.preparing != true { return ticket }
            try await Task.sleep(for: .seconds(2))
        }
        throw SourceError.http(status: 202)
    }

    static func mapError(status: Int, body: Data) -> SourceError {
        let error = try? JSONDecoder().decode(YTZeroDTO.ErrorBody.self, from: body)
        switch status {
        case 404, 409: return .unavailable(reason: error?.error)
        case 503 where error?.code == "youtube_refused": return .blockedUpstream
        default: return .http(status: status)
        }
    }
}
