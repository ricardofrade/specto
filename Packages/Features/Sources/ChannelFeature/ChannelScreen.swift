import SwiftUI
import Core
import Library
import DesignSystem

@Observable
public final class ChannelModel {
    public let channelID: ChannelID
    public private(set) var name: String
    public private(set) var avatarURL: URL?
    /// The channel's header art, when it has one.
    public private(set) var bannerURL: URL?
    /// A PeerTube channel's home server ("video.blender.org"), from its `name@host` handle.
    public var server: String? {
        channelID.peerTube.flatMap { $0.handle.split(separator: "@").last.map(String.init) }
    }
    public private(set) var rows: [FeedRow] = []
    public private(set) var isSubscribed: Bool
    public private(set) var isLoading = false
    public private(set) var error: String?
    /// The channel's playlists, loaded when the Playlists tab first shows.
    public private(set) var playlists: [PlaylistRow] = []
    public private(set) var loadedPlaylists = false
    public var hasPlaylists: Bool { loadPlaylists != nil }
    /// The channel's Shorts, loaded when the Shorts tab first shows.
    public private(set) var shorts: [FeedRow] = []
    public private(set) var loadedShorts = false
    public var hasShorts: Bool { loadShorts != nil }

    @ObservationIgnored private let load: @Sendable (ChannelID, String?) async throws -> ChannelPage
    @ObservationIgnored private let loadPlaylists: (@Sendable (ChannelID, String?) async throws -> Page<PlaylistSummary>)?
    @ObservationIgnored private let loadShorts: (@Sendable (ChannelID, String?) async throws -> Page<VideoSummary>)?
    @ObservationIgnored private var shortsCursor: String?
    @ObservationIgnored private var loadingShorts = false
    @ObservationIgnored private var playlistsCursor: String?
    @ObservationIgnored private var loadingPlaylists = false
    @ObservationIgnored private let setSubscribed: @Sendable (ChannelSummary, Bool) async throws -> Void
    @ObservationIgnored private var cursor: String?
    @ObservationIgnored private var loadedFirstPage = false

    /// - Parameters:
    ///   - cached: videos already in the local database, shown before the network answers.
    ///   - loadPlaylists: nil when no instance lists playlists (no Playlists tab).
    public init(channelID: ChannelID, name: String, cached: [VideoSummary], isSubscribed: Bool,
                load: @escaping @Sendable (ChannelID, String?) async throws -> ChannelPage,
                loadPlaylists: (@Sendable (ChannelID, String?) async throws -> Page<PlaylistSummary>)? = nil,
                loadShorts: (@Sendable (ChannelID, String?) async throws -> Page<VideoSummary>)? = nil,
                setSubscribed: @escaping @Sendable (ChannelSummary, Bool) async throws -> Void) {
        self.loadShorts = loadShorts
        self.channelID = channelID
        self.name = name
        self.isSubscribed = isSubscribed
        self.load = load
        self.loadPlaylists = loadPlaylists
        self.setSubscribed = setSubscribed
        rows = Self.format(cached)
    }

    public func loadFirstPage() async {
        guard !loadedFirstPage else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await load(channelID, nil)
            loadedFirstPage = true
            if !page.name.isEmpty { name = page.name }
            avatarURL = page.avatar?.url
            bannerURL = page.banner?.url ?? bannerURL
            rows = Self.format(page.videos.items)
            cursor = page.videos.nextCursor
            error = nil
        } catch {
            if rows.isEmpty { self.error = String(localized: "Couldn't load this channel.") }
        }
    }

    public func loadMoreIfNeeded(after id: VideoID) async {
        guard id == rows.last?.id, let cursor, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let page = try? await load(channelID, cursor) else { return }
        let known = Set(rows.map(\.id))
        rows += Self.format(page.videos.items.filter { !known.contains($0.id) })
        self.cursor = page.videos.nextCursor
    }

    /// First call loads the first page; later calls (from the last card) load the next.
    public func loadShortsIfNeeded(after id: VideoID? = nil) async {
        guard let loadShorts, !loadingShorts else { return }
        if loadedShorts { guard id == shorts.last?.id, shortsCursor != nil else { return } }
        loadingShorts = true
        defer { loadingShorts = false }
        guard let page = try? await loadShorts(channelID, loadedShorts ? shortsCursor : nil) else {
            loadedShorts = true
            return
        }
        let known = Set(shorts.map(\.id))
        shorts += Self.format(page.items.filter { !known.contains($0.id) })
        shortsCursor = page.nextCursor
        loadedShorts = true
    }

    /// First call loads the first page; later calls (from the last cell) load the next.
    public func loadPlaylistsIfNeeded(after id: PlaylistID? = nil) async {
        guard let loadPlaylists, !loadingPlaylists else { return }
        if loadedPlaylists { guard id == playlists.last?.id, playlistsCursor != nil else { return } }
        loadingPlaylists = true
        defer { loadingPlaylists = false }
        guard let page = try? await loadPlaylists(channelID, loadedPlaylists ? playlistsCursor : nil) else {
            loadedPlaylists = true
            return
        }
        let known = Set(playlists.map(\.id))
        // Channel playlists are the channel's own: fill in its name where the source leaves it out.
        playlists += page.items.filter { !known.contains($0.id) }.map { item in
            PlaylistRow(PlaylistSummary(id: item.id, title: item.title, channelName: item.channelName ?? name,
                                        videoCount: item.videoCount, thumbnails: item.thumbnails))
        }
        playlistsCursor = page.nextCursor
        loadedPlaylists = true
    }

    public func toggleSubscription() async {
        let target = !isSubscribed
        isSubscribed = target        // Optimistic; reverted on failure.
        do {
            try await setSubscribed(ChannelSummary(id: channelID, name: name,
                                                   avatar: avatarURL.map { Thumbnail(url: $0, width: 0, height: 0) }),
                                    target)
        } catch {
            isSubscribed = !target
            self.error = String(localized: "Couldn't update the subscription.")
        }
    }

    static func format(_ videos: [VideoSummary]) -> [FeedRow] {
        let formatter = RowFormatter()
        return videos.map { formatter.row($0, positionSeconds: nil, durationSeconds: nil) }
    }
}

public struct ChannelScreen: View {
    private let makeModel: () -> ChannelModel
    private let onSelect: (VideoSummary) -> Void
    private let onOpenPlaylist: (PlaylistSummary) -> Void
    private let onOpenShorts: ([VideoSummary], Int) -> Void
    @State private var model: ChannelModel?

    /// The model is created once per screen, on first appearance, however often the parent
    /// re-renders.
    public init(model: @escaping @autoclosure () -> ChannelModel, onSelect: @escaping (VideoSummary) -> Void,
                onOpenPlaylist: @escaping (PlaylistSummary) -> Void = { _ in },
                onOpenShorts: @escaping (_ shorts: [VideoSummary], _ start: Int) -> Void = { _, _ in }) {
        self.makeModel = model
        self.onSelect = onSelect
        self.onOpenPlaylist = onOpenPlaylist
        self.onOpenShorts = onOpenShorts
    }

    public var body: some View {
        if let model {
            ChannelContent(model: model, onSelect: onSelect, onOpenPlaylist: onOpenPlaylist, onOpenShorts: onOpenShorts)
        } else {
            Color.clear.onAppear { model = makeModel() }
        }
    }
}

private struct ChannelContent: View {
    enum Tab: Hashable { case videos, shorts, playlists }

    let model: ChannelModel
    let onSelect: (VideoSummary) -> Void
    let onOpenPlaylist: (PlaylistSummary) -> Void
    let onOpenShorts: ([VideoSummary], Int) -> Void
    @Environment(\.displayScale) private var displayScale
    @State private var columnWidth: CGFloat = 340
    @State private var tab = Tab.videos

    var body: some View {
        ScrollView {
            header
            if let error = model.error {
                Text(error).foregroundStyle(Tokens.Colors.textSecondary).padding()
            }
            if model.hasPlaylists || model.hasShorts {
                Picker(selection: $tab) {
                    Text("Videos").tag(Tab.videos)
                    if model.hasShorts { Text("Shorts").tag(Tab.shorts) }
                    if model.hasPlaylists { Text("Playlists").tag(Tab.playlists) }
                } label: { Text("Show") }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .padding(.horizontal, Tokens.Spacing.screenInset)
                .padding(.bottom, Tokens.Spacing.l)
                .accessibilityIdentifier("channel.tab")
            }
            if tab == .shorts {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Tokens.Spacing.s)],
                          spacing: Tokens.Spacing.s) {
                    ForEach(Array(model.shorts.enumerated()), id: \.element.id) { index, row in
                        Button { onOpenShorts(model.shorts.map(\.video), index) } label: { ShortCard(row: row) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("channel.short")
                            .task { await model.loadShortsIfNeeded(after: row.id) }
                    }
                }
                .padding(.horizontal, Tokens.Spacing.screenInset)
                .task { await model.loadShortsIfNeeded() }
                if model.loadedShorts, model.shorts.isEmpty {
                    Text("No Shorts").foregroundStyle(Tokens.Colors.textSecondary).padding()
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Tokens.Spacing.l)],
                      spacing: Tokens.Spacing.xl) {
                switch tab {
                case .shorts:
                    EmptyView()
                case .videos:
                    ForEach(model.rows) { row in
                        Button { onSelect(row.video) } label: {
                            VideoCell(VideoCellContent(row: row, pixelWidth: Int(columnWidth * displayScale)),
                                      thumbnailWidth: columnWidth)
                                .equatable()
                        }
                        .buttonStyle(.plain)
                        .task { await model.loadMoreIfNeeded(after: row.id) }
                    }
                case .playlists:
                    ForEach(model.playlists) { row in
                        Button { onOpenPlaylist(row.playlist) } label: {
                            VideoCell(VideoCellContent(playlist: row, pixelWidth: Int(columnWidth * displayScale)),
                                      thumbnailWidth: columnWidth)
                                .equatable()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("channel.playlist")
                        .task { await model.loadPlaylistsIfNeeded(after: row.id) }
                    }
                }
            }
            .padding(.horizontal, Tokens.Spacing.screenInset)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                columnWidth = Self.columnWidth(for: width - 2 * Tokens.Spacing.screenInset)
            }
            .task(id: tab) { if tab == .playlists { await model.loadPlaylistsIfNeeded() } }
            if tab == .playlists, model.loadedPlaylists, model.playlists.isEmpty {
                Text("No playlists").foregroundStyle(Tokens.Colors.textSecondary).padding()
            }
            if model.isLoading {
                if model.rows.isEmpty {
                    // The first page: the grid's shape at once.
                    LoadingPlaceholders(count: 3, style: .stacked, thumbnailWidth: columnWidth)
                        .padding(.horizontal, Tokens.Spacing.screenInset)
                } else {
                    ProgressView().padding()
                }
            }
        }
        .navigationTitle(model.name)
        .inlineNavigationTitle()
        .task { await model.loadFirstPage() }
    }

    /// Like an artist page in Music: the channel's banner (or its avatar, blurred) fading into
    /// the page, the avatar overlapping its edge, then the name and Subscribe.
    private var header: some View {
        VStack(spacing: Tokens.Spacing.m) {
            ZStack(alignment: .bottom) {
                // In an overlay: the art fills the width without widening the page.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .overlay {
                        if let banner = model.bannerURL {
                            RemoteImage(banner, pointSize: CGSize(width: 840, height: 140))
                        } else {
                            RemoteImage(model.avatarURL, pointSize: CGSize(width: 88, height: 88))
                                .blur(radius: 40)
                                .opacity(0.55)
                        }
                    }
                    .clipped()
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
                .padding(.bottom, 44)
                RemoteImage(model.avatarURL, pointSize: CGSize(width: 96, height: 96))
                    .frame(width: 96, height: 96)
                    .clipShape(.circle)
                    .overlay { Circle().strokeBorder(Tokens.Colors.background, lineWidth: 4) }
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            }
            .accessibilityHidden(true)
            Text(model.name).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            if let server = model.server {
                ServerLabel(server: server)
            }
            Button { Task { await model.toggleSubscription() } } label: {
                Text(model.isSubscribed ? "Subscribed" : "Subscribe")
                    .frame(minWidth: 140)
            }
            .buttonStyle(.glassProminent)
            .tint(model.isSubscribed ? .gray : .accentColor)
            .accessibilityIdentifier("channel.subscribe")
            .sensoryFeedback(.success, trigger: model.isSubscribed)
        }
        .padding(.bottom, Tokens.Spacing.xl)
    }

    /// Mirrors `.adaptive(minimum: 300)`: as many 300-pt columns as fit, sharing the width.
    static func columnWidth(for width: CGFloat) -> CGFloat {
        let columns = max(1, floor((width + Tokens.Spacing.l) / (300 + Tokens.Spacing.l)))
        return (width - (columns - 1) * Tokens.Spacing.l) / columns
    }
}

/// A Short in the channel's grid: tall, title over the bottom.
private struct ShortCard: View {
    let row: FeedRow
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Color.clear
            .aspectRatio(9 / 16, contentMode: .fit)
            .overlay {
                RemoteImage(row.thumbnails.best(forPixelWidth: Int(200 * displayScale))?.url,
                            pointSize: CGSize(width: 120, height: 213))
            }
            .overlay(alignment: .bottomLeading) {
                Text(row.title)
                    .font(Tokens.Typography.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(Tokens.Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(.rect(cornerRadius: Tokens.Radius.thumbnail))
            .accessibilityElement(children: .combine)
    }
}

extension VideoCellContent {
    init(playlist row: PlaylistRow, pixelWidth: Int) {
        self.init(title: row.playlist.title, channelName: row.playlist.channelName ?? "", detail: "",
                  durationText: row.countText, thumbnailURL: row.playlist.thumbnails.best(forPixelWidth: pixelWidth)?.url,
                  isLive: false, progress: nil, badgeSymbol: "list.bullet")
    }

    init(row: FeedRow, pixelWidth: Int) {
        self.init(title: row.title, channelName: row.channelName, detail: row.detail, durationText: row.durationText,
                  thumbnailURL: row.thumbnails.best(forPixelWidth: pixelWidth)?.url, isLive: row.isLive,
                  progress: row.progress, isPeerTube: row.id.isPeerTube)
    }
}
