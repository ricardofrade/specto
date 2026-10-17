import Foundation

/// PeerTube's REST API (`/api/v1`), as far as Specto uses it. Shapes recorded from a public
/// server in `Tests/CoreTests/Fixtures/peertube` (hosts sanitised).
enum PeerTubeDTO {
    struct List<Item: Decodable>: Decodable {
        let total: Int?
        let data: [Item]?
    }

    struct Image: Decodable {
        let path: String?
        let fileUrl: String?
        let width: Int?
        let height: Int?

        func thumbnail(base: URL) -> Thumbnail? {
            guard let url = PeerTubeDTO.absolute(fileUrl ?? path, base: base) else { return nil }
            return Thumbnail(url: url, width: width ?? 0, height: height ?? 0)
        }
    }

    struct Channel: Decodable {
        let name: String?
        let displayName: String?
        let host: String?
        let avatars: [Image]?
        let banners: [Image]?

        /// `name@host`, how PeerTube addresses a channel on any server.
        var handle: String? {
            guard let name, let host else { return nil }
            return "\(name)@\(host)"
        }

        func summary(server: String, base: URL) -> ChannelSummary? {
            guard let handle else { return nil }
            return ChannelSummary(id: .peerTube(host: server, handle: handle), name: displayName ?? name ?? "",
                                  avatar: avatars?.compactMap { $0.thumbnail(base: base) }.max { $0.width < $1.width })
        }
    }

    struct Video: Decodable {
        let uuid: String?
        let name: String?
        let duration: Int?
        let views: Int?
        let likes: Int?
        let publishedAt: String?
        let isLive: Bool?
        let thumbnailPath: String?
        let previewPath: String?
        let channel: Channel?
        let description: String?
        let streamingPlaylists: [StreamingPlaylist]?
        let files: [File]?

        func summary(server: String, base: URL) -> VideoSummary? {
            guard let uuid else { return nil }
            var thumbnails: [Thumbnail] = []
            if let small = PeerTubeDTO.absolute(thumbnailPath, base: base) { thumbnails.append(Thumbnail(url: small, width: 280, height: 157)) }
            if let large = PeerTubeDTO.absolute(previewPath, base: base) { thumbnails.append(Thumbnail(url: large, width: 850, height: 480)) }
            let handle = channel?.handle ?? ""
            return VideoSummary(id: .peerTube(host: server, uuid: uuid), title: name ?? "",
                                channelID: .peerTube(host: server, handle: handle),
                                channelName: channel?.displayName ?? channel?.name ?? "",
                                duration: duration.flatMap { $0 > 0 ? .seconds($0) : nil },
                                publishedAt: publishedAt.flatMap(PeerTubeDTO.date),
                                viewCount: views, thumbnails: thumbnails, isLive: isLive ?? false)
        }
    }

    struct StreamingPlaylist: Decodable {
        let playlistUrl: String?
    }

    struct File: Decodable {
        struct Resolution: Decodable { let id: Int? }
        let fileUrl: String?
        let resolution: Resolution?
    }

    struct Caption: Decodable {
        struct Language: Decodable { let id: String?; let label: String? }
        let language: Language?
        let captionPath: String?
        let fileUrl: String?
    }

    struct Storyboards: Decodable {
        struct Board: Decodable {
            let storyboardPath: String?
            let fileUrl: String?
            let totalWidth: Int?
            let totalHeight: Int?
            let spriteWidth: Int?
            let spriteHeight: Int?
            let spriteDuration: Int?
        }
        let storyboards: [Board]?
    }

    struct Account: Decodable {
        let name: String?
        let displayName: String?
    }

    struct Comment: Decodable {
        let id: Int?
        let text: String?
        let account: Account?
        let createdAt: String?
        let totalReplies: Int?
        let isDeleted: Bool?
    }

    /// A thread with its replies, as `comment-threads/{id}` returns it.
    struct Thread: Decodable {
        let comment: Comment?
        let children: [Thread]?
    }

    struct Playlist: Decodable {
        let uuid: String?
        let displayName: String?
        let videosLength: Int?
        let thumbnailPath: String?
        let videoChannel: Channel?

        func summary(server: String, base: URL) -> PlaylistSummary? {
            guard let uuid else { return nil }
            return PlaylistSummary(id: .peerTube(host: server, uuid: uuid), title: displayName ?? "",
                                   channelName: videoChannel?.displayName, videoCount: videosLength,
                                   thumbnails: PeerTubeDTO.absolute(thumbnailPath, base: base)
                                       .map { [Thumbnail(url: $0, width: 280, height: 157)] } ?? [])
        }
    }

    struct PlaylistElement: Decodable {
        let video: Video?
    }

    struct Config: Decodable {
        struct Instance: Decodable { let name: String? }
        let serverVersion: String?
        let instance: Instance?
    }

    /// A server's own path ("/lazy-static/…") or a full URL, made absolute.
    static func absolute(_ text: String?, base: URL) -> URL? {
        guard let text, !text.isEmpty else { return nil }
        return URL(string: text, relativeTo: base)?.absoluteURL
    }

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        // Read-only after creation; ISO8601DateFormatter is documented thread-safe.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(_ text: String) -> Date? {
        iso.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
