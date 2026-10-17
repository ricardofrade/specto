import Foundation
import Testing
import Core
@testable import Playback

struct UpNextCountdownTests {
    private func video(_ id: String, live: Bool = false, short: Bool = false) -> VideoSummary {
        VideoSummary(id: VideoID(rawValue: id), title: id, channelID: ChannelID(rawValue: "UC"), channelName: "C",
                     duration: .seconds(60), publishedAt: nil, viewCount: nil, thumbnails: [], isLive: live, isShort: short)
    }

    @Test func skipsTheCurrentVideoLiveStreamsAndShorts() {
        let related = [video("now"), video("live", live: true), video("short", short: true), video("next")]
        #expect(UpNextCountdown.candidate(in: related, after: VideoID(rawValue: "now"))?.id.rawValue == "next")
        #expect(UpNextCountdown.candidate(in: [video("now")], after: VideoID(rawValue: "now")) == nil)
    }

    @Test func countsDownWithItsLabel() {
        var countdown = UpNextCountdown(video: video("next"))
        #expect(countdown.secondsLeft == 5 && countdown.label.contains("5"))
        countdown.tick(2)
        #expect(countdown.secondsLeft == 2 && countdown.label.contains("2"))
    }
}
