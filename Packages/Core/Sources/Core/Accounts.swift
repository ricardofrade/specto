import Foundation

/// Signing in to an instance's account with a username and password (ADR 0017). Each returns
/// the secret the app keeps in the Keychain under `InstanceConfig.tokenKey(for:)`: Piped's
/// token, Invidious's session cookie, or a YT Zero device token.
public enum AccountSignIn {
    public enum Failure: Error, Equatable {
        /// Wrong username or password.
        case rejected
        /// PeerTube accounts aren't supported (its subscriptions stay on the device).
        case unsupported
    }

    public static func signIn(_ instance: InstanceConfig, username: String, password: String,
                              deviceName: String) async throws -> String {
        switch instance.kind {
        case .piped: try await piped(instance.apiURL, username: username, password: password)
        case .invidious: try await invidious(instance.apiURL, username: username, password: password)
        case .ytZero: try await YTZeroDeviceAuth(instanceURL: instance.apiURL)
                .signIn(username: username, password: password, deviceName: deviceName)
        case .peerTube: throw Failure.unsupported
        }
    }

    /// `POST /login` answers `{"token": …}`, or an error body when the credentials are wrong.
    static func piped(_ base: URL, username: String, password: String) async throws -> String {
        struct Body: Encodable { let username: String; let password: String }
        struct Answer: Decodable { let token: String?; let error: String? }
        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: base.appending(path: "login"), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(username: username, password: password))
        let (data, _) = try await session.data(for: request)
        guard let token = (try? JSONDecoder().decode(Answer.self, from: data))?.token, !token.isEmpty else {
            throw Failure.rejected
        }
        return token
    }

    /// Invidious's sign-in form sets an `SID` cookie; its API accepts that cookie.
    static func invidious(_ base: URL, username: String, password: String) async throws -> String {
        // An ephemeral session keeps its cookies in memory, apart from everything else.
        let session = URLSession(configuration: .ephemeral)
        var components = URLComponents(url: base.appending(path: "login"), resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "referer", value: "/"), .init(name: "type", value: "invidious")]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [.init(name: "email", value: username), .init(name: "password", value: password),
                           .init(name: "action", value: "signin")]
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        _ = try await session.data(for: request)
        let cookies = session.configuration.httpCookieStorage?.cookies ?? []
        guard let sid = cookies.first(where: { $0.name == "SID" })?.value, !sid.isEmpty else {
            throw Failure.rejected
        }
        return sid
    }
}

/// A Piped account: its subscriptions and feed (Piped keeps no watch history to sync).
public struct PipedAccount: SubscriptionAccount {
    private let api: APIRequester
    private let token: String

    public init(instance: InstanceConfig, token: String, client: any HTTPClient = URLSessionHTTPClient()) {
        self.token = token
        api = APIRequester(baseURL: instance.apiURL, client: client, headers: ["Authorization": token])
    }

    public func subscriptions() async throws -> [ChannelSummary] {
        struct Entry: Decodable { let url: String?; let name: String?; let avatar: String? }
        let entries: [Entry] = try await api.get("subscriptions")
        return entries.compactMap { entry in
            guard let id = entry.url?.split(separator: "/").last.map(String.init), id.hasPrefix("UC") else { return nil }
            return ChannelSummary(id: ChannelID(rawValue: id), name: entry.name ?? "",
                                  avatar: entry.avatar.flatMap(Thumbnail.unsized))
        }
    }

    public func follow(_ channel: ChannelID) async throws {
        struct Body: Encodable { let channelId: String }
        struct Answer: Decodable { let message: String? }
        let _: Answer = try await api.post("subscribe", json: Body(channelId: channel.rawValue))
    }

    public func unfollow(_ channel: ChannelID) async throws {
        struct Body: Encodable { let channelId: String }
        struct Answer: Decodable { let message: String? }
        let _: Answer = try await api.post("unsubscribe", json: Body(channelId: channel.rawValue))
    }

    /// Piped's feed comes in one list (newest first); page 0 holds the newest 300.
    public func accountFeed(page: Int) async throws -> Page<AccountVideo> {
        guard page == 0 else { return Page(items: [], nextCursor: nil) }
        let items: [PipedDTO.ContentItem] = try await api.get("feed", query: [.init(name: "authToken", value: token)])
        let videos = items.lazy.compactMap(\.videoSummary).prefix(300)
            .map { AccountVideo(video: $0, resumePosition: nil, isWatched: false) }
        return Page(items: Array(videos), nextCursor: nil)
    }

    public func saveProgress(_ position: Duration, duration: Duration, for id: VideoID) async throws {}
    public func setWatched(_ watched: Bool, for id: VideoID) async throws {}
}

/// An Invidious account, through its `/api/v1/auth` endpoints with the session cookie.
public struct InvidiousAccount: SubscriptionAccount {
    private let api: APIRequester
    private let instance: InstanceConfig

    public init(instance: InstanceConfig, session: String, client: any HTTPClient = URLSessionHTTPClient()) {
        self.instance = instance
        api = APIRequester(baseURL: instance.apiURL, client: client, headers: ["Cookie": "SID=\(session)"])
    }

    public func subscriptions() async throws -> [ChannelSummary] {
        struct Entry: Decodable { let author: String?; let authorId: String? }
        let entries: [Entry] = try await api.get("api/v1/auth/subscriptions")
        return entries.compactMap { entry in
            entry.authorId.map { ChannelSummary(id: ChannelID(rawValue: $0), name: entry.author ?? "", avatar: nil) }
        }
    }

    public func follow(_ channel: ChannelID) async throws {
        _ = try await api.send(api.request("api/v1/auth/subscriptions/\(channel.rawValue)", method: "POST"))
    }

    public func unfollow(_ channel: ChannelID) async throws {
        _ = try await api.send(api.request("api/v1/auth/subscriptions/\(channel.rawValue)", method: "DELETE"))
    }

    public func accountFeed(page: Int) async throws -> Page<AccountVideo> {
        struct Feed: Decodable { let notifications: [InvidiousDTO.Item]?; let videos: [InvidiousDTO.Item]? }
        let feed: Feed = try await api.get("api/v1/auth/feed", query: [.init(name: "page", value: String(page + 1))])
        let items = (feed.notifications ?? []) + (feed.videos ?? [])
        var seen = Set<VideoID>()
        let videos = items.compactMap(\.videoSummary).filter { seen.insert($0.id).inserted }
            .map { AccountVideo(video: $0, resumePosition: nil, isWatched: false) }
        return Page(items: videos, nextCursor: videos.isEmpty ? nil : String(page + 1))
    }

    public func saveProgress(_ position: Duration, duration: Duration, for id: VideoID) async throws {}
    public func setWatched(_ watched: Bool, for id: VideoID) async throws {}
}
