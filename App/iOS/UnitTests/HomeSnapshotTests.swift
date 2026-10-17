import Foundation
import Testing
@testable import Specto

@Suite struct HomeSnapshotTests {
    @Test func playLinksRoundTrip() throws {
        let url = try #require(HomeSnapshot.playURL(for: "aqz-KE-bpKQ"))
        #expect(url.absoluteString == "dev.placeholder.specto://watch?v=aqz-KE-bpKQ")
        #expect(HomeSnapshot.videoID(in: url) == "aqz-KE-bpKQ")
    }

    @Test func foreignOrIncompleteLinksAreIgnored() throws {
        for link in ["https://example.com/watch?v=aqz-KE-bpKQ", "dev.placeholder.specto://channel?v=x",
                     "dev.placeholder.specto://watch", "dev.placeholder.specto://watch?v="] {
            #expect(HomeSnapshot.videoID(in: try #require(URL(string: link))) == nil, "\(link)")
        }
    }

    @Test func snapshotSurvivesEncoding() throws {
        let snapshot = HomeSnapshot(
            continueWatching: [.init(id: "a", title: "A", imageURL: URL(string: "https://example.com/a.jpg"), progress: 0.4)],
            latest: [.init(id: "b", title: "B", imageURL: nil, progress: nil)])
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(HomeSnapshot.self, from: data) == snapshot)
    }
}
