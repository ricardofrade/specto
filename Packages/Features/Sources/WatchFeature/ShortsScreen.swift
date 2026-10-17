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
    let onSave: (VideoSummary) -> Void
    let onOpenChannel: (VideoSummary) -> Void
    @State private var current: VideoID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - onShow: play this Short (it's now on screen).
    ///   - onSave: to Watch Later.
    public init(session: PlaybackSession, content: ShortsContent, onShow: @escaping (VideoSummary) -> Void,
                onClose: @escaping () -> Void, onSave: @escaping (VideoSummary) -> Void = { _ in },
                onOpenChannel: @escaping (VideoSummary) -> Void = { _ in }) {
        self.session = session
        self.content = content
        self.onShow = onShow
        self.onClose = onClose
        self.onSave = onSave
        self.onOpenChannel = onOpenChannel
        _current = State(initialValue: content.videos.indices.contains(content.start) ? content.videos[content.start].id : nil)
    }

    public var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(content.videos) { video in
                    ShortPage(video: video, session: session, isCurrent: video.id == current,
                              onSave: { onSave(video) }, onOpenChannel: { onOpenChannel(video) })
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
            withAnimation(reduceMotion ? nil : .default) { current = id }
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
    let onSave: () -> Void
    let onOpenChannel: () -> Void
    @State private var saved = false

    var body: some View {
        // The page takes exactly the screen; the media fills it in an overlay, so its overflow
        // (a 9:16 video on a taller phone) is cropped without widening the page and pushing the
        // side rail off-screen.
        Color.black.overlay {
            // Edge to edge: a tall phone crops the sides a little rather than showing black bars.
            if isCurrent {
                PlayerSurface(session: session)
                    .aspectRatio(9 / 16, contentMode: .fill)
                    .accessibilityIdentifier("shorts.surface")
                    // "<state> <video ID> <engine> <height> <seconds>", for UI tests.
                    .accessibilityValue(Text(verbatim: "\(session.state) \(video.id.rawValue) \(session.engineKind?.rawValue ?? "none") \(session.videoHeight.map { "\($0)p" } ?? "-") \(session.position.components.seconds)"))
            } else {
                RemoteImage(video.thumbnails.best(forPixelWidth: 1080)?.url, pointSize: CGSize(width: 360, height: 640))
                    .aspectRatio(9 / 16, contentMode: .fill)
            }
        }
        .overlay {
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
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            // The side rail: the channel, Watch Later, Share.
            VStack(spacing: Tokens.Spacing.l) {
                Button(action: onOpenChannel) {
                    Label { Text(verbatim: video.channelName) } icon: { Image(systemName: "person.crop.circle") }
                }
                .accessibilityIdentifier("shorts.channel")
                Button {
                    onSave()
                    saved = true
                } label: {
                    Label { Text("Save to Watch Later") } icon: { Image(systemName: saved ? "clock.fill" : "clock") }
                }
                .accessibilityIdentifier("shorts.save")
                .accessibilityAddTraits(saved ? .isSelected : [])
                .sensoryFeedback(.success, trigger: saved)
                if let link = URL(string: "https://www.youtube.com/shorts/\(video.id.rawValue)") {
                    ShareLink(item: link) {
                        Label { Text("Share") } icon: { Image(systemName: "square.and.arrow.up") }
                    }
                    .accessibilityIdentifier("shorts.share")
                }
            }
            .labelStyle(.iconOnly)
            .font(.title2)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .padding(.trailing, Tokens.Spacing.m)
            .padding(.bottom, 120)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                Text(video.channelName).font(.subheadline.weight(.semibold))
                Text(video.title).font(.body).lineLimit(3)
            }
            .foregroundStyle(.white)
            .padding(Tokens.Spacing.l)
            .padding(.trailing, 72)   // Clear of the side rail.
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
