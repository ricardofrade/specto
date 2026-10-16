import SwiftUI
import Core
import Library
import DesignSystem

/// The subscriptions feed. Navigation and empty-state actions are the app's to wire.
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
    private let transition: Namespace.ID?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    @State private var contentWidth: CGFloat = 390

    /// - Parameters:
    ///   - emptyReason: why there is nothing to show yet, when the feed is empty.
    ///   - onPrefetch: a row became likely to be tapped (touch-down, top of the list).
    /// - Parameter transition: namespace for the zoom into the Watch screen (source id: the row id).
    public init(model: FeedModel, emptyReason: EmptyReason?, transition: Namespace.ID? = nil,
                onEmptyAction: @escaping () -> Void,
                onSelect: @escaping (FeedRow) -> Void, onPrefetch: @escaping (FeedRow) -> Void = { _ in },
                onOpenChannel: @escaping (ChannelID, String) -> Void = { _, _ in },
                onAddToQueue: @escaping (FeedRow) -> Void = { _ in }) {
        self.transition = transition
        self.onAddToQueue = onAddToQueue
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
            .navigationTitle(Text("Subscriptions", comment: "Feed screen title"))
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
                if let error = model.refreshError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Tokens.Spacing.screenInset)
                }
                // One column on a phone, more as width allows (unfolded, iPad, wide windows).
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.minimumColumnWidth), spacing: Tokens.Spacing.l,
                                            alignment: .top)],
                          spacing: Tokens.Spacing.xl) {
                    ForEach(model.rows) { row in
                        VideoCell(VideoCellContent(row: row, pixelWidth: Int(thumbnailWidth * displayScale)),
                                  thumbnailWidth: thumbnailWidth)
                            .equatable()
                            .zoomSource(id: row.id, in: transition)
                            .contentShape(.rect)
                            .onAppear { model.rowAppeared(row.id) }
                            .contextMenu {
                                Button { onAddToQueue(row) } label: {
                                    Label { Text("Add to Queue") } icon: { Image(systemName: "text.badge.plus") }
                                }
                                Button { onOpenChannel(row.channelID, row.channelName) } label: {
                                    Label { Text("Go to Channel") } icon: { Image(systemName: "person.crop.circle") }
                                }
                            }
                            .onTapGesture { onSelect(row) }
                            .onLongPressGesture(minimumDuration: 0.3) { onPrefetch(row) } onPressingChanged: { pressing in
                                if pressing { onPrefetch(row) }
                            }
                    }
                }
                .padding(.horizontal, Tokens.Spacing.screenInset)
                .padding(.vertical, Tokens.Spacing.l)
            }
            .accessibilityIdentifier("feed.list")
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                contentWidth = width
                model.thumbnailPixelSize = CGSize(width: thumbnailWidth * displayScale,
                                                  height: thumbnailWidth * 9 / 16 * displayScale)
            }
        }
    }

    static let minimumColumnWidth: CGFloat = 320

    /// Mirrors the adaptive grid: as many columns of at least 320 pt as fit, sharing the width.
    private var thumbnailWidth: CGFloat {
        let available = max(contentWidth - 2 * Tokens.Spacing.screenInset, 100)
        let columns = max(1, floor((available + Tokens.Spacing.l) / (Self.minimumColumnWidth + Tokens.Spacing.l)))
        return (available - (columns - 1) * Tokens.Spacing.l) / columns
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
            ContentUnavailableView {
                Label { Text("No subscriptions") } icon: { Image(systemName: "person.2") }
            } description: {
                Text("Import your subscriptions from YouTube, NewPipe, FreeTube or Piped.")
            } actions: {
                Button { onEmptyAction() } label: { Text("Import Subscriptions") }
                    .buttonStyle(.glassProminent)
            }
        case nil:
            if model.isRefreshing {
                ProgressView()
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
