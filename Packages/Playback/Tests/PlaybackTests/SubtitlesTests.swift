import Foundation
import Testing
import Core
@testable import Playback

struct WebVTTTests {
    @Test func parsesCuesWithAndWithoutHours() {
        let cues = WebVTT.parse("""
        WEBVTT
        Kind: captions

        00:00:01.000 --> 00:00:03.500 align:start position:0%
        Hello <c.colorE5E5E5>there</c>

        1
        01:00:02.250 --> 01:00:04.000
        <i>Second</i> &amp; last
        """)
        #expect(cues == [
            SubtitleCue(start: .seconds(1), end: .milliseconds(3500), text: "Hello there"),
            SubtitleCue(start: .milliseconds(3_602_250), end: .seconds(3604), text: "Second & last"),
        ])
    }

    @Test func dropsTheRepeatedLineOfRollingAutoCaptions() {
        let cues = WebVTT.parse("""
        WEBVTT

        00:00:01.000 --> 00:00:02.000
        first line

        00:00:02.000 --> 00:00:03.000
        first line
        second<00:00:02.500><c> line</c>
        """)
        #expect(cues.map(\.text) == ["first line", "second line"])
    }

    @Test func findsTheCueShowingAtAPosition() {
        let cues = [SubtitleCue(start: .seconds(1), end: .seconds(2), text: "a"),
                    SubtitleCue(start: .seconds(5), end: .seconds(7), text: "b")]
        #expect(WebVTT.cue(at: .milliseconds(1500), in: cues)?.text == "a")
        #expect(WebVTT.cue(at: .seconds(3), in: cues) == nil)
        #expect(WebVTT.cue(at: .seconds(6), in: cues)?.text == "b")
        #expect(WebVTT.cue(at: .seconds(7), in: cues) == nil)
    }
}
