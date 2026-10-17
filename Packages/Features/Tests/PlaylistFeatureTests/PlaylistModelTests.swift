import Foundation
import Testing
import Core
import Library
@testable import PlaylistFeature

@MainActor
struct PlaylistModelTests {
    private let summary = PlaylistSummary(id: PlaylistID(rawValue: "PLx"), title: "From the list", channelName: "Blender",
                                          videoCount: 5, thumbnails: [])

    private func video(_ n: Int) -> VideoSummary {
        VideoSummary(id: VideoID(rawValue: "video\(n)"), title: "Video \(n)", channelID: ChannelID(rawValue: "UC"),
                     channelName: "Blender", duration: .seconds(60), publishedAt: nil, viewCount: nil, thumbnails: [])
    }

    /// Two videos per page, five in all.
    private func pages() -> @Sendable (PlaylistID, String?) async throws -> PlaylistPage {
        let all = (0..<5).map(video)
        return { id, cursor in
            let start = cursor.flatMap(Int.init) ?? 0
            let end = min(start + 2, all.count)
            return PlaylistPage(id: id, title: cursor == nil ? "Conference talks" : "", channelName: cursor == nil ? "Blender" : nil,
                                videoCount: cursor == nil ? 5 : nil,
                                videos: Page(items: Array(all[start..<end]), nextCursor: end < all.count ? "\(end)" : nil))
        }
    }

    @Test func firstPageUpdatesTheHeader() async throws {
        let model = PlaylistModel(summary: summary, store: PlaylistStore(try AppDatabase.inMemory()), load: pages())
        await model.loadFirstPage()
        #expect(model.title == "Conference talks")
        #expect(model.rows.map(\.id.rawValue) == ["video0", "video1"])
        #expect(model.countText != nil)
    }

    @Test func playAllLoadsEveryPage() async throws {
        let model = PlaylistModel(summary: summary, store: PlaylistStore(try AppDatabase.inMemory()), load: pages())
        let videos = await model.allVideos()
        #expect(videos.map(\.id.rawValue) == (0..<5).map { "video\($0)" })
        #expect(await model.allVideos(limit: 3).count == 3)
    }

    @Test func savingGoesToTheLibrary() async throws {
        let db = try AppDatabase.inMemory()
        let model = PlaylistModel(summary: summary, store: PlaylistStore(db), load: pages())
        await model.loadFirstPage()
        model.toggleSaved()
        #expect(model.isSaved)
        #expect(try PlaylistStore(db).all().map(\.title) == ["Conference talks"])
        model.toggleSaved()
        #expect(try PlaylistStore(db).all().isEmpty)
        let reopened = PlaylistModel(summary: summary, store: PlaylistStore(db), load: pages())
        #expect(!reopened.isSaved)
    }
}
