import SwiftUI
import Core
import Library
import Playback
import PlaybackUI
import DesignSystem

/// What the Watch screen shows: the video, and its details once loaded.
public struct WatchContent: Sendable, Equatable {
    public let video: VideoSummary
    public var details: VideoDetails? {
        didSet { relatedRows = Self.format(details?.related ?? []) }
    }
    public private(set) var chapters: [ChapterRow] = []
    public var error: String?
    /// Pre-formatted once when details arrive, never in `body`.
    public private(set) var relatedRows: [FeedRow] = []

    public init(video: VideoSummary, details: VideoDetails? = nil, error: String? = nil) {
        self.video = video
        self.details = details
        self.error = error
        relatedRows = Self.format(details?.related ?? [])
    }

    public mutating func setChapters(_ chapters: [Chapter]) {
        self.chapters = ChapterRow.rows(chapters)
    }

    private static func format(_ videos: [VideoSummary]) -> [FeedRow] {
        let formatter = RowFormatter()
        return videos.prefix(15).map { formatter.row($0, positionSeconds: nil, durationSeconds: nil) }
    }

    public static func == (lhs: WatchContent, rhs: WatchContent) -> Bool {
        lhs.video == rhs.video && lhs.details?.summary == rhs.details?.summary
            && lhs.chapters == rhs.chapters && lhs.error == rhs.error
    }
}

public struct WatchScreen: View {
    private let session: PlaybackSession
    private let content: WatchContent
    private let makeComments: (() -> CommentsModel)?
    @State private var comments: CommentsModel?
    private let showsRelated: Bool
    private let onSelectRelated: (VideoSummary) -> Void
    private let onOpenChannel: (ChannelID, String) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dismiss) private var dismiss
    @State private var size = CGSize(width: 390, height: 844)

    /// - Parameters:
    ///   - comments: nil when no instance can load comments.
    ///   - showsRelated: YouTube's own "Up next" suggestions; a setting, off for some.
    ///   Created once per video, however often the parent re-renders.
    public init(session: PlaybackSession, content: WatchContent, comments: (() -> CommentsModel)? = nil,
                showsRelated: Bool = true,
                onSelectRelated: @escaping (VideoSummary) -> Void,
                onOpenChannel: @escaping (ChannelID, String) -> Void) {
        self.session = session
        self.content = content
        self.makeComments = comments
        self.showsRelated = showsRelated
        self.onSelectRelated = onSelectRelated
        self.onOpenChannel = onOpenChannel
    }

    public var body: some View {
        layout
            .overlay(alignment: .topLeading) {
                // Swipe down also closes; this is the visible, VoiceOver-reachable way.
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text("Close player"))
                .accessibilityIdentifier("watch.close")
                .padding(Tokens.Spacing.s)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .task(id: content.video.id) { comments = makeComments?() }
    }

    @ViewBuilder
    private var layout: some View {
        switch WatchLayout.choose(width: size.width, height: size.height, horizontal: horizontalSizeClass) {
        case .compact:
            VStack(spacing: 0) {
                player
                ScrollView { details }
            }
        case .band:
            VStack(spacing: 0) {
                player
                WatchTabs(content: content, comments: comments, session: session) { details }
            }
        case .sidePanel:
            HStack(spacing: 0) {
                player.frame(maxHeight: .infinity).background(.black)
                WatchTabs(content: content, comments: comments, session: session) { details }
                    .frame(width: min(400, size.width * 0.34))
            }
        }
    }

    /// Changing layout rebuilds this area: the new surface attaches and the session ignores the
    /// old one's late detach, so the video layer just moves and playback never reloads.
    private var player: some View {
        PlayerArea(session: session)
            .aspectRatio(16 / 9, contentMode: .fit)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            Text(content.video.title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Button { onOpenChannel(content.video.channelID, content.video.channelName) } label: {
                Label { Text(content.video.channelName) } icon: { Image(systemName: "person.crop.circle") }
                    .font(Tokens.Typography.cellMeta.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Tokens.Colors.textSecondary)
            .accessibilityIdentifier("watch.channel")
            .accessibilityHint(Text("Opens the channel"))
            if let error = content.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            if let description = content.details?.description, !description.isEmpty {
                Text(description)
                    .font(Tokens.Typography.body)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
            if showsRelated, !content.relatedRows.isEmpty {
                Text("Up next").font(.headline).padding(.top, Tokens.Spacing.m)
                    .accessibilityAddTraits(.isHeader)
                ForEach(content.relatedRows) { row in
                    Button { onSelectRelated(row.video) } label: {
                        VideoCell(VideoCellContent(row: row, pixelWidth: Int(160 * displayScale)),
                                  style: .row, thumbnailWidth: 160)
                            .equatable()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Tokens.Spacing.screenInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The surface plus transport controls that show on tap and fade during playback.
private struct PlayerArea: View {
    let session: PlaybackSession
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            PlayerSurface(session: session)
                .accessibilityIdentifier("watch.surface")
                // "<state> <seconds>": read by UI tests that check playback never stalls.
                .accessibilityValue(Text(verbatim: "\(session.state) \(session.position.components.seconds)"))
            if controlsVisible {
                PlayerControlCluster(isPlaying: session.state == .playing,
                                     captionsAvailable: false) { action in
                    handle(action)
                }
                .transition(.opacity)
            }
            if session.state == .loading || session.state == .buffering {
                ProgressView().tint(.white)
                    .accessibilityLabel(Text("Loading"))
            }
        }
        .background(.black)
        .contentShape(.rect)
        .onTapGesture { toggleControls() }
        .onChange(of: session.state) { _, state in
            if state == .playing { scheduleHide() } else { show() }
        }
        .sensoryFeedback(.selection, trigger: session.state == .playing)
    }

    private func handle(_ action: PlayerControlAction) {
        switch action {
        case .togglePlayback: session.state == .playing ? session.pause() : session.resume()
        case .skipBack: Task { await session.seek(to: max(.zero, session.position - .seconds(10))) }
        case .skipForward: Task { await session.seek(to: session.position + .seconds(10)) }
        case .captions: break
        }
        scheduleHide()
    }

    private func toggleControls() {
        if controlsVisible { hide() } else { show(); scheduleHide() }
    }

    private func show() {
        hideTask?.cancel()
        withAnimation(Tokens.Motion.standard) { controlsVisible = true }
    }

    /// Controls stay up under VoiceOver, which can't reach controls that fade away.
    private func hide() {
        guard !UIAccessibility.isVoiceOverRunning else { return }
        withAnimation(Tokens.Motion.standard) { controlsVisible = false }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard session.state == .playing else { return }
        hideTask = Task {
            try? await Task.sleep(for: Tokens.Motion.controlsAutoHide)
            if !Task.isCancelled { hide() }
        }
    }
}

extension VideoCellContent {
    init(row: FeedRow, pixelWidth: Int) {
        self.init(title: row.title, channelName: row.channelName, detail: row.detail, durationText: row.durationText,
                  thumbnailURL: row.thumbnails.best(forPixelWidth: pixelWidth)?.url, isLive: row.isLive,
                  progress: row.progress)
    }
}
