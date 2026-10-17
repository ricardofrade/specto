import Foundation

/// PeerTube content is addressed per server, so its IDs carry the server: `pt:<host>:<id>`.
/// That keeps them apart from YouTube's, and lets the router send each request to the instance
/// that can answer it (ADR 0016).
public enum PeerTubeID {
    static let prefix = "pt:"

    static func make(host: String, id: String) -> String { "\(prefix)\(host):\(id)" }

    static func parse(_ raw: String) -> (host: String, id: String)? {
        guard raw.hasPrefix(prefix) else { return nil }
        let rest = raw.dropFirst(prefix.count)
        guard let colon = rest.firstIndex(of: ":") else { return nil }
        let host = String(rest[..<colon]), id = String(rest[rest.index(after: colon)...])
        return host.isEmpty || id.isEmpty ? nil : (host, id)
    }
}

public extension VideoID {
    static func peerTube(host: String, uuid: String) -> VideoID { VideoID(rawValue: PeerTubeID.make(host: host, id: uuid)) }
    /// The server and the video's UUID, for a PeerTube video; nil for YouTube's.
    var peerTube: (host: String, uuid: String)? { PeerTubeID.parse(rawValue).map { ($0.host, $0.id) } }
    var isPeerTube: Bool { peerTube != nil }
    /// Where to open or share it: YouTube's page, or the video's page on its PeerTube server.
    var webURL: URL? {
        if let peerTube { return URL(string: "https://\(peerTube.host)/w/\(peerTube.uuid)") }
        return URL(string: "https://www.youtube.com/watch?v=\(rawValue)")
    }
}

public extension ChannelID {
    /// `handle` is PeerTube's `name@host` for the channel.
    static func peerTube(host: String, handle: String) -> ChannelID { ChannelID(rawValue: PeerTubeID.make(host: host, id: handle)) }
    var peerTube: (host: String, handle: String)? { PeerTubeID.parse(rawValue).map { ($0.host, $0.id) } }
    var isPeerTube: Bool { peerTube != nil }
}

public extension PlaylistID {
    static func peerTube(host: String, uuid: String) -> PlaylistID { PlaylistID(rawValue: PeerTubeID.make(host: host, id: uuid)) }
    var peerTube: (host: String, uuid: String)? { PeerTubeID.parse(rawValue).map { ($0.host, $0.id) } }
    var isPeerTube: Bool { peerTube != nil }
}

/// A Piped, Invidious or YT Zero adapter that declines PeerTube content, so the router passes
/// it on instead of asking YouTube's front-ends for IDs they can't know.
public struct YouTubeOnly: VideoSource {
    private let source: any VideoSource

    public init(_ source: any VideoSource) {
        self.source = source
    }

    public var instance: InstanceConfig { source.instance }
    public var capabilities: SourceCapabilities { source.capabilities }

    public func search(_ query: String, cursor: String?) async throws -> Page<VideoSummary> {
        try await source.search(query, cursor: cursor)
    }
    public func search(_ query: String, filter: SearchFilter, cursor: String?) async throws -> Page<SearchResult> {
        try await source.search(query, filter: filter, cursor: cursor)
    }
    public func suggestions(for query: String) async throws -> [String] { try await source.suggestions(for: query) }
    public func trending(region: String?) async throws -> [VideoSummary] { try await source.trending(region: region) }
    public func trending(region: String?, category: TrendingCategory) async throws -> [VideoSummary] {
        guard category != .peerTube else { throw SourceError.belongsElsewhere }
        return try await source.trending(region: region, category: category)
    }
    public func channel(_ id: ChannelID, cursor: String?) async throws -> ChannelPage {
        guard !id.isPeerTube else { throw SourceError.belongsElsewhere }
        return try await source.channel(id, cursor: cursor)
    }
    public func watchPage(for id: VideoID) async throws -> WatchPage {
        guard !id.isPeerTube else { throw SourceError.belongsElsewhere }
        return try await source.watchPage(for: id)
    }
    public func feed(for channels: [ChannelID]) async throws -> [VideoSummary] {
        let mine = channels.filter { !$0.isPeerTube }
        guard !mine.isEmpty else { throw SourceError.belongsElsewhere }
        return try await source.feed(for: mine)
    }
    public func comments(for id: VideoID, cursor: String?) async throws -> Page<Comment> {
        guard !id.isPeerTube else { throw SourceError.belongsElsewhere }
        return try await source.comments(for: id, cursor: cursor)
    }
    public func playlist(_ id: PlaylistID, cursor: String?) async throws -> PlaylistPage {
        guard !id.isPeerTube else { throw SourceError.belongsElsewhere }
        return try await source.playlist(id, cursor: cursor)
    }
    public func channelPlaylists(_ id: ChannelID, cursor: String?) async throws -> Page<PlaylistSummary> {
        guard !id.isPeerTube else { throw SourceError.belongsElsewhere }
        return try await source.channelPlaylists(id, cursor: cursor)
    }
    public func channelShorts(_ id: ChannelID, cursor: String?) async throws -> Page<VideoSummary> {
        guard !id.isPeerTube else { throw SourceError.belongsElsewhere }
        return try await source.channelShorts(id, cursor: cursor)
    }
    public func healthCheck() async -> HealthSample { await source.healthCheck() }
}
