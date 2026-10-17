import SwiftUI
import Core
import Library
import DesignSystem

/// The newest unwatched video, full-bleed under the tab bar like the Apple TV app's billboard,
/// with Play, Add to Queue and the channel as focusable buttons.
struct Billboard: View {
    let row: FeedRow
    let actions: VideoActions
    @Environment(\.displayScale) private var displayScale
    @FocusState private var focused: Action?

    private enum Action: Hashable { case play, queue, channel }

    static let height: CGFloat = 720

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(row.thumbnails.best(forPixelWidth: Int(1920 * displayScale))?.url,
                        pointSize: CGSize(width: 1920, height: 1080))
                .frame(height: Self.height)
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                }
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .leading, endPoint: .center)
                }
                .ignoresSafeArea(edges: [.top, .horizontal])
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 18) {
                Text(row.title)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                    .frame(maxWidth: 1100, alignment: .leading)
                HStack(spacing: 10) {
                    Text(row.channelName)
                    if !row.detail.isEmpty { Text(verbatim: "·"); Text(row.detail) }
                }
                .font(.callout)
                .opacity(0.85)
                HStack(spacing: 24) {
                    Button { actions.play(row.video) } label: {
                        Label { Text("Play") } icon: { Image(systemName: "play.fill") }
                    }
                    .focused($focused, equals: .play)
                    Button { actions.addToQueue(row.video) } label: {
                        Label { Text("Add to Queue") } icon: { Image(systemName: "text.badge.plus") }
                    }
                    .focused($focused, equals: .queue)
                    Button { actions.openChannel(row.channelID, row.channelName) } label: {
                        Label { Text(row.channelName) } icon: { Image(systemName: "person.crop.circle") }
                    }
                    .focused($focused, equals: .channel)
                }
                // A full-width row below the tab bar, so coming down from any tab lands here, on Play.
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
                .defaultFocus($focused, .play, priority: .userInitiated)
                .padding(.top, 8)
            }
            .foregroundStyle(.white)
            .padding(.bottom, 50)
        }
        .frame(height: Self.height)
    }
}
