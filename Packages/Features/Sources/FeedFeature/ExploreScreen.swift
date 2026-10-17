import SwiftUI
import Core
import Library
import DesignSystem

/// Explore: trending videos, number one large, the rest as rows on a phone and a grid on wider
/// windows. Navigation is the app's to wire.
public struct ExploreScreen: View {
    private let model: ExploreModel
    private let onSelect: (FeedRow) -> Void
    private let onPrefetch: (FeedRow) -> Void
    private let onOpenChannel: (ChannelID, String) -> Void
    private let onAddToQueue: (FeedRow) -> Void
    private let onSetWatched: (FeedRow, Bool) -> Void
    private let onSaveToWatchLater: (FeedRow) -> Void
    private let onSaveToPlaylist: (FeedRow) -> Void
    private let transition: Namespace.ID?
    @Environment(\.displayScale) private var displayScale
    @State private var contentWidth: CGFloat = 390

    public init(model: ExploreModel, transition: Namespace.ID? = nil,
                onSelect: @escaping (FeedRow) -> Void, onPrefetch: @escaping (FeedRow) -> Void = { _ in },
                onOpenChannel: @escaping (ChannelID, String) -> Void = { _, _ in },
                onAddToQueue: @escaping (FeedRow) -> Void = { _ in },
                onSetWatched: @escaping (FeedRow, Bool) -> Void = { _, _ in },
                onSaveToWatchLater: @escaping (FeedRow) -> Void = { _ in },
                onSaveToPlaylist: @escaping (FeedRow) -> Void = { _ in }) {
        self.model = model
        self.transition = transition
        self.onSelect = onSelect
        self.onPrefetch = onPrefetch
        self.onOpenChannel = onOpenChannel
        self.onAddToQueue = onAddToQueue
        self.onSetWatched = onSetWatched
        self.onSaveToWatchLater = onSaveToWatchLater
        self.onSaveToPlaylist = onSaveToPlaylist
    }

    public var body: some View {
        content
            .navigationTitle(Text("Explore"))
            .refreshable { await model.refresh(force: true) }
            .task { await model.start() }
    }

    @ViewBuilder
    private var content: some View {
        list
    }

    /// All and Gaming, when the instances list them; it scrolls with the list.
    private var categoryChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Tokens.Spacing.s) {
                ForEach(model.categories, id: \.self) { category in
                    let selected = category == model.category
                    Button { model.select(category) } label: {
                        Label { Text(verbatim: category.title) } icon: { Image(systemName: category.symbol) }
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.glass)
                    .tint(selected ? Tokens.Colors.accent : nil)
                    .foregroundStyle(selected ? Tokens.Colors.accent : Tokens.Colors.textPrimary)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("explore.category")
                }
            }
            .padding(.vertical, Tokens.Spacing.xs)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: model.category)
    }

    @ViewBuilder
    private var list: some View {
        if let featured = model.featured {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Tokens.Spacing.section) {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
                        if model.categories.count > 1 { categoryChips }
                        Label { Text(verbatim: model.heading) } icon: { Image(systemName: "flame.fill") }
                            .font(Tokens.Typography.sectionTitle)
                            .foregroundStyle(Tokens.Colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        if let error = model.refreshError {
                            Text(error).font(Tokens.Typography.caption).foregroundStyle(Tokens.Colors.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HeroCard(VideoCellContent(row: featured, pixelWidth: Int(heroWidth * displayScale)), width: heroWidth)
                            .equatable()
                            .modifier(RowInteractions(row: featured, actions: rowActions, transition: transition))
                            .accessibilityIdentifier("explore.video")
                    }
                    if columns == 1 {
                        LazyVStack(alignment: .leading, spacing: Tokens.Spacing.m) {
                            ForEach(model.rows) { row in
                                VideoCell(VideoCellContent(row: row, pixelWidth: Int(FeedScreen.rowThumbnailWidth * displayScale)),
                                          style: .row, thumbnailWidth: FeedScreen.rowThumbnailWidth)
                                    .equatable()
                                    .modifier(RowInteractions(row: row, actions: rowActions, transition: transition))
                                    .accessibilityIdentifier("explore.video")
                            }
                        }
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.Spacing.l, alignment: .top),
                                                 count: columns),
                                  spacing: Tokens.Spacing.xl) {
                            ForEach(model.rows) { row in
                                VideoCell(VideoCellContent(row: row, pixelWidth: Int(thumbnailWidth * displayScale)),
                                          thumbnailWidth: thumbnailWidth)
                                    .equatable()
                                    .modifier(RowInteractions(row: row, actions: rowActions, transition: transition))
                                    .accessibilityIdentifier("explore.video")
                            }
                        }
                    }
                }
                .padding(.horizontal, Tokens.Spacing.screenInset)
                .padding(.vertical, Tokens.Spacing.l)
            }
            .accessibilityIdentifier("explore.list")
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        } else if model.isRefreshing || model.refreshError == nil {
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
                    if model.categories.count > 1 { categoryChips }   // Switch back while one loads.
                    LoadingPlaceholders(count: 4, style: .stacked, thumbnailWidth: max(contentWidth - 2 * Tokens.Spacing.screenInset, 100))
                }
                .padding(Tokens.Spacing.screenInset)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
        } else {
            ContentUnavailableView {
                Label { Text("Nothing to explore yet") } icon: { Image(systemName: "flame") }
            } description: {
                Text(model.refreshError ?? "")
            } actions: {
                Button { Task { await model.refresh(force: true) } } label: { Text("Try Again") }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private var rowActions: RowActions {
        RowActions(select: onSelect, prefetch: onPrefetch, openChannel: onOpenChannel, addToQueue: onAddToQueue,
                   setWatched: onSetWatched, hideChannel: nil,
                   saveToWatchLater: onSaveToWatchLater, saveToPlaylist: onSaveToPlaylist)
    }

    private var available: CGFloat { max(contentWidth - 2 * Tokens.Spacing.screenInset, 100) }

    private var heroWidth: CGFloat { available }

    private var columns: Int {
        max(1, Int((available + Tokens.Spacing.l) / (FeedScreen.minimumColumnWidth + Tokens.Spacing.l)))
    }

    private var thumbnailWidth: CGFloat {
        let count = CGFloat(columns)
        return (available - (count - 1) * Tokens.Spacing.l) / count
    }
}
