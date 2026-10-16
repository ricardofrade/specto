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
    public var error: String?
    /// Pre-formatted once when details arrive, never in `body`.
    public private(set) var relatedRows: [FeedRow] = []

    public init(video: VideoSummary, details: VideoDetails? = nil, error: String? = nil) {
        self.video = video
        self.details = details
        self.error = error
        relatedRows = Self.format(details?.related ?? [])
    }

    private static func format(_ videos: [VideoSummary]) -> [FeedRow] {
        let formatter = RowFormatter()
        return videos.prefix(15).map { formatter.row($0, positionSeconds: nil, durationSeconds: nil) }
    }

    public static func == (lhs: WatchContent, rhs: WatchContent) -> Bool {
        lhs.video == rhs.video && lhs.details?.summary == rhs.details?.summary && lhs.error == rhs.error
    }
}

public struct WatchScreen: View {
    private let session: PlaybackSession
    private let content: WatchContent
    private let showsRelated: Bool
    private let onSelectRelated: (VideoSummary) -> Void
    private let onOpenChannel: (ChannelID, String) -> Void
    @Environment(\.displayScale) private var displayScale

    /// - Parameter showsRelated: YouTube's own "Up next" suggestions; a setting, off for some.
    public init(session: PlaybackSession, content: WatchContent, showsRelated: Bool = true,
                onSelectRelated: @escaping (VideoSummary) -> Void,
                onOpenChannel: @escaping (ChannelID, String) -> Void) {
        self.session = session
        self.content = content
        self.showsRelated = showsRelated
        self.onSelectRelated = onSelectRelated
        self.onOpenChannel = onOpenChannel
    }

    public var body: some View {
        VStack(spacing: 0) {
            PlayerArea(session: session)
                .aspectRatio(16 / 9, contentMode: .fit)
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
                    Text(content.video.title)
                        .font(.title3.weight(.semibold))
                    Button { onOpenChannel(content.video.channelID, content.video.channelName) } label: {
                        Label { Text(content.video.channelName) } icon: { Image(systemName: "person.crop.circle") }
                            .font(Tokens.Typography.cellMeta.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .accessibilityIdentifier("watch.channel")
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
            }
        }
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
                .accessibilityValue(Text(verbatim: String(describing: session.state)))
            if controlsVisible {
                PlayerControlCluster(isPlaying: session.state == .playing,
                                     captionsAvailable: false) { action in
                    handle(action)
                }
                .transition(.opacity)
            }
            if session.state == .loading || session.state == .buffering {
                ProgressView().tint(.white)
            }
        }
        .background(.black)
        .contentShape(.rect)
        .onTapGesture { toggleControls() }
        .onChange(of: session.state) { _, state in
            if state == .playing { scheduleHide() } else { show() }
        }
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

    private func hide() {
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
