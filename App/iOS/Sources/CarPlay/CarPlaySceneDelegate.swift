import CarPlay
import Core
import Library
import Playback
import DesignSystem

/// CarPlay audio app: Continue / Queue / Subscriptions lists, the system Now Playing screen,
/// and chapters as a list. Plays audio-only through the app's shared `PlaybackSession`.
/// Requires the CarPlay audio entitlement (requested in M0).
@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var environment: AppEnvironment { AppEnvironment.shared }

    nonisolated func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                              didConnect interfaceController: CPInterfaceController) {
        MainActor.assumeIsolated {
            self.interfaceController = interfaceController
            let tabBar = CPTabBarTemplate(templates: makeLists())
            interfaceController.setRootTemplate(tabBar, animated: false, completion: nil)
            configureNowPlaying()
        }
    }

    nonisolated func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                              didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        MainActor.assumeIsolated { self.interfaceController = nil }
    }

    // MARK: Lists

    private func content() -> CarPlayContent {
        let database = environment.database
        return CarPlayContent(
            continueListening: (try? WatchStateStore(database).inProgress()) ?? [],
            queue: (try? QueueStore(database).rows()) ?? [],
            subscriptions: (try? FeedStore(database).rows(AppSettings.shared.feedOptions)) ?? [],
            offline: Set(((try? DownloadStore(database).all()) ?? []).filter { $0.state == .done }.map(\.videoID.rawValue)))
    }

    private func makeLists() -> [CPListTemplate] {
        content().tabs.map { tab in
            let list = CPListTemplate(title: tab.title, sections: [CPListSection(items: tab.items.map(makeItem))])
            list.tabImage = UIImage(systemName: tab.systemImage)
            list.emptyViewSubtitleVariants = [tab.emptyMessage]
            return list
        }
    }

    private func makeItem(_ item: CarPlayContent.Item) -> CPListItem {
        let listItem = CPListItem(text: item.title, detailText: item.detail)
        listItem.isPlaying = environment.session.item?.videoID == item.row.id
        if let progress = item.row.progress { listItem.playbackProgress = progress }
        let row = item.row
        // CarPlay may call handlers off the main thread: @Sendable, hopping to the main actor.
        listItem.handler = { @Sendable [weak self] _, completion in
            let done = Completion(completion)
            Task { @MainActor in
                await self?.play(row)
                done.call()
            }
        }
        if let url = row.thumbnails.best(forPixelWidth: 160)?.url {
            Task {
                let image = await ImagePipeline.shared.image(url, pixelSize: CGSize(width: 160, height: 90))
                listItem.setImage(image)
            }
        }
        return listItem
    }

    private func play(_ row: FeedRow) async {
        _ = try? await environment.play(row.video, mode: .audioOnly, surfaceHeight: 0)
        if let interfaceController, interfaceController.topTemplate !== CPNowPlayingTemplate.shared {
            interfaceController.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
        }
    }

    // MARK: Now Playing and chapters

    private func configureNowPlaying() {
        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.isUpNextButtonEnabled = true
        nowPlaying.upNextTitle = String(localized: "Chapters")
        nowPlaying.add(self)
    }

    fileprivate func showChapters() {
        guard let item = environment.session.item, !item.chapters.isEmpty else { return }
        let rows = item.chapters.map { chapter in
            let row = CPListItem(text: chapter.title, detailText: RowFormatter.clock(chapter.start))
            let start = chapter.start
            row.handler = { @Sendable [weak self] _, completion in
                let done = Completion(completion)
                Task { @MainActor in
                    await self?.environment.session.seek(to: start, precise: false)
                    self?.interfaceController?.popTemplate(animated: true, completion: nil)
                    done.call()
                }
            }
            return row
        }
        interfaceController?.pushTemplate(CPListTemplate(title: String(localized: "Chapters"),
                                                         sections: [CPListSection(items: rows)]),
                                          animated: true, completion: nil)
    }
}

extension CarPlaySceneDelegate: CPNowPlayingTemplateObserver {
    nonisolated func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        Task { @MainActor in self.showChapters() }
    }
}

/// CarPlay's list-item completion isn't annotated `Sendable`. It only tells CarPlay to stop the
/// item's spinner, is called once, and is called on the main actor.
nonisolated private struct Completion: @unchecked Sendable {
    private let body: () -> Void
    init(_ body: @escaping () -> Void) { self.body = body }
    @MainActor func call() { body() }
}
