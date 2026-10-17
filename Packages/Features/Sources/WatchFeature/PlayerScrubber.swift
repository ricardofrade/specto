import SwiftUI
import Core
import Playback
import PlaybackUI
import DesignSystem

/// The progress bar: elapsed and remaining time, SponsorBlock segments and chapter starts marked
/// on the track, and drag to seek with a preview frame above the finger.
struct PlayerScrubber: View {
    let session: PlaybackSession
    let storyboard: Storyboard?
    let chapters: [ChapterRow]
    /// Called while dragging, so the controls don't fade mid-scrub.
    let onInteraction: () -> Void
    @State private var clock = TransportClock()
    /// The dragged fraction and its time, while scrubbing.
    @State private var scrub: (fraction: Double, text: String)?
    @State private var width: CGFloat = 1

    private static let previewWidth: CGFloat = 160

    var body: some View {
        VStack(spacing: Tokens.Spacing.xs) {
            track
            HStack {
                Text(verbatim: scrub?.text ?? clock.elapsed)
                Spacer()
                Text(verbatim: clock.remaining)
            }
            .font(Tokens.Typography.timecode)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 2)
        }
        .overlay(alignment: .topLeading) { preview }
        .onChange(of: session.position, initial: true) {
            clock = TransportClock(position: session.position, duration: session.duration)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Playback position"))
        .accessibilityValue(Text(verbatim: "\(clock.elapsed), \(clock.remaining)"))
        .accessibilityAdjustableAction { direction in
            let step: Duration = direction == .increment ? .seconds(10) : .seconds(-10)
            Task { await session.seek(to: max(.zero, session.position + step), precise: true) }
        }
        .accessibilityIdentifier("watch.scrubber")
    }

    private var track: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.3))
            segmentMarks
            Capsule().fill(.white).scaleEffect(x: fraction, y: 1, anchor: .leading)
            chapterMarks
            thumb
        }
        .frame(height: scrub == nil ? 4 : 8)
        .frame(height: 28)
        .contentShape(.rect)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
        .gesture(drag)
        .animation(Tokens.Motion.snappy, value: scrub == nil)
    }

    private var fraction: Double { scrub?.fraction ?? clock.fraction }

    /// Where a position falls on the track, in points.
    private func x(_ position: Duration) -> CGFloat {
        guard let duration = session.duration, duration > .zero else { return 0 }
        return width * CGFloat(position / duration)
    }

    private var segmentMarks: some View {
        ForEach(session.skipSegments, id: \.self) { segment in
            Rectangle()
                .fill(Color.yellow.opacity(0.85))
                .frame(width: max(2, x(segment.end) - x(segment.start)))
                .offset(x: x(segment.start))
        }
    }

    private var chapterMarks: some View {
        ForEach(chapters.dropFirst()) { chapter in
            Rectangle().fill(.black.opacity(0.6)).frame(width: 2).offset(x: x(chapter.start))
        }
    }

    private var thumb: some View {
        let diameter: CGFloat = scrub == nil ? 12 : 18
        return Circle().fill(.white)
            .frame(width: diameter, height: diameter)
            .offset(x: width * CGFloat(fraction) - diameter / 2)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dragged = min(1, max(0, Double(value.location.x / width)))
                scrub = (dragged, TransportClock.format(target(dragged), longest: session.duration))
                onInteraction()
            }
            .onEnded { _ in
                guard let scrub else { return }
                let position = target(scrub.fraction)
                Task { await session.seek(to: position, precise: true) }
                self.scrub = nil
            }
    }

    @ViewBuilder
    private var preview: some View {
        if let scrub, let storyboard, let frame = storyboard.frame(at: target(scrub.fraction)) {
            VStack(spacing: Tokens.Spacing.xs) {
                StoryboardFrameView(page: frame.page, origin: CGPoint(x: frame.x, y: frame.y),
                                    frameSize: CGSize(width: storyboard.frameWidth, height: storyboard.frameHeight),
                                    pageSize: CGSize(width: storyboard.pageWidth, height: storyboard.pageHeight),
                                    displayWidth: Self.previewWidth)
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.8), lineWidth: 1.5) }
                Text(verbatim: scrub.text).font(Tokens.Typography.timecode).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2)
            }
            .offset(x: min(max(0, width * scrub.fraction - Self.previewWidth / 2), max(0, width - Self.previewWidth)),
                    y: -(Self.previewWidth * 9 / 16) - 34)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private func target(_ fraction: Double) -> Duration {
        (session.duration ?? .zero) * fraction
    }
}
