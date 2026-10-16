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
