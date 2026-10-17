import Foundation

/// Health of one instance for one capability, learned from real traffic (passive)
/// and from `healthCheck()` (active).
struct InstanceHealth: Sendable {
    var consecutiveFailures = 0
    /// While set and in the future, the instance is skipped for this capability.
    var openUntil: ContinuousClock.Instant?
    /// Exponentially weighted moving average of successful call latency.
    var latency: Duration?

    func isOpen(at now: ContinuousClock.Instant) -> Bool {
        openUntil.map { now < $0 } ?? false
    }

    mutating func recordSuccess(latency sample: Duration) {
        consecutiveFailures = 0
        openUntil = nil
        latency = latency.map { $0 * 0.7 + sample * 0.3 } ?? sample
    }

    mutating func recordFailure(_ error: SourceError, at now: ContinuousClock.Instant) {
        consecutiveFailures += 1
        let cooldown: Duration = switch error {
        // Blocked instances stay blocked for a while; don't hammer them.
        case .blockedUpstream: .seconds(15 * 60)
        case .rateLimited(let retryAfter): retryAfter ?? .seconds(60)
        default: consecutiveFailures >= 3 ? .seconds(min(30 * (1 << min(consecutiveFailures - 3, 5)), 600)) : .zero
        }
        openUntil = cooldown > .zero ? now + cooldown : nil
    }
}

/// Routes each operation to the best instance that declares the capability, and fails over
/// to the next one when an error is `isRetryableElsewhere`.
public actor InstanceRouter: SourceRouting {
    private var sources: [any VideoSource]
    /// The person's pick ("Prefer"): asked first while it isn't cooling down; the others by
    /// speed after it (ADR 0018).
    private var preferred: UUID?
    private var health: [Key: InstanceHealth] = [:]
    private let clock = ContinuousClock()

    private struct Key: Hashable {
        let instance: UUID
        let capability: UInt32
    }

    public init(sources: [any VideoSource], preferred: UUID? = nil) {
        self.sources = sources
        self.preferred = preferred
    }

    public func replaceSources(_ sources: [any VideoSource]) {
        self.sources = sources
        let ids = Set(sources.map(\.instance.id))
        health = health.filter { ids.contains($0.key.instance) }
    }

    public nonisolated func perform<T: Sendable>(
        _ capability: SourceCapabilities,
        _ operation: @Sendable (any VideoSource) async throws -> T
    ) async throws -> T {
        let candidates = await rankedSources(for: capability)
        guard !candidates.isEmpty else { throw SourceError.unsupported(capability) }

        var lastError: Error = SourceError.unsupported(capability)
        for source in candidates {
            let start = clock.now
            do {
                let value = try await operation(source)
                await record(.success(clock.now - start), source: source, capability: capability)
                return value
            } catch SourceError.belongsElsewhere {
                // Not this instance's content: no mark against its health.
                lastError = SourceError.belongsElsewhere
            } catch let error as SourceError {
                await record(.failure(error), source: source, capability: capability)
                lastError = error
                guard error.isRetryableElsewhere else { throw error }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError {
                let wrapped = SourceError.network(error)
                await record(.failure(wrapped), source: source, capability: capability)
                lastError = wrapped
            }
        }
        throw lastError
    }

    /// The preferred instance first when it's available; then closed circuits by latency
    /// (unknown latency last), keeping the user's order on ties.
    func rankedSources(for capability: SourceCapabilities) -> [any VideoSource] {
        let ranked = rankedBySpeed(for: capability)
        guard let preferred, let index = ranked.firstIndex(where: { $0.instance.id == preferred }),
              !(health[key(ranked[index], capability)]?.isOpen(at: clock.now) ?? false) else { return ranked }
        var list = ranked
        list.insert(list.remove(at: index), at: 0)
        return list
    }

    private func rankedBySpeed(for capability: SourceCapabilities) -> [any VideoSource] {
        let now = clock.now
        let supporting = sources.enumerated().filter { $0.element.capabilities.contains(capability) }
        let available = supporting.filter { !(health[key($0.element, capability)]?.isOpen(at: now) ?? false) }
        // If every instance is cooling down, try them anyway rather than fail without trying.
        let pool = available.isEmpty ? supporting : available
        return pool.sorted { a, b in
            let la = health[key(a.element, capability)]?.latency
            let lb = health[key(b.element, capability)]?.latency
            switch (la, lb) {
            case let (x?, y?) where x != y: return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    private enum Outcome { case success(Duration), failure(SourceError) }

    private func record(_ outcome: Outcome, source: any VideoSource, capability: SourceCapabilities) {
        let k = key(source, capability)
        var entry = health[k] ?? InstanceHealth()
        switch outcome {
        case .success(let latency): entry.recordSuccess(latency: latency)
        case .failure(let error): entry.recordFailure(error, at: clock.now)
        }
        health[k] = entry
    }

    private func key(_ source: any VideoSource, _ capability: SourceCapabilities) -> Key {
        Key(instance: source.instance.id, capability: capability.rawValue)
    }

    /// Active probe of every instance; unhealthy ones cool down for all capabilities.
    public func checkHealth() async -> [HealthSample] {
        let current = sources
        let samples = await withTaskGroup(of: HealthSample.self) { group in
            for source in current { group.addTask { await source.healthCheck() } }
            return await group.reduce(into: []) { $0.append($1) }
        }
        let now = clock.now
        for sample in samples where !sample.isHealthy {
            for source in current where source.instance.id == sample.instanceID {
                for bit in 0..<32 where source.capabilities.rawValue & (1 << bit) != 0 {
                    let k = Key(instance: sample.instanceID, capability: 1 << bit)
                    var entry = health[k] ?? InstanceHealth()
                    entry.openUntil = now + .seconds(60)
                    health[k] = entry
                }
            }
        }
        return samples
    }
}
