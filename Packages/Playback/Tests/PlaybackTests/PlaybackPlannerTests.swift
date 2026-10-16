import Foundation
import Testing
import Core
@testable import Playback

struct PlaybackPlannerTests {
    private let url = URL(string: "https://proxy.example/v")!
    private let planner = PlaybackPlanner(selector: FormatSelector(capabilities: .init(av1Hardware: false, vp9Hardware: false,
                                                                                         vp9SoftwareMaxHeight: 1440)))

    private func page(video: [VideoStream] = [], audio: [AudioStream] = [], hls: URL? = nil,
                      muxed: URL? = nil, live: Bool = false) -> WatchPage {
        let summary = VideoSummary(id: VideoID(rawValue: "v"), title: "", channelID: ChannelID(rawValue: "c"),
                                   channelName: "", duration: nil, publishedAt: nil, viewCount: nil,
                                   thumbnails: [], isLive: live)
        return WatchPage(details: VideoDetails(summary: summary, description: "", likeCount: nil, related: []),
                         manifest: StreamManifest(videoID: summary.id, videoStreams: video, audioStreams: audio,
                                                  hlsURL: hls, muxedURL: muxed, chapters: [], expiresAt: nil))
    }

    private var h264: VideoStream {
        VideoStream(url: url, codec: .h264, container: .mp4, width: 1920, height: 1080, fps: 30, bitrate: nil, isHDR: false)
    }
    private var aac: AudioStream { AudioStream(url: url, codec: .aac, container: .mp4, bitrate: 128_000, language: nil) }

    @Test func videoModePairsTheBestVideoWithAudio() throws {
        let request = try planner.request(for: page(video: [h264], audio: [aac]), mode: .video, maxDisplayHeight: 2160,
                                          throughputBitsPerSecond: nil, allowHDR: false, startAt: .seconds(5))
        guard case .adaptive(let video?, let audio) = request.source else { Issue.record("\(request.source)"); return }
        #expect(video.height == 1080 && audio.codec == .aac)
        #expect(request.startAt == .seconds(5))
    }

    @Test func audioOnlyDropsVideo() throws {
        let request = try planner.request(for: page(video: [h264], audio: [aac]), mode: .audioOnly, maxDisplayHeight: 0,
                                          throughputBitsPerSecond: nil, allowHDR: false)
        guard case .adaptive(nil, _) = request.source else { Issue.record("\(request.source)"); return }
    }

    @Test func liveUsesHLSAndSingleURLSourcesPassThrough() throws {
        let live = try planner.request(for: page(video: [h264], audio: [aac], hls: url, live: true), mode: .video,
                                       maxDisplayHeight: 1080, throughputBitsPerSecond: nil, allowHDR: false)
        #expect(live.source == .hls(url))
        let muxed = try planner.request(for: page(muxed: url), mode: .video, maxDisplayHeight: 1080,
                                        throughputBitsPerSecond: nil, allowHDR: false)
        #expect(muxed.source == .progressive(url))
    }

    @Test func nothingPlayableIsAnError() {
        #expect(throws: PlaybackError.self) {
            try planner.request(for: page(), mode: .video, maxDisplayHeight: 1080,
                                throughputBitsPerSecond: nil, allowHDR: false)
        }
    }
}
