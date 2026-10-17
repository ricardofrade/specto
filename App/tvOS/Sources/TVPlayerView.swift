import SwiftUI
import Core
import Library
import Playback
import PlaybackUI
import DesignSystem

/// Full-screen playback with the Siri Remote:
/// - Select or Play/Pause toggles playback.
/// - Left/right skip back 10 s and forward 10 s. Right after a SponsorBlock skip, left undoes it.
/// - Down opens the chapters; up shows the transport bar.
/// - Menu (Back) closes the chapters, then the player.
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
    @State private var showsChapters = false
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
            if showsChapters {
                ChaptersShelf(chapters: chapters, starts: chapterStarts, current: transport.chapterIndex) { chapter in
                    Task { await session.seek(to: chapter.start, precise: false) }
                    closeChapters()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if transportVisible || session.state != .playing {
                TransportBar(title: title, channelName: channelName, text: transport,
                             isPlaying: session.state == .playing, hasChapters: !chapters.isEmpty)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .focusable(!showsChapters)
        .focused($playerFocused)
        .onTapGesture(perform: togglePlayback)
        .onPlayPauseCommand(perform: togglePlayback)
        .onMoveCommand(perform: move)
        .onExitCommand(perform: exit)
        .onChange(of: session.position) { updateTransport() }
        // The queue can advance to the next video while this screen stays up.
        .onChange(of: session.item?.videoID) { adoptCurrentItem() }
        .onChange(of: session.lastSkipped) { _, segment in
            guard let segment else { return }
            withAnimation(Tokens.Motion.standard) { skipped = (segment, .now) }
            Task {
                try? await Task.sleep(for: .seconds(5))
                withAnimation(Tokens.Motion.standard) { if skipped?.segment == segment { skipped = nil } }
            }
        }
        .task { await start() }
        .onAppear {
            playerFocused = true
            revealTransport()
        }
    }

    // MARK: Actions

    private func start() async {
        do {
            let page = try await environment.play(video, surfaceHeight: Int(1080 * displayScale))
            adoptCurrentItem()
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
        case .down where !chapters.isEmpty:
            withAnimation(Tokens.Motion.standard) { showsChapters = true }
        default:
            break
        }
        revealTransport()
    }

    private func seek(by offset: Duration) {
        let target = max(.zero, session.position + offset)
        Task { await session.seek(to: session.duration.map { min($0, target) } ?? target, precise: false) }
    }

    private func exit() {
        if showsChapters {
            closeChapters()
        } else {
            session.stop()
            dismiss()
        }
    }

    private func closeChapters() {
        withAnimation(Tokens.Motion.standard) { showsChapters = false }
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
                    Label { Text("Chapters") } icon: { Image(systemName: "chevron.down") }
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

private struct ChaptersShelf: View {
    let chapters: [Chapter]
    let starts: [String]
    let current: Int?
    let onSelect: (Chapter) -> Void
    @FocusState private var focused: Int?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: TVMetrics.gridSpacing) {
                ForEach(chapters.indices, id: \.self) { index in
                    Button { onSelect(chapters[index]) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(chapters[index].title).font(.callout.weight(.medium)).lineLimit(2)
                            Text(starts[index]).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(width: 360, height: 120, alignment: .topLeading)
                        .padding(24)
                    }
                    .buttonStyle(.card)
                    .focused($focused, equals: index)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
        .scrollClipDisabled()
        .padding(.bottom, 40)
        .onAppear { focused = current ?? 0 }
    }
}
