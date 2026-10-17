import Foundation
import Observation
import QuartzCore
import Core

public struct NowPlayingItem: Sendable, Equatable {
    public let videoID: VideoID
    public let title: String
    public let channelName: String
    public let artworkURL: URL?
    public let chapters: [Chapter]

    public init(videoID: VideoID, title: String, channelName: String,
                artworkURL: URL?, chapters: [Chapter] = []) {
        self.videoID = videoID
        self.title = title
        self.channelName = channelName
        self.artworkURL = artworkURL
        self.chapters = chapters
    }
}

/// Implemented by `Library` (GRDB). Kept as a protocol so `Playback` doesn't depend on persistence.
public protocol ResumeStore: Sendable {
    func position(for id: VideoID) async -> Duration?
    /// `duration` lets the store treat a position near the end as finished.
    func save(_ position: Duration, duration: Duration?, for id: VideoID) async
}

/// One per app, injected into every scene. Owns the engines, so views can come and go
/// (fold, unfold, split-screen, mini-player, PiP, CarPlay) without interrupting playback.
@MainActor
@Observable
public final class PlaybackSession {
    public private(set) var item: NowPlayingItem?
    public private(set) var state: PlaybackState = .idle
    public private(set) var position: Duration = .zero
    public private(set) var duration: Duration?
    public private(set) var mode: PlaybackMode = .video
    public private(set) var decoder: DecoderInfo?
    public private(set) var stats: PlaybackStats?
    /// SponsorBlock segments for the current item.
    public private(set) var skipSegments: [SkipSegment] = []
    /// The most recent automatic skip, for a brief "Skipped sponsor" notice.
    public private(set) var lastSkipped: SkipSegment?
    /// A segment the playhead is in whose category the viewer skips by hand: the player
    /// offers "Skip intro" while it plays. Nil outside one, or once skipped.
    public private(set) var skippable: SkipSegment?
    /// Categories offered as a button instead of skipped automatically.
    @ObservationIgnored private var manualCategories: Set<SkipSegment.Category> = []
    /// Categories only marked on the timeline: never skipped or offered.
    @ObservationIgnored private var shownCategories: Set<SkipSegment.Category> = []
    /// Playback speed (1 is normal). Kept across videos and engine switches.
    public private(set) var rate: Float = 1
    /// The subtitle line to show now, or nil.
    public private(set) var subtitle: String?
    @ObservationIgnored private var subtitleCues: [SubtitleCue] = []
    /// Which engine is playing (AirPlay moves video from mpv to AVPlayer and back).
    public private(set) var engineKind: EngineKind?
    /// The planned video stream's height; nil for audio-only, HLS and single-file sources.
    public private(set) var videoHeight: Int?

    @ObservationIgnored private let engineFactory: @MainActor (EngineKind) -> any PlaybackEngine
    @ObservationIgnored private let resumeStore: any ResumeStore
    @ObservationIgnored private var engines: [EngineKind: any PlaybackEngine] = [:]
    @ObservationIgnored private var eventTasks: [EngineKind: Task<Void, Never>] = [:]
    @ObservationIgnored private var current: (any PlaybackEngine)?
    @ObservationIgnored private weak var host: (any RenderSurfaceHost)?
    @ObservationIgnored private var lastSavedPosition: Duration = .zero
    /// Bumped by every `play` and `stop`; a load that finishes under an older value is stale.
    @ObservationIgnored private var generation = 0
    /// True only while media is loaded. Nothing is saved while loading, so neither a stale
    /// position from the previous media nor a not-yet-resumed zero can overwrite a saved one.
    @ObservationIgnored private var acceptsPosition = false
    /// Saves run one after another so an older position never overwrites a newer one.
    @ObservationIgnored private var saveChain: Task<Void, Never>?
    /// Segments already skipped in this load; seeking back into one plays it.
    @ObservationIgnored private var skipped: Set<SkipSegment> = []

    /// How often position is persisted during playback. Also saved on pause, end and switch.
    @ObservationIgnored public var saveInterval: Duration = .seconds(5)

    public init(resumeStore: any ResumeStore,
                engineFactory: @escaping @MainActor (EngineKind) -> any PlaybackEngine) {
        self.resumeStore = resumeStore
        self.engineFactory = engineFactory
    }

    // MARK: Lifecycle

    /// Call early (after first frame of the feed) so the first tap-to-play skips engine setup.
    public func prewarm() {
        engine(for: .mpv).prewarm()
    }

    public func play(_ item: NowPlayingItem, _ request: PlaybackRequest) async {
        persistPosition(force: true)
        generation += 1
        let loadGeneration = generation
        acceptsPosition = false

        let next = engine(for: request.engine ?? EngineKind.preferred(for: request.mode))
        if let current, current !== next {
            current.stop()
            current.detach()
        }

        self.item = item
        self.mode = request.mode
        self.state = .loading
        self.decoder = nil
        self.stats = nil
        self.duration = nil
        self.position = request.startAt
        self.skipSegments = []
        self.lastSkipped = nil
        self.skippable = nil
        self.manualCategories = []
        self.shownCategories = []
        self.subtitleCues = []
        self.subtitle = nil
        self.skipped = []
        self.current = next
        self.engineKind = next.kind
        if request.mode == .video, case .adaptive(let video?, _) = request.source {
            videoHeight = video.height
        } else {
            videoHeight = nil
        }
        if request.mode == .video, let host {
            next.attach(host)
        }

        var request = request
        if request.startAt == .zero {
            let saved = await resumeStore.position(for: item.videoID)
            guard loadGeneration == generation else { return }
            if let saved {
                request.startAt = saved
                position = saved
            }
        }
        lastSavedPosition = request.startAt

        do {
            try await next.load(request)
            guard loadGeneration == generation else { return }
            acceptsPosition = true
            if rate != 1 { next.setRate(rate) }
            next.play()
        } catch {
            guard loadGeneration == generation else { return }
            state = .failed(error as? PlaybackError ?? .other(String(describing: error)))
        }
    }

    /// Switch between video and audio-only, keeping the current position.
    public func switchMode(to newMode: PlaybackMode, using request: PlaybackRequest) async {
        guard let item, newMode != mode else { return }
        var request = request
        request.mode = newMode
        request.startAt = position
        await play(item, request)
    }

    /// Segments arrive after playback starts; ignored if the item changed meanwhile.
    /// Subtitles for the current video (empty turns them off). Ignored if another video started.
    public func setSubtitles(_ cues: [SubtitleCue], for id: VideoID) {
        guard item?.videoID == id else { return }
        subtitleCues = cues
        updateSubtitle()
    }

    private func updateSubtitle() {
        let text = WebVTT.cue(at: position, in: subtitleCues)?.text
        if text != subtitle { subtitle = text }
    }

    /// - Parameters:
    ///   - manual: categories to offer with a Skip button rather than skip on their own.
    ///   - shownOnly: categories only marked on the timeline (ADR 0013).
    public func setSkipSegments(_ segments: [SkipSegment], for id: VideoID,
                                manual: Set<SkipSegment.Category> = [],
                                shownOnly: Set<SkipSegment.Category> = []) {
        guard item?.videoID == id else { return }
        skipSegments = segments
        manualCategories = manual
        shownCategories = shownOnly
    }

    /// Skips the segment `skippable` offers.
    public func skipOffered() {
        guard let segment = skippable else { return }
        skipped.insert(segment)
        skippable = nil
        let engine = current
        Task { await engine?.seek(to: segment.end, precise: false) }
    }

    public func setVideoEnabled(_ enabled: Bool) {
        current?.setVideoEnabled(enabled)
    }

    public func resume() { current?.play() }

    public func setRate(_ newRate: Float) {
        rate = newRate
        current?.setRate(newRate)
    }
    public func pause() { current?.pause() }

    public func seek(to target: Duration, precise: Bool = false) async {
        await current?.seek(to: target, precise: precise)
    }

    public func stop() {
        persistPosition(force: true)
        subtitleCues = []
        subtitle = nil
        generation += 1
        acceptsPosition = false
        current?.stop()
        current?.detach()
        current = nil
        engineKind = nil
        item = nil
        state = .idle
        position = .zero
        duration = nil
        decoder = nil
        stats = nil
    }

    // MARK: Render surfaces

    /// The engine playing now (system Picture-in-Picture attaches to AVPlayer's layer).
    public var activeEngine: (any PlaybackEngine)? { current }

    /// The visible surface's layer; Picture-in-Picture inserts its player layer here.
    public var hostLayer: CALayer? { host?.containerLayer }

    public func attach(_ host: any RenderSurfaceHost) {
        self.host = host
        if mode == .video {
            current?.attach(host)
        }
    }

    /// No-op unless `host` is the active one: SwiftUI may build the new view before
    /// tearing down the old one, and the old view's detach must not kill the new surface.
    public func detach(_ host: any RenderSurfaceHost) {
        guard self.host === host else { return }
        self.host = nil
        current?.detach()
    }

    public func hostDidLayout(_ host: any RenderSurfaceHost) {
        guard self.host === host else { return }
        current?.layoutSurface()
    }

    // MARK: Testing

    /// Waits for queued resume-position saves.
    func flushSaves() async {
        await saveChain?.value
    }

    // MARK: Private

    private func engine(for kind: EngineKind) -> any PlaybackEngine {
        if let existing = engines[kind] { return existing }
        let created = engineFactory(kind)
        engines[kind] = created
        let stream = created.events
        eventTasks[kind] = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                self.handle(event, from: created)
            }
        }
        return created
    }

    private func handle(_ event: PlaybackEvent, from engine: any PlaybackEngine) {
        guard let current, current === engine else { return }
        switch event {
        case .state(let newState):
            state = newState
            if newState == .paused || newState == .ended {
                persistPosition(force: true)
            }
        case .position(let newPosition, let newDuration):
            guard acceptsPosition else { return }
            position = newPosition
            duration = newDuration
            persistPosition(force: false)
            skipSegmentIfNeeded()
            updateSubtitle()
        case .decoder(let info):
            decoder = info
        case .stats(let newStats):
            stats = newStats
        }
    }

    private func skipSegmentIfNeeded() {
        let inside = skipSegments.first { segment in
            !shownCategories.contains(segment.category)
                && position >= segment.start && position < segment.end - .milliseconds(500) && !skipped.contains(segment)
        }
        guard let segment = inside, !manualCategories.contains(segment.category) else {
            if skippable != inside { skippable = inside }
            return
        }
        skippable = nil
        skipped.insert(segment)
        lastSkipped = segment
        let engine = current
        Task { await engine?.seek(to: segment.end, precise: false) }
    }

    private func persistPosition(force: Bool) {
        guard acceptsPosition, let id = item?.videoID else { return }
        let delta = position > lastSavedPosition ? position - lastSavedPosition : lastSavedPosition - position
        guard force || delta >= saveInterval else { return }
        lastSavedPosition = position
        let store = resumeStore
        let snapshot = position
        let length = duration
        let previous = saveChain
        saveChain = Task {
            await previous?.value
            await store.save(snapshot, duration: length, for: id)
        }
    }
}
