import Foundation
import Testing
import Core

struct SourceErrorTests {
    @Test(arguments: [
        SourceError.unsupported(.streams),
        .decoding("bad json"),
        .rateLimited(retryAfter: nil),
        .blockedUpstream,
        .network(URLError(.timedOut)),
        .http(status: 500),
        .http(status: 403),
        .http(status: 429),
    ])
    func instanceProblemsRetryElsewhere(_ error: SourceError) {
        #expect(error.isRetryableElsewhere)
    }

    @Test(arguments: [
        SourceError.unavailable(reason: "Private video"),
        .http(status: 404),
        .http(status: 400),
    ])
    func contentProblemsDoNotRetry(_ error: SourceError) {
        #expect(!error.isRetryableElsewhere)
    }

    @Test func byteRangeIsInclusive() {
        #expect(ByteRange(start: 0, end: 739).length == 740)
    }
}

struct ThumbnailChoiceTests {
    private func thumb(_ width: Int) -> Thumbnail {
        Thumbnail(url: URL(string: "https://i.example/\(width).jpg")!, width: width, height: width * 9 / 16)
    }

    @Test func picksTheSmallestThatCoversTheCell() {
        let thumbnails = [thumb(1280), thumb(320), thumb(640)]
        #expect(thumbnails.best(forPixelWidth: 600)?.width == 640)
        #expect(thumbnails.best(forPixelWidth: 2000)?.width == 1280)
        #expect([Thumbnail.unsized("https://i.example/x.jpg")!].best(forPixelWidth: 600)?.width == 0)
        #expect([Thumbnail]().best(forPixelWidth: 100) == nil)
    }
}
