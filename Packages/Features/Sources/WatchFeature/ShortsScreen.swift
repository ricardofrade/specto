import SwiftUI
import Core
import Playback
import PlaybackUI
import DesignSystem

/// What the Shorts player shows: the shelf's Shorts, starting at the one tapped.
public struct ShortsContent: Identifiable, Equatable {
    public let id = UUID()
    public let videos: [VideoSummary]
    public let start: Int

    public init(videos: [VideoSummary], start: Int) {
        self.videos = videos
        self.start = min(max(start, 0), max(videos.count - 1, 0))
    }
}

#if os(iOS)
/// Shorts, full screen, one per page: swipe up for the next. The one on screen plays in the
/// app's single session; when it ends, auto-advance plays the next and the pager follows.
public struct ShortsScreen: View {
    let session: PlaybackSession
    let content: ShortsContent
    let onShow: (VideoSummary) -> Void
    let onClose: () -> Void
    @State private var current: VideoID?

    /// - Parameters:
    ///   - onShow: play this Short (it's now on screen).
    public init(session: PlaybackSession, content: ShortsContent, onShow: @escaping (VideoSummary) -> Void,
                onClose: @escaping () -> Void) {
        self.session = session
        self.content = content
        self.onShow = onShow
        self.onClose = onClose
        _current = State(initialValue: content.videos.indices.contains(content.start) ? content.videos[content.start].id : nil)
    }

    public var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(content.videos) { video in
                    ShortPage(video: video, session: session, isCurrent: video.id == current)
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $current)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        .background(.black)
        .overlay(alignment: .topLeading) {
            Button(action: onClose) {
                Label { Text("Close") } icon: { Image(systemName: "xmark") }
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .padding(Tokens.Spacing.l)
            .accessibilityIdentifier("shorts.close")
        }
        .environment(\.colorScheme, .dark)
        .task { if let video = video(current) { onShow(video) } }
        .onChange(of: current) { _, id in
            guard let video = video(id), session.item?.videoID != video.id else { return }
            onShow(video)
        }
        // Auto-advance played the next one: scroll to it.
        .onChange(of: session.item?.videoID) { _, id in
            guard let id, id != current, video(id) != nil else { return }
            withAnimation { current = id }
        }
    }

    private func video(_ id: VideoID?) -> VideoSummary? {
        content.videos.first { $0.id == id }
    }
}

/// One Short: the video while it's the current page, its thumbnail otherwise. Tap to pause.
private struct ShortPage: View {
    let video: VideoSummary
    let session: PlaybackSession
    let isCurrent: Bool

    var body: some View {
        ZStack {
            Color.black
            if isCurrent {
                PlayerSurface(session: session)
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .accessibilityIdentifier("shorts.surface")
                    // "<state> <video ID> <engine> <height> <seconds>", for UI tests.
                    .accessibilityValue(Text(verbatim: "\(session.state) \(video.id.rawValue) \(session.engineKind?.rawValue ?? "none") \(session.videoHeight.map { "\($0)p" } ?? "-") \(session.position.components.seconds)"))
            } else {
                RemoteImage(video.thumbnails.best(forPixelWidth: 1080)?.url, pointSize: CGSize(width: 360, height: 640))
                    .aspectRatio(9 / 16, contentMode: .fit)
                    .clipped()
            }
            if isCurrent, session.state == .paused {
                Image(systemName: "play.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            guard isCurrent else { return }
            if session.state == .playing { session.pause() } else { session.resume() }
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                Text(video.channelName).font(.subheadline.weight(.semibold))
                Text(video.title).font(.body).lineLimit(3)
            }
            .foregroundStyle(.white)
            .padding(Tokens.Spacing.l)
            .padding(.bottom, Tokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shorts.page")
    }
}
#endif
