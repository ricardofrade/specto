import SwiftUI
import Core
import Library
import DesignSystem

@Observable
public final class ChannelModel {
    public let channelID: ChannelID
    public private(set) var name: String
    public private(set) var avatarURL: URL?
    public private(set) var rows: [FeedRow] = []
    public private(set) var isSubscribed: Bool
    public private(set) var isLoading = false
    public private(set) var error: String?

    @ObservationIgnored private let load: @Sendable (ChannelID, String?) async throws -> ChannelPage
    @ObservationIgnored private let setSubscribed: @Sendable (ChannelSummary, Bool) async throws -> Void
    @ObservationIgnored private var cursor: String?
    @ObservationIgnored private var loadedFirstPage = false

    /// - Parameters:
    ///   - cached: videos already in the local database, shown before the network answers.
    public init(channelID: ChannelID, name: String, cached: [VideoSummary], isSubscribed: Bool,
                load: @escaping @Sendable (ChannelID, String?) async throws -> ChannelPage,
                setSubscribed: @escaping @Sendable (ChannelSummary, Bool) async throws -> Void) {
        self.channelID = channelID
        self.name = name
        self.isSubscribed = isSubscribed
        self.load = load
        self.setSubscribed = setSubscribed
        rows = Self.format(cached)
    }

    public func loadFirstPage() async {
        guard !loadedFirstPage else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await load(channelID, nil)
            loadedFirstPage = true
            if !page.name.isEmpty { name = page.name }
            avatarURL = page.avatar?.url
            rows = Self.format(page.videos.items)
            cursor = page.videos.nextCursor
            error = nil
        } catch {
            if rows.isEmpty { self.error = String(localized: "Couldn't load this channel.") }
        }
    }

    public func loadMoreIfNeeded(after id: VideoID) async {
        guard id == rows.last?.id, let cursor, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard let page = try? await load(channelID, cursor) else { return }
        let known = Set(rows.map(\.id))
        rows += Self.format(page.videos.items.filter { !known.contains($0.id) })
        self.cursor = page.videos.nextCursor
    }

    public func toggleSubscription() async {
        let target = !isSubscribed
        isSubscribed = target        // Optimistic; reverted on failure.
        do {
            try await setSubscribed(ChannelSummary(id: channelID, name: name,
                                                   avatar: avatarURL.map { Thumbnail(url: $0, width: 0, height: 0) }),
                                    target)
        } catch {
            isSubscribed = !target
            self.error = String(localized: "Couldn't update the subscription.")
        }
    }

    static func format(_ videos: [VideoSummary]) -> [FeedRow] {
        let formatter = RowFormatter()
        return videos.map { formatter.row($0, positionSeconds: nil, durationSeconds: nil) }
    }
}

public struct ChannelScreen: View {
    private let makeModel: () -> ChannelModel
    private let onSelect: (VideoSummary) -> Void
    @State private var model: ChannelModel?

    /// The model is created once per screen, on first appearance, however often the parent
    /// re-renders.
    public init(model: @escaping @autoclosure () -> ChannelModel, onSelect: @escaping (VideoSummary) -> Void) {
        self.makeModel = model
        self.onSelect = onSelect
    }

    public var body: some View {
        if let model {
            ChannelContent(model: model, onSelect: onSelect)
        } else {
            Color.clear.onAppear { model = makeModel() }
        }
    }
}

private struct ChannelContent: View {
    let model: ChannelModel
    let onSelect: (VideoSummary) -> Void
    @Environment(\.displayScale) private var displayScale
    @State private var columnWidth: CGFloat = 340

    var body: some View {
        ScrollView {
            header
            if let error = model.error {
                Text(error).foregroundStyle(Tokens.Colors.textSecondary).padding()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: Tokens.Spacing.l)],
                      spacing: Tokens.Spacing.xl) {
                ForEach(model.rows) { row in
                    Button { onSelect(row.video) } label: {
                        VideoCell(VideoCellContent(row: row, pixelWidth: Int(columnWidth * displayScale)),
                                  thumbnailWidth: columnWidth)
                            .equatable()
                    }
                    .buttonStyle(.plain)
                    .task { await model.loadMoreIfNeeded(after: row.id) }
                }
            }
            .padding(.horizontal, Tokens.Spacing.screenInset)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                columnWidth = Self.columnWidth(for: width - 2 * Tokens.Spacing.screenInset)
            }
            if model.isLoading { ProgressView().padding() }
        }
        .navigationTitle(model.name)
        .inlineNavigationTitle()
        .task { await model.loadFirstPage() }
    }

    private var header: some View {
        VStack(spacing: Tokens.Spacing.m) {
            RemoteImage(model.avatarURL, pointSize: CGSize(width: 88, height: 88))
                .frame(width: 88, height: 88)
                .clipShape(.circle)
                .accessibilityHidden(true)
            Text(model.name).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
            Button { Task { await model.toggleSubscription() } } label: {
                Text(model.isSubscribed ? "Subscribed" : "Subscribe")
                    .frame(minWidth: 140)
            }
            .buttonStyle(.glassProminent)
            .tint(model.isSubscribed ? .gray : .accentColor)
            .accessibilityIdentifier("channel.subscribe")
            .sensoryFeedback(.success, trigger: model.isSubscribed)
        }
        .padding(Tokens.Spacing.xl)
    }

    /// Mirrors `.adaptive(minimum: 300)`: as many 300-pt columns as fit, sharing the width.
    static func columnWidth(for width: CGFloat) -> CGFloat {
        let columns = max(1, floor((width + Tokens.Spacing.l) / (300 + Tokens.Spacing.l)))
        return (width - (columns - 1) * Tokens.Spacing.l) / columns
    }
}

extension VideoCellContent {
    init(row: FeedRow, pixelWidth: Int) {
        self.init(title: row.title, channelName: row.channelName, detail: row.detail, durationText: row.durationText,
                  thumbnailURL: row.thumbnails.best(forPixelWidth: pixelWidth)?.url, isLive: row.isLive,
                  progress: row.progress)
    }
}
