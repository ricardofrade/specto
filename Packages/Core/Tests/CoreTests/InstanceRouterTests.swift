import Foundation
import Testing
@testable import Core

/// A source whose behaviour is scripted per call.
private final class ScriptedSource: VideoSource, @unchecked Sendable {
    let instance: InstanceConfig
    let capabilities: SourceCapabilities
    // Guarded by `lock`.
    private var results: [Result<[VideoSummary], SourceError>]
    private(set) var calls = 0
    private let lock = NSLock()

    init(_ name: String, capabilities: SourceCapabilities = [.trending], results: [Result<[VideoSummary], SourceError>]) {
        instance = InstanceConfig(kind: .piped, displayName: name, apiURL: URL(string: "https://\(name).example")!)
        self.capabilities = capabilities
        self.results = results
    }

    func trending(region: String?) async throws -> [VideoSummary] {
        let result = lock.withLock {
            calls += 1
            return results.count > 1 ? results.removeFirst() : results[0]
        }
        return try result.get()
    }

    func healthCheck() async -> HealthSample {
        HealthSample(instanceID: instance.id, isHealthy: true, latency: .milliseconds(5))
    }

    var callCount: Int { lock.withLock { calls } }
}

struct InstanceRouterTests {
    private let ok: Result<[VideoSummary], SourceError> = .success([])

    @Test func failsOverOnRetryableErrors() async throws {
        let blocked = ScriptedSource("a", results: [.failure(.blockedUpstream)])
        let healthy = ScriptedSource("b", results: [ok])
        let router = InstanceRouter(sources: [blocked, healthy])
        _ = try await router.perform(.trending) { try await $0.trending(region: nil) }
        #expect(blocked.callCount == 1 && healthy.callCount == 1)
    }

    @Test func thePreferredInstanceGoesFirstUntilItFails() async throws {
        let fast = ScriptedSource("a", results: [ok])
        let preferred = ScriptedSource("b", results: [.failure(.blockedUpstream), ok])
        let router = InstanceRouter(sources: [fast, preferred], preferred: preferred.instance.id)
        _ = try await router.perform(.trending) { try await $0.trending(region: nil) }
        #expect(preferred.callCount == 1 && fast.callCount == 1)   // Tried first, failed over.
        // Blocked: cooling down, so the other goes first now.
        _ = try await router.perform(.trending) { try await $0.trending(region: nil) }
        #expect(preferred.callCount == 1 && fast.callCount == 2)
    }

    @Test func doesNotRetryContentErrorsElsewhere() async {
        let first = ScriptedSource("a", results: [.failure(.unavailable(reason: "Private video"))])
        let second = ScriptedSource("b", results: [ok])
        let router = InstanceRouter(sources: [first, second])
        await #expect(throws: SourceError.self) {
            try await router.perform(.trending) { try await $0.trending(region: nil) }
        }
        #expect(second.callCount == 0)
    }

    @Test func skipsSourcesWithoutTheCapability() async throws {
        let noTrending = ScriptedSource("a", capabilities: [.search], results: [ok])
        let trending = ScriptedSource("b", results: [ok])
        let router = InstanceRouter(sources: [noTrending, trending])
        _ = try await router.perform(.trending) { try await $0.trending(region: nil) }
        #expect(noTrending.callCount == 0 && trending.callCount == 1)
    }

    @Test func aBlockedInstanceCoolsDownAndIsTriedLast() async throws {
        let blocked = ScriptedSource("a", results: [.failure(.blockedUpstream), ok])
        let healthy = ScriptedSource("b", results: [ok])
        let router = InstanceRouter(sources: [blocked, healthy])
        _ = try await router.perform(.trending) { try await $0.trending(region: nil) }
        _ = try await router.perform(.trending) { try await $0.trending(region: nil) }
        // Second call goes straight to the healthy instance.
        #expect(blocked.callCount == 1 && healthy.callCount == 2)
    }

    @Test func withEveryInstanceCoolingDownItStillTries() async throws {
        let only = ScriptedSource("a", results: [.failure(.blockedUpstream), ok])
        let router = InstanceRouter(sources: [only])
        await #expect(throws: SourceError.self) {
            try await router.perform(.trending) { try await $0.trending(region: nil) }
        }
        _ = try await router.perform(.trending) { try await $0.trending(region: nil) }
        #expect(only.callCount == 2)
    }

    @Test func noCapableSourceIsUnsupported() async {
        let router = InstanceRouter(sources: [])
        await #expect(throws: SourceError.self) {
            try await router.perform(.streams) { try await $0.watchPage(for: VideoID(rawValue: "x")) }
        }
    }
}
