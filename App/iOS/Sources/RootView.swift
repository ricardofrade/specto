import SwiftUI
import Core
import Library
import Playback
import FeedFeature
import InstancesFeature
import WatchFeature

struct RootView: View {
    enum Section: Hashable { case feed, settings }

    let environment: AppEnvironment
    let onFirstFeedFrame: () -> Void
    @State private var feed: FeedModel
    @State private var section = Section.feed
    @State private var watching: WatchContent?
    @State private var shortSidePixels = 1080
    @Environment(\.displayScale) private var displayScale

    init(environment: AppEnvironment, onFirstFeedFrame: @escaping () -> Void) {
        self.environment = environment
        self.onFirstFeedFrame = onFirstFeedFrame
        _feed = State(initialValue: FeedModel(store: FeedStore(environment.database)) { force in
            try await environment.refreshFeed(force: force)
        })
    }

    var body: some View {
        TabView(selection: $section) {
            Tab(value: Section.feed) {
                FeedScreen(model: feed, emptyReason: emptyReason, onEmptyAction: { section = .settings },
                           onSelect: { play($0.video) }, onPrefetch: { environment.prefetch($0.video) })
                    .onAppear(perform: onFirstFeedFrame)
            } label: {
                Label { Text("Subscriptions") } icon: { Image(systemName: "play.square.stack") }
            }
            Tab(value: Section.settings) {
                NavigationStack {
                    InstancesScreen(instances: InstanceStore(environment.database),
                                    subscriptions: SubscriptionStore(environment.database),
                                    secrets: environment.secrets, deviceName: UIDevice.current.name,
                                    onChange: { environment.instancesChanged() },
                                    onImported: { environment.subscriptionsChanged($0) })
                }
            } label: {
                Label { Text("Settings") } icon: { Image(systemName: "gearshape") }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            shortSidePixels = Int(min(size.width, size.height) * displayScale)
        }
        .sheet(item: $watching) { content in
            WatchScreen(session: environment.session, content: content) { play($0) }
                .presentationDragIndicator(.visible)
        }
    }

    private var emptyReason: FeedScreen.EmptyReason? {
        if environment.instances.isEmpty { return .noInstance }
        if !environment.hasSubscriptions && environment.account == nil { return .noSubscriptions }
        return nil
    }

    private func play(_ video: VideoSummary) {
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

extension WatchContent: @retroactive Identifiable {
    public var id: VideoID { video.id }
}
