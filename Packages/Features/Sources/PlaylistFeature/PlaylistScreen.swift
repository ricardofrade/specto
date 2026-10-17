import SwiftUI
import Core
import Library
import DesignSystem

#if os(iOS)
/// A playlist: Play All, save to the Library, and its videos in order.
public struct PlaylistScreen: View {
    /// Owned here: the navigation destination that builds this screen can run again at any time.
    @State private var model: PlaylistModel
    private let onPlay: (_ videos: [VideoSummary], _ start: Int) -> Void
    @Environment(\.displayScale) private var displayScale

    /// - Parameter onPlay: plays `videos[start]`, then the rest in order.
    public init(model: PlaylistModel, onPlay: @escaping (_ videos: [VideoSummary], _ start: Int) -> Void) {
        _model = State(initialValue: model)
        self.onPlay = onPlay
    }

    public var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if let error = model.error, model.rows.isEmpty {
                Text(error).foregroundStyle(Tokens.Colors.textSecondary)
            }
            Section {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    Button { onPlay(model.rows.map(\.video), index) } label: {
                        VideoCell(VideoCellContent(row: row, pixelWidth: Int(140 * displayScale)), style: .row,
                                  thumbnailWidth: 140)
                            .equatable()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("playlist.video")
                    .task { await model.loadMoreIfNeeded(after: row.id) }
                }
                if model.isLoading {
                    if model.rows.isEmpty {
                        LoadingPlaceholders(count: 5)
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("playlist.list")
        .task { await model.loadFirstPage() }
    }

    private var header: some View {
        VStack(spacing: Tokens.Spacing.m) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay { RemoteImage(model.thumbnailURL, pointSize: CGSize(width: 320, height: 180)) }
                .clipShape(.rect(cornerRadius: Tokens.Radius.thumbnail))
                .frame(maxWidth: 320)
                .accessibilityHidden(true)
            VStack(spacing: Tokens.Spacing.xxs) {
                Text(model.title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                if let channel = model.channelName {
                    Text(channel).foregroundStyle(Tokens.Colors.textSecondary)
                }
                if let count = model.countText {
                    Text(count).font(Tokens.Typography.caption).foregroundStyle(Tokens.Colors.textSecondary)
                }
            }
            HStack(spacing: Tokens.Spacing.m) {
                Button {
                    Task {
                        let videos = await model.allVideos()
                        if !videos.isEmpty { onPlay(videos, 0) }
                    }
                } label: {
                    Label { Text("Play All") } icon: { Image(systemName: "play.fill") }
                        .frame(minWidth: 120)
                }
                .buttonStyle(.glassProminent)
                .disabled(model.rows.isEmpty)
                .accessibilityIdentifier("playlist.playAll")
                Button { model.toggleSaved() } label: {
                    Label { Text(model.isSaved ? "Saved" : "Save") } icon: {
                        Image(systemName: model.isSaved ? "bookmark.fill" : "bookmark")
                    }
                }
                .buttonStyle(.glass)
                .accessibilityIdentifier("playlist.save")
                .sensoryFeedback(.success, trigger: model.isSaved)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Tokens.Spacing.xl)
    }
}

extension VideoCellContent {
    init(row: FeedRow, pixelWidth: Int) {
        self.init(title: row.title, channelName: row.channelName, detail: row.detail, durationText: row.durationText,
                  thumbnailURL: row.thumbnails.best(forPixelWidth: pixelWidth)?.url, isLive: row.isLive,
                  progress: row.progress, isPeerTube: row.id.isPeerTube)
    }
}
#endif
