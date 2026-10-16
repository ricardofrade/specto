import SwiftUI
import Core
import Playback
import PlaybackUI
import DesignSystem

/// What the Watch screen shows: the video, and its details once loaded.
public struct WatchContent: Sendable, Equatable {
    public let video: VideoSummary
    public var details: VideoDetails?
    public var error: String?

    public init(video: VideoSummary, details: VideoDetails? = nil, error: String? = nil) {
        self.video = video
        self.details = details
        self.error = error
    }

    public static func == (lhs: WatchContent, rhs: WatchContent) -> Bool {
        lhs.video == rhs.video && lhs.details?.summary == rhs.details?.summary && lhs.error == rhs.error
    }
}

public struct WatchScreen: View {
    private let session: PlaybackSession
    private let content: WatchContent
    private let onSelectRelated: (VideoSummary) -> Void

    public init(session: PlaybackSession, content: WatchContent, onSelectRelated: @escaping (VideoSummary) -> Void) {
        self.session = session
        self.content = content
        self.onSelectRelated = onSelectRelated
    }

    public var body: some View {
        VStack(spacing: 0) {
            PlayerArea(session: session)
                .aspectRatio(16 / 9, contentMode: .fit)
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
                    Text(content.video.title)
                        .font(.title3.weight(.semibold))
                    Text(content.video.channelName)
                        .font(Tokens.Typography.cellMeta)
                        .foregroundStyle(Tokens.Colors.textSecondary)
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
                    if let related = content.details?.related, !related.isEmpty {
                        Text("Up next").font(.headline).padding(.top, Tokens.Spacing.m)
                        ForEach(related.prefix(15)) { video in
                            Button { onSelectRelated(video) } label: {
                                RelatedRow(video: video)
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

private struct RelatedRow: View {
    let video: VideoSummary

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.m) {
            AsyncImage(url: video.thumbnails.first?.url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Tokens.Colors.thumbnailPlaceholder
            }
            .frame(width: 160, height: 90)
            .clipShape(.rect(cornerRadius: Tokens.Radius.thumbnail))
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                Text(video.title).font(Tokens.Typography.cellMeta.weight(.semibold)).lineLimit(2)
                Text(video.channelName).font(Tokens.Typography.caption).foregroundStyle(Tokens.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
