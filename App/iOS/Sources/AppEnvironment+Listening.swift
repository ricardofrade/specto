import SwiftUI
import Core
import Library
import Playback

/// M6: the listening queue, auto-advance, and offline audio.
extension AppEnvironment {
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

    /// When a video ends, the next queued one plays in the same mode (audio in the car).
    func watchForEndOfPlayback() {
        withObservationTracking { _ = session.state } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.session.state == .ended, let current = self.session.item?.videoID {
                    let mode = self.session.mode
                    try? QueueStore(self.database).remove(current)
                    if let next = try? QueueStore(self.database).next(after: current) {
                        _ = try? await self.play(next, mode: mode, surfaceHeight: self.surfaceHeight)
                    }
                }
                self.watchForEndOfPlayback()
            }
        }
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
                    .selectAudio(from: page.manifest.audioStreams, for: .avPlayer, preferredLanguage: nil) else { return }
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
