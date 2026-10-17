import Foundation

/// Adapter for a PeerTube server (ADR 0016). Its IDs carry the server (`pt:<host>:…`), and it
/// declines anyone else's content, so the router sends PeerTube requests here and YouTube's to
/// Piped, Invidious or YT Zero.
///
/// - Streams: the server's HLS playlist (AVPlayer and mpv play it as is), with a plain MP4 file
///   as the fallback. Media comes straight from PeerTube servers, never from Google, so the
///   "through the instance's proxy" rule (googlevideo's IP binding) doesn't apply.
public struct PeerTubeSource: VideoSource {
    public let instance: InstanceConfig
    public let capabilities: SourceCapabilities = [.search, .trending, .trendingCategories, .channel, .comments,
                                                   .streams, .subscriptions, .playlists]
    private let api: APIRequester
    private let server: String
    /// With a YouTube instance also added, search and Explore's main list stay YouTube's;
    /// PeerTube answers its own content, and Explore's PeerTube list.
    private let servesGeneralQueries: Bool

    public init(instance: InstanceConfig, servesGeneralQueries: Bool = true,
                client: any HTTPClient = URLSessionHTTPClient()) {
        self.instance = instance
        self.servesGeneralQueries = servesGeneralQueries
        server = instance.apiURL.host() ?? instance.apiURL.absoluteString
        api = APIRequester(baseURL: instance.apiURL, client: client, mapError: Self.mapError)
    }

    private var base: URL { instance.apiURL }
    private static let pageSize = 30

    // MARK: Discovery

    public func search(_ query: String, cursor: String?) async throws -> Page<VideoSummary> {
        let page = try await search(query, filter: .videos, cursor: cursor)
        return Page(items: page.items.compactMap { if case .video(let video) = $0 { video } else { nil } },
                    nextCursor: page.nextCursor)
    }

    public func search(_ query: String, filter: SearchFilter, cursor: String?) async throws -> Page<SearchResult> {
        guard servesGeneralQueries else { throw SourceError.belongsElsewhere }
        let start = Int(cursor ?? "") ?? 0
        let query = [URLQueryItem(name: "search", value: query)] + Self.window(start)
        switch filter {
        case .videos:
            let list: PeerTubeDTO.List<PeerTubeDTO.Video> = try await api.get("api/v1/search/videos", query: query)
            return page(list, start: start) { $0.summary(server: server, base: base).map(SearchResult.video) }
        case .channels:
            let list: PeerTubeDTO.List<PeerTubeDTO.Channel> = try await api.get("api/v1/search/video-channels", query: query)
            return page(list, start: start) { $0.summary(server: server, base: base).map(SearchResult.channel) }
        case .playlists:
            let list: PeerTubeDTO.List<PeerTubeDTO.Playlist> = try await api.get("api/v1/search/video-playlists", query: query)
            return page(list, start: start) { $0.summary(server: server, base: base).map(SearchResult.playlist) }
        }
    }

    /// PeerTube has none; beside a YouTube front-end, step aside so its suggestions come through.
    public func suggestions(for query: String) async throws -> [String] {
        guard servesGeneralQueries else { throw SourceError.belongsElsewhere }
        return []
    }

    public func trending(region: String?) async throws -> [VideoSummary] {
        try await trending(region: region, category: .all)
    }

    /// The server's trending list; Gaming is PeerTube's category 7. Region doesn't apply.
    public func trending(region: String?, category: TrendingCategory) async throws -> [VideoSummary] {
        guard servesGeneralQueries || category == .peerTube else { throw SourceError.belongsElsewhere }
        var query = [URLQueryItem(name: "sort", value: "-trending"), URLQueryItem(name: "count", value: "40")]
        if category == .gaming { query.append(.init(name: "categoryOneOf", value: "7")) }
        let list: PeerTubeDTO.List<PeerTubeDTO.Video> = try await api.get("api/v1/videos", query: query)
        return (list.data ?? []).compactMap { $0.summary(server: server, base: base) }
    }

    // MARK: Channels

    public func channel(_ id: ChannelID, cursor: String?) async throws -> ChannelPage {
        let handle = try mine(id)
        let start = Int(cursor ?? "") ?? 0
        async let videos: PeerTubeDTO.List<PeerTubeDTO.Video> = api.get(
            "api/v1/video-channels/\(handle)/videos", query: [.init(name: "sort", value: "-publishedAt")] + Self.window(start))
        async let info: PeerTubeDTO.Channel? = cursor == nil ? api.get("api/v1/video-channels/\(handle)") : nil
        let (list, channel) = try await (videos, info)
        return ChannelPage(id: id, name: channel?.displayName ?? channel?.name ?? "",
                           avatar: channel?.avatars?.compactMap { $0.thumbnail(base: base) }.max { $0.width < $1.width },
                           banner: channel?.banners?.compactMap { $0.thumbnail(base: base) }.max { $0.width < $1.width },
                           videos: page(list, start: start) { $0.summary(server: server, base: base) })
    }

    public func channelPlaylists(_ id: ChannelID, cursor: String?) async throws -> Page<PlaylistSummary> {
        let handle = try mine(id)
        let start = Int(cursor ?? "") ?? 0
        let list: PeerTubeDTO.List<PeerTubeDTO.Playlist> = try await api.get(
            "api/v1/video-channels/\(handle)/video-playlists", query: Self.window(start))
        return page(list, start: start) { $0.summary(server: server, base: base) }
    }

    /// PeerTube has no Shorts.
    public func channelShorts(_ id: ChannelID, cursor: String?) async throws -> Page<VideoSummary> {
        _ = try mine(id)
        return Page(items: [], nextCursor: nil)
    }

    /// Each channel's latest uploads, a few channels at a time.
    public func feed(for channels: [ChannelID]) async throws -> [VideoSummary] {
        let handles = channels.compactMap { $0.peerTube?.host == server ? $0.peerTube?.handle : nil }
        guard !handles.isEmpty else { throw SourceError.belongsElsewhere }
        var videos: [VideoSummary] = []
        for batch in stride(from: 0, to: handles.count, by: 6).map({ Array(handles[$0..<min($0 + 6, handles.count)]) }) {
            try await withThrowingTaskGroup(of: [VideoSummary].self) { group in
                for handle in batch {
                    group.addTask {
                        // One missing channel shouldn't sink the feed.
                        let list: PeerTubeDTO.List<PeerTubeDTO.Video>? = try? await api.get(
                            "api/v1/video-channels/\(handle)/videos",
                            query: [.init(name: "sort", value: "-publishedAt"), .init(name: "count", value: "15")])
                        return (list?.data ?? []).compactMap { $0.summary(server: server, base: base) }
                    }
                }
                for try await items in group { videos += items }
            }
        }
        return videos
    }

    // MARK: Watching

    public func watchPage(for id: VideoID) async throws -> WatchPage {
        let uuid = try mine(id)
        let video: PeerTubeDTO.Video = try await api.get("api/v1/videos/\(uuid)")
        // Extras that older servers lack or that may fail: never fatal.
        async let captions: PeerTubeDTO.List<PeerTubeDTO.Caption>? = try? api.get("api/v1/videos/\(uuid)/captions")
        async let boards: PeerTubeDTO.Storyboards? = try? api.get("api/v1/videos/\(uuid)/storyboards")
        async let related = moreFromChannel(video.channel?.handle)
        let (captionList, storyboards, more) = await (captions, boards, related)

        guard let summary = video.summary(server: server, base: base) else { throw SourceError.decoding("video") }
        let details = VideoDetails(summary: summary, description: video.description ?? "", likeCount: video.likes,
                                   related: (more?.data ?? []).compactMap { $0.summary(server: server, base: base) }
                                       .filter { $0.id != id },
                                   channelAvatar: video.channel?.summary(server: server, base: base)?.avatar)
        // Web videos: the largest MP4 up to 1080p (resolution 0 is audio only).
        let muxed = (video.files ?? [])
            .filter { ($0.resolution?.id ?? 0) > 0 && ($0.resolution?.id ?? 0) <= 1080 }
            .max { ($0.resolution?.id ?? 0) < ($1.resolution?.id ?? 0) }
            .flatMap { PeerTubeDTO.absolute($0.fileUrl, base: base) }
        let manifest = StreamManifest(
            videoID: id, videoStreams: [], audioStreams: [],
            hlsURL: video.streamingPlaylists?.first.flatMap { PeerTubeDTO.absolute($0.playlistUrl, base: base) },
            muxedURL: muxed,
            captions: (captionList?.data ?? []).compactMap { caption in
                guard let url = PeerTubeDTO.absolute(caption.fileUrl ?? caption.captionPath, base: base) else { return nil }
                return CaptionTrack(url: url, language: caption.language?.id ?? "", label: caption.language?.label ?? "",
                                    isAutoGenerated: false)
            },
            storyboards: (storyboards?.storyboards ?? []).compactMap { Self.storyboard($0, base: base, duration: video.duration) },
            chapters: [],
            expiresAt: nil)
        return WatchPage(details: details, manifest: manifest)
    }

    /// "Up next" for PeerTube: the channel's latest (the API has no recommendations).
    private func moreFromChannel(_ handle: String?) async -> PeerTubeDTO.List<PeerTubeDTO.Video>? {
        guard let handle else { return nil }
        return try? await api.get("api/v1/video-channels/\(handle)/videos",
                                  query: [.init(name: "sort", value: "-publishedAt"), .init(name: "count", value: "16")])
    }

    public func comments(for id: VideoID, cursor: String?) async throws -> Page<Comment> {
        let uuid = try mine(id)
        // A thread's replies: its tree, flattened one level.
        if let cursor, cursor.hasPrefix("thread:") {
            let thread: PeerTubeDTO.Thread = try await api.get("api/v1/videos/\(uuid)/comment-threads/\(cursor.dropFirst(7))")
            return Page(items: (thread.children ?? []).compactMap { $0.comment.flatMap(Self.comment) }, nextCursor: nil)
        }
        let start = Int(cursor ?? "") ?? 0
        let list: PeerTubeDTO.List<PeerTubeDTO.Comment> = try await api.get(
            "api/v1/videos/\(uuid)/comment-threads", query: [.init(name: "sort", value: "-createdAt")] + Self.window(start))
        return page(list, start: start) { Self.comment($0) }
    }

    public func playlist(_ id: PlaylistID, cursor: String?) async throws -> PlaylistPage {
        guard let ref = id.peerTube, ref.host == server else { throw SourceError.belongsElsewhere }
        let start = Int(cursor ?? "") ?? 0
        async let info: PeerTubeDTO.Playlist = api.get("api/v1/video-playlists/\(ref.uuid)")
        async let elements: PeerTubeDTO.List<PeerTubeDTO.PlaylistElement> = api.get(
            "api/v1/video-playlists/\(ref.uuid)/videos", query: Self.window(start))
        let (playlist, list) = try await (info, elements)
        return PlaylistPage(id: id, title: playlist.displayName ?? "", channelName: playlist.videoChannel?.displayName,
                            videoCount: playlist.videosLength,
                            videos: page(list, start: start) { $0.video?.summary(server: server, base: base) })
    }

    public func healthCheck() async -> HealthSample {
        let start = ContinuousClock.now
        do {
            let config: PeerTubeDTO.Config = try await api.get("api/v1/config")
            return HealthSample(instanceID: instance.id, isHealthy: config.serverVersion != nil,
                                latency: ContinuousClock.now - start)
        } catch {
            return HealthSample(instanceID: instance.id, isHealthy: false, latency: nil)
        }
    }

    // MARK: Helpers

    /// The video's UUID or the channel's handle on this server; anything else is another's.
    private func mine(_ id: VideoID) throws -> String {
        guard let ref = id.peerTube, ref.host == server else { throw SourceError.belongsElsewhere }
        return ref.uuid
    }

    private func mine(_ id: ChannelID) throws -> String {
        guard let ref = id.peerTube, ref.host == server else { throw SourceError.belongsElsewhere }
        return ref.handle
    }

    private static func window(_ start: Int) -> [URLQueryItem] {
        [.init(name: "start", value: String(start)), .init(name: "count", value: String(pageSize))]
    }

    /// A page with an offset cursor while more remain.
    private func page<Item, Result>(_ list: PeerTubeDTO.List<Item>, start: Int, _ transform: (Item) -> Result?) -> Page<Result> {
        let items = list.data ?? []
        let next = start + items.count
        return Page(items: items.compactMap(transform),
                    nextCursor: !items.isEmpty && next < (list.total ?? 0) ? String(next) : nil)
    }

    private static func comment(_ comment: PeerTubeDTO.Comment) -> Comment? {
        guard let id = comment.id, comment.isDeleted != true else { return nil }
        let replies = comment.totalReplies ?? 0
        return Comment(id: String(id), authorName: comment.account?.displayName ?? comment.account?.name ?? "",
                       authorChannelID: nil, text: HTMLText.plain(comment.text ?? ""), likeCount: nil,
                       publishedAt: comment.createdAt.flatMap(PeerTubeDTO.date), publishedText: nil, isPinned: false,
                       replyCount: replies, repliesCursor: replies > 0 ? "thread:\(id)" : nil)
    }

    /// One sprite sheet; frames every `spriteDuration` seconds, up to the video's length.
    private static func storyboard(_ board: PeerTubeDTO.Storyboards.Board, base: URL, duration: Int?) -> Storyboard? {
        guard let url = PeerTubeDTO.absolute(board.fileUrl ?? board.storyboardPath, base: base),
              let width = board.spriteWidth, let height = board.spriteHeight, width > 0, height > 0,
              let totalWidth = board.totalWidth, let totalHeight = board.totalHeight else { return nil }
        let columns = totalWidth / width, rows = totalHeight / height
        let interval = max(1, board.spriteDuration ?? 1)
        let frames = min(columns * rows, max(1, (duration ?? columns * rows * interval) / interval))
        return Storyboard(pages: [url], frameWidth: width, frameHeight: height, columns: columns, rows: rows,
                          frameCount: frames, intervalMilliseconds: interval * 1000)
    }

    static func mapError(status: Int, body: Data) -> SourceError {
        status == 404 ? .unavailable(reason: nil) : .http(status: status)
    }
}
