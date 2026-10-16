import Foundation
import Testing
@testable import Core

struct CommunityServicesTests {
    private let id = VideoID(rawValue: "dQw4w9WgXcQ")

    @Test func queriesByHashPrefixNeverTheVideoID() async throws {
        let client = FixtureClient()
        client.on("/api/skipSegments/", body: Data(#"""
        [{"videoID":"other00000x","segments":[{"category":"sponsor","actionType":"skip","segment":[1,2]}]},
         {"videoID":"dQw4w9WgXcQ","segments":[
            {"category":"sponsor","actionType":"skip","segment":[30.5,61.0]},
            {"category":"intro","actionType":"skip","segment":[0,4.2]},
            {"category":"poi_highlight","actionType":"poi","segment":[90,90]}]}]
        """#.utf8))
        let segments = try await CommunityServices(client: client).skipSegments(for: id, categories: [.sponsor, .intro])
        #expect(segments.map(\.category) == [.intro, .sponsor])
        #expect(segments.last?.start == .milliseconds(30_500) && segments.last?.end == .seconds(61))
        let path = try #require(client.requests.first?.url?.path())
        #expect(path.hasSuffix("/" + CommunityServices.hashPrefix(id)))
        #expect(!(client.requests.first?.url?.absoluteString.contains(id.rawValue) ?? true))
        #expect(CommunityServices.hashPrefix(id).count == 4)
    }

    @Test func noSegmentsIsA404() async throws {
        let client = FixtureClient()
        client.on("/api/skipSegments/", status: 404, body: Data("Not Found".utf8))
        #expect(try await CommunityServices(client: client).skipSegments(for: id, categories: [.sponsor]).isEmpty)
    }

    @Test func brandingAppliesDeArrowsDisplayRule() async throws {
        let client = FixtureClient()
        client.on("/api/branding/", body: Data(#"""
        {"dQw4w9WgXcQ":{"titles":[{"title":"The >Official Music Video","original":false,"votes":3,"locked":false}],
                        "thumbnails":[{"timestamp":42.5,"original":false,"votes":1,"locked":false}]},
         "downvoted00":{"titles":[{"title":"Bad","original":false,"votes":-2,"locked":false}],"thumbnails":[]},
         "notWanted00":{"titles":[{"title":"Elsewhere","original":false,"votes":5,"locked":false}],"thumbnails":[]}}
        """#.utf8))
        let branding = try await CommunityServices(client: client)
            .branding(for: [id, VideoID(rawValue: "downvoted00")])
        #expect(branding[id] == Branding(title: "The Official Music Video", thumbnailTime: 42.5))
        #expect(branding[VideoID(rawValue: "downvoted00")] == nil)
        #expect(branding[VideoID(rawValue: "notWanted00")] == nil)
    }
}
