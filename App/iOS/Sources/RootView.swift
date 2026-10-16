import SwiftUI
import Core
import Library
import Playback
import FeedFeature
import InstancesFeature
import WatchFeature
import SearchFeature
import ChannelFeature

/// Typed routes pushed inside the Watch sheet.
enum WatchRoute: Hashable {
    case channel(ChannelID, name: String)
}

struct RootView: View {
    enum Section: Hashable { case feed, search, settings }

    let environment: AppEnvironment
    let onFirstFeedFrame: () -> Void
    @State private var settings = AppSettings()
    @State private var feed: FeedModel
    @State private var search: SearchModel
    @State private var section = Section.feed
    @State private var watching: WatchContent?
    @State private var watchPath: [WatchRoute] = []
    @State private var shortSidePixels = 1080
    @Namespace private var zoom
    @Environment(\.displayScale) private var displayScale

    init(environment: AppEnvironment, onFirstFeedFrame: @escaping () -> Void) {
        self.environment = environment
        self.onFirstFeedFrame = onFirstFeedFrame
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _feed = State(initialValue: FeedModel(store: FeedStore(environment.database),
                                              options: .init(hideShorts: settings.hideShorts)) { force in
            try await environment.refreshFeed(force: force)
        })
        _search = State(initialValue: SearchModel { query, cursor in
            try await environment.search(query, cursor: cursor)
        })
    }

    var body: some View {
        TabView(selection: $section) {
            Tab(value: Section.feed) {
                FeedScreen(model: feed, emptyReason: emptyReason, transition: zoom,
                           onEmptyAction: { section = .settings },
                           onSelect: { play($0.video) }, onPrefetch: { environment.prefetch($0.video) })
                    .onAppear {
                        onFirstFeedFrame()
                        environment.warmUp()
                    }
            } label: {
                Label { Text("Subscriptions") } icon: { Image(systemName: "play.square.stack") }
            }
            Tab(value: Section.settings) {
                NavigationStack { settingsScreen }
            } label: {
                Label { Text("Settings") } icon: { Image(systemName: "gearshape") }
            }
            Tab(value: Section.search, role: .search) {
                SearchScreen(model: search) { play($0) }
            } label: {
                Label { Text("Search") } icon: { Image(systemName: "magnifyingglass") }
            }
        }
        .miniPlayer(isEnabled: environment.session.item != nil && watching == nil) {
            MiniPlayerBar(session: environment.session) { reopenPlayer() }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            shortSidePixels = Int(min(size.width, size.height) * displayScale)
        }
        .onChange(of: settings.hideShorts) { _, hide in
            feed.setOptions(.init(hideShorts: hide))
        }
        .sheet(item: $watching) { content in
            NavigationStack(path: $watchPath) {
                WatchScreen(session: environment.session, content: content, showsRelated: settings.showsRelated,
                            onSelectRelated: { play($0) },
                            onOpenChannel: { watchPath.append(.channel($0, name: $1)) })
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationDestination(for: WatchRoute.self) { route in
                        switch route {
                        case .channel(let id, let name):
                            ChannelScreen(model: channelModel(id, name: name)) { play($0) }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
            .navigationTransition(.zoom(sourceID: content.video.id, in: zoom))
        }
    }

    private var settingsScreen: some View {
        InstancesScreen(instances: InstanceStore(environment.database),
                        subscriptions: SubscriptionStore(environment.database),
                        secrets: environment.secrets, deviceName: UIDevice.current.name,
                        onChange: { environment.instancesChanged() },
                        onImported: { environment.subscriptionsChanged($0) })
            .safeAreaInset(edge: .bottom) {
                Form {
                    Toggle(isOn: $settings.hideShorts) { Text("Hide Shorts in the feed") }
                    Toggle(isOn: $settings.showsRelated) { Text("Show “Up next” suggestions") }
                }
                .frame(height: 140)
                .scrollDisabled(true)
            }
    }

    private var emptyReason: FeedScreen.EmptyReason? {
        if environment.instances.isEmpty { return .noInstance }
        if !environment.hasSubscriptions && environment.account == nil { return .noSubscriptions }
        return nil
    }

    private func channelModel(_ id: ChannelID, name: String) -> ChannelModel {
        ChannelModel(channelID: id, name: name,
                     cached: (try? FeedStore(environment.database).videos(channel: id)) ?? [],
                     isSubscribed: environment.isSubscribed(id),
                     load: { id, cursor in try await environment.channel(id, cursor: cursor) },
                     setSubscribed: { channel, subscribed in try await environment.setSubscribed(channel, subscribed) })
    }

    private func reopenPlayer() {
        guard let item = environment.session.item else { return }
        watching = WatchContent(video: VideoSummary(id: item.videoID, title: item.title,
                                                    channelID: ChannelID(rawValue: ""), channelName: item.channelName,
                                                    duration: nil, publishedAt: nil, viewCount: nil,
                                                    thumbnails: item.artworkURL.map { [Thumbnail(url: $0, width: 0, height: 0)] } ?? []))
        watchPath = []
    }

    private func play(_ video: VideoSummary) {
        watchPath = []
        watching = WatchContent(video: video)
        Task {
            do {
                let details = try await environment.play(video, surfaceHeight: shortSidePixels)
                if watching?.video.id == video.id { watching?.details = details }
            } catch {
                if watching?.video.id == video.id { watching?.error = Self.message(for: error) }
            }
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case SourceError.unavailable(let reason):
            reason ?? String(localized: "This video isn't available.")
        case SourceError.blockedUpstream:
            String(localized: "Your instances are being blocked by YouTube right now. Try again later.")
        case SourceError.unsupported:
            String(localized: "None of your instances can play videos.")
        case let error as PlaybackError:
            switch error {
            case .unsupportedFormat(let detail): detail
            default: String(localized: "Playback failed.")
            }
        default:
            String(localized: "Couldn't load this video.")
        }
    }
}

private extension View {
    /// The tab bar's bottom accessory (iOS 26.1+). On 26.0 there's no mini-player; closing the
    /// Watch screen still keeps playback going.
    @ViewBuilder
    func miniPlayer(isEnabled: Bool, @ViewBuilder content: () -> some View) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: isEnabled, content: content)
        } else {
            self
        }
    }
}

extension WatchContent: @retroactive Identifiable {
    public var id: VideoID { video.id }
}
