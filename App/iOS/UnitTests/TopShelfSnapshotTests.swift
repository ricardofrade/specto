import Foundation
import Testing

@Suite struct TopShelfSnapshotTests {
    @Test func playLinksRoundTrip() throws {
        let url = try #require(TopShelfSnapshot.playURL(for: "aqz-KE-bpKQ"))
        #expect(url.absoluteString == "dev.placeholder.player.tv://watch?v=aqz-KE-bpKQ")
        #expect(TopShelfSnapshot.videoID(in: url) == "aqz-KE-bpKQ")
    }

    @Test func foreignOrIncompleteLinksAreIgnored() throws {
        for link in ["https://example.com/watch?v=aqz-KE-bpKQ", "dev.placeholder.player.tv://channel?v=x",
                     "dev.placeholder.player.tv://watch", "dev.placeholder.player.tv://watch?v="] {
            #expect(TopShelfSnapshot.videoID(in: try #require(URL(string: link))) == nil, "\(link)")
        }
    }

    @Test func snapshotSurvivesEncoding() throws {
        let snapshot = TopShelfSnapshot(
            continueWatching: [.init(id: "a", title: "A", imageURL: URL(string: "https://example.com/a.jpg"), progress: 0.4)],
            latest: [.init(id: "b", title: "B", imageURL: nil, progress: nil)])
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(TopShelfSnapshot.self, from: data) == snapshot)
    }
}
