import SwiftUI
import Core
import Library
import DesignSystem

/// Home: the newest unwatched video large at the top, Continue Watching and Queue shelves, then
/// the latest uploads from subscriptions. Navigation and empty-state actions are the app's to wire.
public struct FeedScreen: View {
    public enum EmptyReason: Sendable {
        case noInstance
        case noSubscriptions
    }

    private let model: FeedModel
    private let emptyReason: EmptyReason?
    private let onEmptyAction: () -> Void
    private let onSelect: (FeedRow) -> Void
    private let onPrefetch: (FeedRow) -> Void
    private let onOpenChannel: (ChannelID, String) -> Void
    private let onAddToQueue: (FeedRow) -> Void
    private let onSetWatched: (FeedRow, Bool) -> Void
    private let onHideChannel: (FeedRow) -> Void
    private let onOpenShorts: ([FeedRow], Int) -> Void
    private let onSaveToWatchLater: (FeedRow) -> Void
    private let onSaveToPlaylist: (FeedRow) -> Void
    private let transition: Namespace.ID?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var contentWidth: CGFloat = 390
    /// On a device that folds, grids keep an even column count so no card straddles the crease.
    @State private var canFold = false

    /// - Parameters:
    ///   - emptyReason: why there is nothing to show yet, when the feed is empty.
    ///   - onPrefetch: a row became likely to be tapped (touch-down, top of the list).
    /// - Parameter transition: namespace for the zoom into the Watch screen (source id: the row id).
    public init(model: FeedModel, emptyReason: EmptyReason?, transition: Namespace.ID? = nil,
                onEmptyAction: @escaping () -> Void,
                onSelect: @escaping (FeedRow) -> Void, onPrefetch: @escaping (FeedRow) -> Void = { _ in },
                onOpenChannel: @escaping (ChannelID, String) -> Void = { _, _ in },
                onAddToQueue: @escaping (FeedRow) -> Void = { _ in },
                onSetWatched: @escaping (FeedRow, Bool) -> Void = { _, _ in },
                onHideChannel: @escaping (FeedRow) -> Void = { _ in },
                onOpenShorts: @escaping (_ shorts: [FeedRow], _ start: Int) -> Void = { _, _ in },
                onSaveToWatchLater: @escaping (FeedRow) -> Void = { _ in },
                onSaveToPlaylist: @escaping (FeedRow) -> Void = { _ in }) {
        self.onSaveToWatchLater = onSaveToWatchLater
        self.onSaveToPlaylist = onSaveToPlaylist
        self.onOpenShorts = onOpenShorts
        self.transition = transition
        self.onAddToQueue = onAddToQueue
        self.onSetWatched = onSetWatched
        self.onHideChannel = onHideChannel
        self.onOpenChannel = onOpenChannel
        self.model = model
        self.emptyReason = emptyReason
        self.onEmptyAction = onEmptyAction
        self.onSelect = onSelect
        self.onPrefetch = onPrefetch
    }

    /// Hosted in the app's `NavigationStack`, which owns navigation (typed routes per scene).
    public var body: some View {
        content
            .navigationTitle(Text("Home", comment: "Home screen title"))
            .refreshable { await model.refresh(force: true) }
            .task {
                model.onWarmManifest = onPrefetch
                await model.start()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refresh(force: false) } }
            }
            .sensoryFeedback(.success, trigger: model.isRefreshing) { wasRefreshing, isRefreshing in
                wasRefreshing && !isRefreshing && model.refreshError == nil
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.rows.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Tokens.Spacing.section) {
                    if let error = model.refreshError {
                        // The text takes the row's width, so longer languages (German) wrap, never clip.
                        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.s) {
                            Image(systemName: "exclamationmark.triangle").accessibilityHidden(true)
                            Text(error).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .padding(.horizontal, Tokens.Spacing.screenInset)
                    }
                    if let featured = model.featured {
                        HeroCard(VideoCellContent(row: featured, pixelWidth: Int(heroWidth * displayScale)), width: heroWidth)
                            .equatable()
                            .modifier(RowInteractions(row: featured, actions: rowActions, transition: transition))
                            .onAppear { model.rowAppeared(featured.id) }
                            .padding(.horizontal, Tokens.Spacing.screenInset)
                    }
                    if !model.continueWatching.isEmpty {
                        Shelf(title: Text("Continue Watching"), rows: model.continueWatching,
                              cardWidth: shelfCardWidth, actions: rowActions, transition: transition)
                    }
                    if !model.queue.isEmpty {
                        Shelf(title: Text("Queue"), rows: model.queue, cardWidth: shelfCardWidth,
                              actions: rowActions, transition: transition)
                    }
                    if !model.shorts.isEmpty {
                        ShortsShelf(rows: model.shorts) { onOpenShorts(model.shorts, $0) }
                    }
                    ForEach(model.sections) { section in
                        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
                            Text(verbatim: section.title).font(Tokens.Typography.sectionTitle)
                                .accessibilityAddTraits(.isHeader)
                            if columns == 1, section.period != .today {
                                // A phone: older videos as compact rows, about three per card's height.
                                LazyVStack(alignment: .leading, spacing: Tokens.Spacing.m) {
                                    ForEach(section.rows) { row in
                                        VideoCell(VideoCellContent(row: row, pixelWidth: Int(Self.rowThumbnailWidth * displayScale)),
                                                  style: .row, thumbnailWidth: Self.rowThumbnailWidth)
                                            .equatable()
                                            .modifier(RowInteractions(row: row, actions: rowActions, transition: transition))
                                            .onAppear { model.rowAppeared(row.id) }
                                    }
                                }
                            } else {
                                // Today as large cards on a phone; more columns as width allows
                                // (unfolded, iPad, wide windows).
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.Spacing.l,
                                                                             alignment: .top), count: columns),
                                          spacing: Tokens.Spacing.xl) {
                                    ForEach(section.rows) { row in
                                        VideoCell(VideoCellContent(row: row, pixelWidth: Int(thumbnailWidth * displayScale)),
                                                  thumbnailWidth: thumbnailWidth)
                                            .equatable()
                                            .modifier(RowInteractions(row: row, actions: rowActions, transition: transition))
                                            .onAppear { model.rowAppeared(row.id) }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, Tokens.Spacing.screenInset)
                    }
                }
                .padding(.vertical, Tokens.Spacing.l)
            }
            .accessibilityIdentifier("feed.list")
            .onFoldChange { canFold = $0.isPresent }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                contentWidth = width
                model.thumbnailPixelSize = CGSize(width: thumbnailWidth * displayScale,
                                                  height: thumbnailWidth * 9 / 16 * displayScale)
            }
        }
    }

    static let minimumColumnWidth: CGFloat = 320
    /// Compact rows' thumbnail width on a phone.
    static let rowThumbnailWidth: CGFloat = 160

    private var rowActions: RowActions {
        RowActions(select: onSelect, prefetch: onPrefetch, openChannel: onOpenChannel, addToQueue: onAddToQueue,
                   setWatched: onSetWatched, hideChannel: onHideChannel,
                   saveToWatchLater: onSaveToWatchLater, saveToPlaylist: onSaveToPlaylist)
    }

    /// Full width; on wide windows `HeroCard` caps the height, so it stays a hero, not a wall.
    private var heroWidth: CGFloat {
        max(contentWidth - 2 * Tokens.Spacing.screenInset, 100)
    }

    /// About two and a half cards visible on a phone, so the shelf reads as scrollable.
    private var shelfCardWidth: CGFloat {
        min(max((contentWidth - Tokens.Spacing.screenInset) / 1.6, 220), 300)
    }

    /// As many columns of at least 320 pt as fit. Where the device folds, an even count (two
    /// narrower columns rather than one across the crease, when 240 pt each still fit).
    private var columns: Int {
        let available = max(contentWidth - 2 * Tokens.Spacing.screenInset, 100)
        let fitting = max(1, Int((available + Tokens.Spacing.l) / (Self.minimumColumnWidth + Tokens.Spacing.l)))
        guard canFold, fitting % 2 == 1 else { return fitting }
        let twoNarrow = available >= 2 * Self.minimumFoldColumnWidth + Tokens.Spacing.l
        return fitting == 1 ? (twoNarrow ? 2 : 1) : fitting - 1
    }

    static let minimumFoldColumnWidth: CGFloat = 240

    private var thumbnailWidth: CGFloat {
        let available = max(contentWidth - 2 * Tokens.Spacing.screenInset, 100)
        let count = CGFloat(columns)
        return (available - (count - 1) * Tokens.Spacing.l) / count
    }

    /// No subscriptions yet: how to bring them, then what's trending. Long-press a video to visit
    /// its channel and subscribe.
    private var explore: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Tokens.Spacing.section) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.s) {
                    Text("Build your Home").font(Tokens.Typography.sectionTitle)
                    Text("Import your subscriptions, or subscribe to channels you find below. Their new videos show up here.")
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { onEmptyAction() } label: { Text("Import Subscriptions") }
                        .buttonStyle(.glassProminent)
                        .padding(.top, Tokens.Spacing.xs)
                }
                .padding(.horizontal, Tokens.Spacing.screenInset)
                VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
                    Label { Text("Trending") } icon: { Image(systemName: "flame") }
                        .font(Tokens.Typography.sectionTitle)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.Spacing.l, alignment: .top),
                                             count: columns),
                              spacing: Tokens.Spacing.xl) {
                        ForEach(model.trending) { row in
                            VideoCell(VideoCellContent(row: row, pixelWidth: Int(thumbnailWidth * displayScale)),
                                      thumbnailWidth: thumbnailWidth)
                                .equatable()
                                .modifier(RowInteractions(row: row, actions: rowActions, transition: transition))
                                .accessibilityIdentifier("feed.trending")
                        }
                    }
                }
                .padding(.horizontal, Tokens.Spacing.screenInset)
            }
            .padding(.vertical, Tokens.Spacing.l)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch emptyReason {
        case .noInstance:
            ContentUnavailableView {
                Label { Text("Bring your own server") } icon: { Image(systemName: "server.rack") }
            } description: {
                Text("This app plays videos through a Piped, Invidious or YT Zero server that you run or trust. It has no servers of its own and collects nothing. Add yours to see your subscriptions here.")
            } actions: {
                Button { onEmptyAction() } label: { Text("Add Instance") }
                    .buttonStyle(.glassProminent)
            }
        case .noSubscriptions:
            if model.trending.isEmpty {
                ContentUnavailableView {
                    Label { Text("No subscriptions") } icon: { Image(systemName: "person.2") }
                } description: {
                    Text("Import your subscriptions from YouTube, NewPipe, FreeTube or Piped.")
                } actions: {
                    Button { onEmptyAction() } label: { Text("Import Subscriptions") }
                        .buttonStyle(.glassProminent)
                }
                .task { await model.loadTrendingIfNeeded() }
            } else {
                explore
            }
        case nil:
            if model.isRefreshing {
                ScrollView {
                    LoadingPlaceholders(count: 4, style: .stacked, thumbnailWidth: thumbnailWidth)
                        .padding(Tokens.Spacing.screenInset)
                }
            } else {
                ContentUnavailableView {
                    Label { Text("Nothing new") } icon: { Image(systemName: "checkmark.circle") }
                } description: {
                    Text(model.refreshError ?? String(localized: "New uploads from your subscriptions show up here."))
                }
            }
        }
    }
}

#Preview("Empty") {
    FeedScreen(model: FeedModel(store: FeedStore(try! AppDatabase.inMemory())) { _ in },
               emptyReason: .noInstance, onEmptyAction: {}, onSelect: { _ in })
}

/// What a row can do, shared by the hero, shelves and grid.
struct RowActions {
    let select: (FeedRow) -> Void
    let prefetch: (FeedRow) -> Void
    let openChannel: (ChannelID, String) -> Void
    let addToQueue: (FeedRow) -> Void
    let setWatched: (FeedRow, Bool) -> Void
    let hideChannel: (FeedRow) -> Void
    let saveToWatchLater: (FeedRow) -> Void
    let saveToPlaylist: (FeedRow) -> Void
}

/// Tap to play (zooming from this view), touch-down prefetch, and the context menu.
struct RowInteractions: ViewModifier {
    let row: FeedRow
    let actions: RowActions
    let transition: Namespace.ID?

    func body(content: Content) -> some View {
        content
            .zoomSource(id: row.id, in: transition)
            .contentShape(.rect)
            .contextMenu {
                Button { actions.addToQueue(row) } label: {
                    Label { Text("Add to Queue") } icon: { Image(systemName: "text.badge.plus") }
                }
                Button { actions.saveToWatchLater(row) } label: {
                    Label { Text("Save to Watch Later") } icon: { Image(systemName: "clock") }
                }
                Button { actions.saveToPlaylist(row) } label: {
                    Label { Text("Save to Playlist…") } icon: { Image(systemName: "bookmark") }
                }
                Button { actions.setWatched(row, !row.isWatched) } label: {
                    if row.isWatched {
                        Label { Text("Mark as Unwatched") } icon: { Image(systemName: "eye.slash") }
                    } else {
                        Label { Text("Mark as Watched") } icon: { Image(systemName: "checkmark.circle") }
                    }
                }
                Button { actions.openChannel(row.channelID, row.channelName) } label: {
                    Label { Text("Go to Channel") } icon: { Image(systemName: "person.crop.circle") }
                }
                Divider()
                Button(role: .destructive) { actions.hideChannel(row) } label: {
                    Label { Text("Hide \(row.channelName) from Home") } icon: { Image(systemName: "rectangle.slash") }
                }
            }
            .onTapGesture { actions.select(row) }
            .onLongPressGesture(minimumDuration: 0.3) { actions.prefetch(row) } onPressingChanged: { pressing in
                if pressing { actions.prefetch(row) }
            }
    }
}

/// A titled horizontal row of cards that snaps card by card.
struct Shelf: View {
    let title: Text
    let rows: [FeedRow]
    let cardWidth: CGFloat
    let actions: RowActions
    let transition: Namespace.ID?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            title.font(Tokens.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Tokens.Spacing.screenInset)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Tokens.Spacing.l) {
                    ForEach(rows) { row in
                        VideoCell(VideoCellContent(row: row, pixelWidth: Int(cardWidth * displayScale)),
                                  thumbnailWidth: cardWidth)
                            .equatable()
                            .frame(width: cardWidth)
                            .modifier(RowInteractions(row: row, actions: actions, transition: transition))
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, Tokens.Spacing.screenInset)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}

private extension View {
    @ViewBuilder
    func zoomSource(id: some Hashable, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
