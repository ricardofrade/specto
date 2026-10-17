import SwiftUI
import Core
import Library
import Playback

/// M6: the listening queue, auto-advance, and offline audio.
extension AppEnvironment {
    // MARK: Feed housekeeping

    /// Mark as Watched / Unwatched; a linked account hears about it too.
    func setWatched(_ video: VideoSummary, _ watched: Bool) {
        let store = WatchStateStore(database)
        if watched { try? store.markWatched(video.id, duration: video.duration) } else { try? store.markUnwatched(video.id) }
        if let account { Task { try? await account.setWatched(watched, for: video.id) } }
    }

    /// Keeps the subscription, takes its videos off Home (undo in Library → Channels).
    func setHiddenFromHome(_ channel: ChannelID, _ hidden: Bool) {
        try? SubscriptionStore(database).setHiddenFromHome(channel, hidden)
    }

    // MARK: Queue

    func addToQueue(_ video: VideoSummary) {
        try? QueueStore(database).add(video)
        #if OFFLINE_DOWNLOADS
        if AppSettings.shared.downloadsQueue { download(video) }
        #endif
    }

    func removeFromQueue(_ id: VideoID) {
        try? QueueStore(database).remove(id)
    }

    func isQueued(_ id: VideoID) -> Bool {
        (try? QueueStore(database).contains(id)) ?? false
    }

    /// Play All, or a video tapped in a playlist: `videos[start]` plays, then the rest in order.
    /// Returns the video to open. The queue isn't touched (queued videos may download).
    func startPlaylist(_ videos: [VideoSummary], at start: Int) -> VideoSummary? {
        guard videos.indices.contains(start) else { return nil }
        playlistContext = videos
        return videos[start]
    }

    /// When a video ends, the next queued one plays in the same mode (audio in the car); with
    /// nothing queued, the next video of the playlist it came from.
    func watchForEndOfPlayback() {
        withObservationTracking { _ = session.state } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.session.state == .ended, let current = self.session.item?.videoID {
                    let mode = self.session.mode
                    try? QueueStore(self.database).remove(current)
                    if self.sleepTimer.stopsAtEndOfVideo() {
                        self.watchForEndOfPlayback()
                        return
                    }
                    if let next = (try? QueueStore(self.database).next(after: current)) ?? self.nextInPlaylist(after: current) {
                        _ = try? await self.play(next, mode: mode, surfaceHeight: self.surfaceHeight)
                    }
                }
                self.watchForEndOfPlayback()
            }
        }
    }

    func nextInPlaylist(after id: VideoID) -> VideoSummary? {
        guard let index = playlistContext.firstIndex(where: { $0.id == id }) else { return nil }
        return playlistContext.dropFirst(index + 1).first
    }

    // MARK: Offline audio

    #if OFFLINE_DOWNLOADS
    /// Downloads the video's AAC audio (AVPlayer-playable, single file). YT Zero's audio route
    /// needs a token and serves 8 MiB chunks, so audio comes from Piped or Invidious.
    func download(_ video: VideoSummary) {
        let router = self.router, offline = self.offlineAudio, limit = AppSettings.shared.offlineLimitBytes
        Task {
            guard let page = try? await router.perform(.streams, { try await $0.watchPage(for: video.id) }),
                  let audio = FormatSelector(capabilities: DecodeCapabilities())
                    .selectAudio(from: page.manifest.audioStreams, for: .avPlayer,
                                 preferredLanguage: AppSettings.shared.audioLanguage) else { return }
            try? FeedStore(database).save([video])
            try? offline.download(video.id, audio: audio)
            offline.enforceLimit(limit)
        }
    }

    /// "120 MB", read off the main actor.
    func offlineUsage() async -> String {
        let offline = offlineAudio
        let bytes = await Task.detached { offline.usedBytes }.value
        return bytes.formatted(.byteCount(style: .file))
    }

    /// Evicts down to the current limit and returns the new usage.
    func applyOfflineLimit() async -> String {
        let offline = offlineAudio, limit = AppSettings.shared.offlineLimitBytes
        await Task.detached { offline.enforceLimit(limit) }.value
        return await offlineUsage()
    }

    func deleteAllDownloads() async {
        let offline = offlineAudio, database = database
        await Task.detached {
            for entry in (try? DownloadStore(database).all()) ?? [] { offline.remove(entry.videoID) }
        }.value
    }

    func playOffline(_ video: VideoSummary, file: URL, tap: Signpost.Interval) async -> WatchPage {
        let summary = video
        let page = WatchPage(details: VideoDetails(summary: summary, description: "", likeCount: nil, related: []),
                             manifest: StreamManifest(videoID: video.id, videoStreams: [], audioStreams: [], hlsURL: nil,
                                                      muxedURL: file, chapters: [], expiresAt: nil))
        currentPage = page
        captionTracks = []
        selectedCaption = nil
        let item = NowPlayingItem(videoID: video.id, title: video.title, channelName: video.channelName,
                                  artworkURL: video.thumbnails.first?.url)
        await session.play(item, PlaybackRequest(videoID: video.id, source: .progressive(file), mode: .audioOnly,
                                                 engine: .avPlayer))
        try? DownloadStore(database).markPlayed(video.id)
        Signpost.end(tap)
        loadSkipSegments(for: video.id)
        return page
    }
    #endif
}
