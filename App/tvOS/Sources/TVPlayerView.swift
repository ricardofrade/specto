import SwiftUI
import Core
import Library
import Playback
import PlaybackUI
import DesignSystem

/// Full-screen playback with the Siri Remote:
/// - Select or Play/Pause toggles playback.
/// - Left/right skip back 10 s and forward 10 s. Right after a SponsorBlock skip, left undoes it.
/// - Down opens chapters and Up Next (shown by itself when a video ends with nothing queued).
/// - Menu (Back) closes that panel, then the player.
struct TVPlayerView: View {
    let environment: AppEnvironment
    let video: VideoSummary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var title: String
    @State private var channelName: String
    @State private var chapters: [Chapter] = []
    /// Chapter start times, formatted once when the chapters load.
    @State private var chapterStarts: [String] = []
    @State private var error: String?
    @State private var transportVisible = true
    @State private var showsPanel = false
    /// The video's related videos ("Up next"), formatted once per page.
    @State private var related: [FeedRow] = []
    @State private var transport = TransportText()
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
            PlayerSurface(session: session)
                .accessibilityIdentifier("tv.player")
                // "<state> <engine> <seconds>": read by UI tests.
                .accessibilityValue(Text(verbatim: "\(session.state) \(session.engineKind?.rawValue ?? "none") \(session.position.components.seconds)"))
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
                          focusUpNext: session.state == .ended) { chapter in
                    Task { await session.seek(to: chapter.start, precise: false) }
                    closePanel()
                } onPlay: { video in
                    closePanel()
                    Task { await play(video) }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if transportVisible || session.state != .playing {
                TransportBar(title: title, channelName: channelName, text: transport,
                             isPlaying: session.state == .playing, hasChapters: !chapters.isEmpty || !related.isEmpty)
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
        case .down where !chapters.isEmpty || !related.isEmpty:
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
        transport = TransportText(position: session.position, duration: session.duration, chapters: chapters)
    }
}

/// Pre-formatted transport strings, rebuilt when the position changes (not in `body`).
struct TransportText: Equatable {
    var elapsed = ""
    var remaining = ""
    var fraction = 0.0
    var chapterTitle: String?
    var chapterIndex: Int?

    init() {}

    init(position: Duration, duration: Duration?, chapters: [Chapter]) {
        elapsed = RowFormatter.clock(position)
        if let duration, duration > .zero {
            remaining = "-" + RowFormatter.clock(max(.zero, duration - position))
            fraction = min(1, max(0, position / duration))
        }
        chapterIndex = chapters.lastIndex { $0.start <= position }
        chapterTitle = chapterIndex.map { chapters[$0].title }
    }
}

private struct TransportBar: View {
    let title: String
    let channelName: String
    let text: TransportText
    let isPlaying: Bool
    let hasChapters: Bool

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
                    Capsule().fill(.white)
                        .scaleEffect(x: text.fraction, y: 1, anchor: .leading)
                }
            HStack {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                Text(text.elapsed).monospacedDigit()
                Spacer()
                if hasChapters {
                    Label { Text("Chapters & Up Next") } icon: { Image(systemName: "chevron.down") }
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
    /// At the end of a video, focus starts on Up Next.
    let focusUpNext: Bool
    let onChapter: (Chapter) -> Void
    let onPlay: (VideoSummary) -> Void
    @FocusState private var focused: Focus?

    enum Focus: Hashable { case chapter(Int), video(VideoID) }

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
