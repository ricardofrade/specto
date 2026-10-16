import Foundation

/// A source that owns the user's subscriptions and watch state on a server (YT Zero today).
/// When one is linked it is the source of truth; `Library` mirrors it (`docs/adr/0002`).
public protocol SubscriptionAccount: Sendable {
    func subscriptions() async throws -> [ChannelSummary]
    func follow(_ channel: ChannelID) async throws
    func unfollow(_ channel: ChannelID) async throws
    /// The server's feed of the user's subscriptions, newest first. Pages are 0-based offsets.
    func accountFeed(page: Int) async throws -> Page<AccountVideo>
    func saveProgress(_ position: Duration, duration: Duration, for id: VideoID) async throws
    func setWatched(_ watched: Bool, for id: VideoID) async throws
}

public struct ChannelSummary: Identifiable, Hashable, Sendable, Codable {
    public let id: ChannelID
    public let name: String
    public let avatar: Thumbnail?

    public init(id: ChannelID, name: String, avatar: Thumbnail?) {
        self.id = id
        self.name = name
        self.avatar = avatar
    }
}

/// A feed entry with the account's watch state for it.
public struct AccountVideo: Sendable, Hashable {
    public let video: VideoSummary
    public let resumePosition: Duration?
    public let isWatched: Bool

    public init(video: VideoSummary, resumePosition: Duration?, isWatched: Bool) {
        self.video = video
        self.resumePosition = resumePosition
        self.isWatched = isWatched
    }
}
