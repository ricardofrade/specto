import SwiftUI
import Core
import Library
import Playback
import PlaybackUI
import DesignSystem

/// Full-screen playback with the Siri Remote:
/// - Select or Play/Pause toggles playback.
/// - Left/right skip back 10 s and forward 10 s. Right after a SponsorBlock skip, left undoes it.
/// - Down opens chapters, subtitles, speed, quality, the sleep timer and Up Next (shown by itself when a video ends
///   with nothing queued).
/// - Menu (Back) closes that panel, then the player.
struct TVPlayerView: View {
    let environment: AppEnvironment
    let video: VideoSummary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var title: String
    @State private var channelName: String
    @State private var chapters: [Chapter] = []
    /// Chapter start times, formatted once when the chapters load.
    @State private var chapterStarts: [String] = []
    @State private var error: String?
    @State private var transportVisible = true
    @State private var showsPanel = false
    @State private var storyboard: Storyboard?
    /// The swiped-to position while scrubbing with the remote, and where the swipe started.
    @State private var scrub: (target: Duration, from: Duration)?
    /// The video's related videos ("Up next"), formatted once per page.
    @State private var related: [FeedRow] = []
    @State private var transport = TransportClock()
    @State private var skipped: (segment: SkipSegment, at: ContinuousClock.Instant)?
    @State private var hideTransport: Task<Void, Never>?
    @FocusState private var playerFocused: Bool

    private var session: PlaybackSession { environment.session }

    init(environment: AppEnvironment, video: VideoSummary) {
        self.environment = environment
        self.video = video
        _title = State(initialValue: video.title)
        _channelName = State(initialValue: video.channelName)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            RemoteSwipe { translation in scrubbed(translation) }
                .allowsHitTesting(false)
            PlayerSurface(session: session)
                .accessibilityIdentifier("tv.player")
                // "<state> <engine> <seconds>": read by UI tests.
                .accessibilityValue(Text(verbatim: "\(session.state) \(session.engineKind?.rawValue ?? "none") \(session.position.components.seconds)"))
            SubtitleView(session.subtitle, baseSize: 38)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, transportVisible || showsPanel ? 330 : 90)
                .animation(Tokens.Motion.standard, value: transportVisible)
            if let error {
                ContentUnavailableView {
                    Label { Text("Can't play this video") } icon: { Image(systemName: "exclamationmark.triangle") }
                } description: {
                    Text(error)
                }
            }
            if let skipped {
                Text("Skipped \(skipped.segment.category.localizedName) · ◀︎ to watch it")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 30).padding(.vertical, 14)
                    .glassEffect(in: .capsule)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(60)
                    .transition(.opacity)
            }
            if showsPanel {
                InfoPanel(chapters: chapters, starts: chapterStarts, current: transport.chapterIndex, related: related,
                          captions: environment.captionTracks, selectedCaption: environment.selectedCaption,
                          onCaption: { environment.selectCaption($0) },
                          rate: session.rate, onRate: { session.setRate($0) },
                          qualities: session.mode == .video ? environment.availableQualities : [],
                          selectedQuality: environment.manualQuality, playingHeight: session.videoHeight,
                          onQuality: { height in Task { await environment.selectQuality(height) } },
                          audioTracks: environment.availableAudioTracks, selectedAudio: environment.selectedAudioTrack,
                          onAudio: { language in Task { await environment.selectAudio(language) } },
                          sleepChoice: environment.sleepTimer.choice, sleepStatus: environment.sleepTimer.status,
                          onSleep: { environment.sleepTimer.set($0) },
                          focusUpNext: session.state == .ended) { chapter in
                    Task { await session.seek(to: chapter.start, precise: false) }
                    closePanel()
                } onPlay: { video in
                    closePanel()
                    Task { await play(video) }
                }
                .transition(.motion(.move(edge: .bottom).combined(with: .opacity), reduceMotion: reduceMotion))
            } else if transportVisible || session.state != .playing {
                TransportBar(title: title, channelName: channelName, text: transport,
                             isPlaying: session.state == .playing, hasChapters: true,
                             segments: segmentFractions, scrub: scrubDisplay)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .focusable(!showsPanel)
        .focused($playerFocused)
        .onTapGesture(perform: togglePlayback)
        .onPlayPauseCommand(perform: togglePlayback)
        .onMoveCommand(perform: move)
        .onExitCommand(perform: exit)
        .onChange(of: session.position) { updateTransport() }
        // The queue can advance to the next video while this screen stays up.
        .onChange(of: session.item?.videoID) { adoptCurrentItem() }
        .onChange(of: session.state) { _, state in
            guard state == .ended, !related.isEmpty else { return }
            Task {
                // Give the queue a moment to start its next video first.
                try? await Task.sleep(for: .seconds(1.5))
                if session.state == .ended { withAnimation(Tokens.Motion.standard) { showsPanel = true } }
            }
        }
        .onChange(of: session.lastSkipped) { _, segment in
            guard let segment else { return }
            withAnimation(Tokens.Motion.standard) { skipped = (segment, .now) }
            Task {
                try? await Task.sleep(for: .seconds(5))
                withAnimation(Tokens.Motion.standard) { if skipped?.segment == segment { skipped = nil } }
            }
        }
        .task { await play(video) }
        .onAppear {
            playerFocused = true
            revealTransport()
        }
    }

    // MARK: Actions

    private func play(_ video: VideoSummary) async {
        do {
            let page = try await environment.play(video, surfaceHeight: Int(1080 * displayScale))
            adoptCurrentItem()
            let formatter = RowFormatter()
            related = page.details.related.map { formatter.row($0, positionSeconds: nil, durationSeconds: nil) }
            storyboard = page.manifest.storyboards.best(forFrameWidth: 320)
            // A Top Shelf link names only the ID; the page has the rest.
            if title.isEmpty { title = page.details.summary.title }
            if channelName.isEmpty { channelName = page.details.summary.channelName }
        } catch {
            self.error = AppEnvironment.message(for: error)
        }
    }

    private func adoptCurrentItem() {
        guard let item = session.item else { return }
        if !item.title.isEmpty { title = item.title }
        if !item.channelName.isEmpty { channelName = item.channelName }
        chapters = item.chapters
        chapterStarts = chapters.map { RowFormatter.clock($0.start) }
        error = nil
    }

    /// SponsorBlock segments as fractions of the video, for the progress bar.
    private var segmentFractions: [ClosedRange<Double>] {
        guard let duration = session.duration, duration > .zero else { return [] }
        return session.skipSegments.map { max(0, $0.start / duration)...min(1, $0.end / duration) }
    }

    private var scrubDisplay: TransportBar.Scrub? {
        guard let scrub, let duration = session.duration, duration > .zero else { return nil }
        return TransportBar.Scrub(fraction: min(1, max(0, scrub.target / duration)),
                                  time: TransportClock.format(scrub.target, longest: duration),
                                  frame: storyboard.flatMap { board in board.frame(at: scrub.target).map { (board, $0) } })
    }

    /// A swipe across the whole surface moves a quarter of the video (at least a minute); lifting
    /// the finger jumps there.
    private func scrubbed(_ translation: CGFloat?) {
        guard !showsPanel, let duration = session.duration, duration > .zero else { return }
        guard let translation else {
            if let scrub { Task { await session.seek(to: scrub.target, precise: true) } }
            withAnimation(Tokens.Motion.standard) { scrub = nil }
            revealTransport()
            return
        }
        let from = scrub?.from ?? session.position
        let span = max(Duration.seconds(60), duration / 4)
        let target = min(duration, max(.zero, from + span * Double(translation / 1000)))
        scrub = (target, from)
        revealTransport()
    }

    private func togglePlayback() {
        if session.state == .playing { session.pause() } else { session.resume() }
        revealTransport()
    }

    private func move(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            if let skipped, ContinuousClock.now - skipped.at < .seconds(5) {
                // Undo the skip: the session skips each segment once, so it plays through now.
                Task { await session.seek(to: skipped.segment.start, precise: false) }
                self.skipped = nil
            } else {
                seek(by: .seconds(-10))
            }
        case .right:
            seek(by: .seconds(10))
        case .down:
            withAnimation(Tokens.Motion.standard) { showsPanel = true }
        default:
            break
        }
        revealTransport()
    }

    /// Exact, so "10 seconds" lands 10 seconds away rather than on the previous keyframe.
    private func seek(by offset: Duration) {
        let target = max(.zero, session.position + offset)
        Task { await session.seek(to: session.duration.map { min($0, target) } ?? target, precise: true) }
    }

    private func exit() {
        if showsPanel {
            closePanel()
        } else {
            session.stop()
            dismiss()
        }
    }

    private func closePanel() {
        withAnimation(Tokens.Motion.standard) { showsPanel = false }
        playerFocused = true
    }

    /// Controls show on interaction and fade after a few seconds of playback.
    private func revealTransport() {
        withAnimation(Tokens.Motion.standard) { transportVisible = true }
        hideTransport?.cancel()
        hideTransport = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(Tokens.Motion.standard) { transportVisible = false }
        }
    }

    private func updateTransport() {
        transport = TransportClock(position: session.position, duration: session.duration, chapters: chapters)
    }
}

struct TransportBar: View {
    @State private var barWidth: CGFloat = 1
    let title: String
    let channelName: String
    let text: TransportClock
    let isPlaying: Bool
    let hasChapters: Bool
    let segments: [ClosedRange<Double>]
    let scrub: Scrub?

    struct Scrub {
        let fraction: Double
        let time: String
        let frame: (Storyboard, Storyboard.Frame)?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).lineLimit(1)
                    Text(channelName).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let chapter = text.chapterTitle {
                    Text(chapter).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Capsule().fill(.white.opacity(0.25))
                .frame(height: 10)
                .overlay(alignment: .leading) {
                    ForEach(segments, id: \.lowerBound) { segment in
                        Rectangle().fill(Color.yellow.opacity(0.85))
                            .frame(width: max(3, barWidth * (segment.upperBound - segment.lowerBound)))
                            .offset(x: barWidth * segment.lowerBound)
                    }
                }
                .overlay(alignment: .leading) {
                    Capsule().fill(.white)
                        .scaleEffect(x: scrub?.fraction ?? text.fraction, y: 1, anchor: .leading)
                }
                .clipShape(.capsule)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
                .overlay(alignment: .bottomLeading) {
                    if let scrub {
                        VStack(spacing: 10) {
                            if let (board, frame) = scrub.frame {
                                StoryboardFrameView(page: frame.page, origin: CGPoint(x: frame.x, y: frame.y),
                                                    frameSize: CGSize(width: board.frameWidth, height: board.frameHeight),
                                                    pageSize: CGSize(width: board.pageWidth, height: board.pageHeight),
                                                    displayWidth: 400)
                                    .clipShape(.rect(cornerRadius: 12))
                            }
                            Text(verbatim: scrub.time).font(.callout.monospacedDigit().weight(.semibold))
                        }
                        .offset(x: min(max(0, barWidth * scrub.fraction - 200), max(0, barWidth - 400)), y: -30)
                    }
                }
            HStack {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                Text(verbatim: scrub?.time ?? text.elapsed).monospacedDigit()
                Spacer()
                if hasChapters {
                    Label { Text("More") } icon: { Image(systemName: "chevron.down") }
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                Text(text.remaining).monospacedDigit()
            }
            .font(.callout)
        }
        .padding(40)
        .glassEffect(in: .rect(cornerRadius: 30))
        .padding(.horizontal, 80)
        .padding(.bottom, 60)
    }
}

/// Chapters and Up Next over the bottom of the video, Apple TV style.
private struct InfoPanel: View {
    let chapters: [Chapter]
    let starts: [String]
    let current: Int?
    let related: [FeedRow]
    let captions: [CaptionTrack]
    let selectedCaption: CaptionTrack?
    let onCaption: (CaptionTrack?) -> Void
    let rate: Float
    let onRate: (Float) -> Void
    let qualities: [Int]
    let selectedQuality: Int?
    let playingHeight: Int?
    let onQuality: (Int?) -> Void
    let audioTracks: [AudioTrackOption]
    let selectedAudio: AudioTrackOption?
    let onAudio: (String?) -> Void
    let sleepChoice: SleepTimer.Choice?
    let sleepStatus: String?
    let onSleep: (SleepTimer.Choice?) -> Void
    /// At the end of a video, focus starts on Up Next.
    let focusUpNext: Bool
    let onChapter: (Chapter) -> Void
    let onPlay: (VideoSummary) -> Void
    @FocusState private var focused: Focus?

    enum Focus: Hashable { case chapter(Int), video(VideoID), setting(Setting) }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            if !chapters.isEmpty {
                shelf(Text("Chapters")) {
                    ForEach(chapters.indices, id: \.self) { index in
                        Button { onChapter(chapters[index]) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(chapters[index].title).font(.callout.weight(.medium)).lineLimit(2)
                                Text(starts[index]).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(width: 360, height: 110, alignment: .topLeading)
                            .padding(24)
                        }
                        .buttonStyle(.card)
                        .focused($focused, equals: .chapter(index))
                    }
                }
            }
            // One row of menus keeps the panel within the screen (Apple TV app style).
            shelf(Text("Settings")) {
                if !captions.isEmpty {
                    settingMenu(.subtitles, title: Text("Subtitles"),
                                value: selectedCaption.map { Text(verbatim: $0.label) } ?? Text("Off")) {
                        Picker(selection: Binding(get: { selectedCaption }, set: { onCaption($0) })) {
                            Text("Off").tag(CaptionTrack?.none)
                            ForEach(captions, id: \.self) { track in Text(verbatim: track.label).tag(Optional(track)) }
                        } label: { Text("Subtitles") }
                    }
                }
                if !audioTracks.isEmpty {
                    settingMenu(.audio, title: Text("Audio Track"), value: Text(verbatim: selectedAudio?.label ?? "")) {
                        Picker(selection: Binding(get: { selectedAudio?.language }, set: { onAudio($0) })) {
                            ForEach(audioTracks) { track in
                                Text(verbatim: track.label).tag(track.language)
                            }
                        } label: { Text("Audio Track") }
                    }
                }
                settingMenu(.speed, title: Text("Playback Speed"), value: Text(verbatim: SpeedOptions.label(for: rate))) {
                    Picker(selection: Binding(get: { rate }, set: { onRate($0) })) {
                        ForEach(SpeedOptions.all, id: \.self) { option in Text(verbatim: option.label).tag(option.rate) }
                    } label: { Text("Playback Speed") }
                }
                if !qualities.isEmpty {
                    settingMenu(.quality, title: Text("Quality"), value: qualityValue) {
                        Picker(selection: Binding(get: { selectedQuality }, set: { onQuality($0) })) {
                            Text("Auto").tag(Int?.none)
                            ForEach(qualities, id: \.self) { height in
                                Text(verbatim: VideoQuality.label(height)).tag(Optional(height))
                            }
                        } label: { Text("Quality") }
                    }
                }
                settingMenu(.sleep, title: Text("Sleep Timer"), value: sleepStatus.map { Text(verbatim: $0) } ?? Text("Off")) {
                    Picker(selection: Binding(get: { sleepChoice }, set: { onSleep($0) })) {
                        Text("Off").tag(SleepTimer.Choice?.none)
                        ForEach(SleepTimer.choices, id: \.self) { choice in
                            Text(verbatim: SleepTimer.label(for: choice)).tag(Optional(choice))
                        }
                    } label: { Text("Sleep Timer") }
                }
            }
            if !related.isEmpty {
                shelf(Text("Up Next")) {
                    ForEach(related) { row in
                        Button { onPlay(row.video) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                RemoteImage(row.thumbnails.best(forPixelWidth: 800)?.url, pointSize: CGSize(width: 400, height: 225))
                                    .frame(width: 400, height: 225)
                                    .clipped()
                                Text(row.title).font(.caption.weight(.medium)).lineLimit(2)
                                    .frame(width: 400, alignment: .leading)
                                    .padding([.horizontal, .bottom], 14)
                            }
                        }
                        .buttonStyle(.card)
                        .focused($focused, equals: .video(row.id))
                    }
                }
            }
        }
        .padding(.vertical, 40)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .center))
        .onAppear {
            if focusUpNext, let first = related.first { focused = .video(first.id) }
            else if !chapters.isEmpty { focused = .chapter(current ?? 0) }
            else if let first = related.first { focused = .video(first.id) }
        }
    }

    private var qualityValue: Text {
        if let selectedQuality { return Text(verbatim: VideoQuality.label(selectedQuality)) }
        if let playingHeight { return Text("Auto (\(VideoQuality.label(playingHeight)))") }
        return Text("Auto")
    }

    enum Setting: Hashable { case subtitles, audio, speed, quality, sleep }

    /// A setting's name and current value; selecting it opens its choices.
    private func settingMenu(_ setting: Setting, title: Text, value: Text,
                             @ViewBuilder choices: () -> some View) -> some View {
        Menu { choices() } label: {
            VStack(alignment: .leading, spacing: 6) {
                title.font(.caption).foregroundStyle(.secondary)
                value.font(.callout.weight(.medium)).lineLimit(1)
            }
            .frame(minWidth: 240, alignment: .leading)
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .focused($focused, equals: .setting(setting))
    }

    private func shelf(_ title: Text, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            title.font(.headline).padding(.horizontal, 80)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: TVMetrics.gridSpacing) { content() }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 20)
            }
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)   // A horizontal scroll view would take all the height.
        }
        .focusSection()
    }
}
