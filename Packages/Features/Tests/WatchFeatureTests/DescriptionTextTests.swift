import Foundation
import Testing
@testable import WatchFeature

struct DescriptionTextTests {
    private func links(_ text: String) -> [String: String] {
        let attributed = DescriptionText.attributed(text)
        var found: [String: String] = [:]
        for run in attributed.runs {
            if let link = run.link { found[String(attributed[run.range].characters)] = link.absoluteString }
        }
        return found
    }

    @Test func timestampsSeek() {
        let found = links("0:00 Intro\n12:34 The good part\n1:02:03 Credits, at 99:99 nothing")
        #expect(found["0:00"] == "specto-seek:0")
        #expect(found["12:34"] == "specto-seek:754")
        #expect(found["1:02:03"] == "specto-seek:3723")
        #expect(found["99:99"] == nil)
        #expect(DescriptionText.seconds(in: URL(string: "specto-seek:754")!) == 754)
    }

    @Test func youTubeLinksOpenInTheAppOthersInTheBrowser() {
        let found = links("Watch https://www.youtube.com/watch?v=aqz-KE-bpKQ and https://youtu.be/SVJiCL3K0j4, "
                          + "a Short https://youtube.com/shorts/R6yNUnRXZ64, and https://www.blender.org/events")
        #expect(found["https://www.youtube.com/watch?v=aqz-KE-bpKQ"] == "dev.placeholder.specto://watch?v=aqz-KE-bpKQ")
        #expect(found["https://youtu.be/SVJiCL3K0j4"] == "dev.placeholder.specto://watch?v=SVJiCL3K0j4")
        #expect(found["https://youtube.com/shorts/R6yNUnRXZ64"] == "dev.placeholder.specto://watch?v=R6yNUnRXZ64")
        #expect(found["https://www.blender.org/events"] == "https://www.blender.org/events")
        // A front end's own watch link (Piped, Invidious) plays here too.
        #expect(links("https://piped.example/watch?v=aqz-KE-bpKQ").values.first == "dev.placeholder.specto://watch?v=aqz-KE-bpKQ")
    }

    @Test func timesInsideLinksStayPartOfTheLink() {
        let found = links("https://example.com/a?t=1:30")
        #expect(found.count == 1 && found.values.first?.hasPrefix("https://example.com") == true)
    }
}
