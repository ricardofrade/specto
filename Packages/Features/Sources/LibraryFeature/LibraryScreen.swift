import SwiftUI
import Core
import Library
import DesignSystem

#if os(iOS)
/// Library (iPhone and iPad; Apple TV has its own view on the same model): Continue Watching as a shelf, the queue (drag to reorder, swipe to remove) and the
/// history (swipe to remove, or clear it all). Navigation is the app's to wire.
public struct LibraryScreen: View {
    private let model: LibraryModel
    private let onSelect: (FeedRow) -> Void
    private let onOpenChannel: (ChannelID, String) -> Void
    private let onOpenChannels: () -> Void
    private let onOpenPlaylists: () -> Void
    private let onOpenPlaylist: (LibraryPlaylistCard.Target) -> Void
    private let onExplore: (() -> Void)?
    @State private var confirmingClear = false
    @State private var query = ""
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var displayScale

    public init(model: LibraryModel, onSelect: @escaping (FeedRow) -> Void,
                onOpenChannel: @escaping (ChannelID, String) -> Void = { _, _ in },
                onOpenChannels: @escaping () -> Void = {}, onOpenPlaylists: @escaping () -> Void = {},
                onOpenPlaylist: @escaping (LibraryPlaylistCard.Target) -> Void = { _ in },
                onExplore: (() -> Void)? = nil) {
        self.onOpenPlaylist = onOpenPlaylist
        self.onExplore = onExplore
        self.model = model
        self.onSelect = onSelect
        self.onOpenChannel = onOpenChannel
        self.onOpenChannels = onOpenChannels
        self.onOpenPlaylists = onOpenPlaylists
    }

    public var body: some View {
        Group {
            if let results = model.historyResults {
                searchResults(results)
            } else if model.isEmpty {
                ContentUnavailableView {
                    Label { Text("Nothing here yet") } icon: { Image(systemName: "books.vertical") }
                } description: {
                    Text("What you watch, queue and save to Watch Later or your playlists gathers here, with your channels.")
                } actions: {
                    if let onExplore {
                        Button(action: onExplore) { Text("Find Something to Watch") }
                            .buttonStyle(.glassProminent)
                    }
                }
            } else {
                list
            }
        }
        .navigationTitle(Text("Library"))
        .searchable(text: $query, prompt: Text("Search History"))
        .task(id: query) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }   // Settle while typing.
            guard !Task.isCancelled else { return }
            await model.searchHistory(query)
        }
        .task { await model.start() }
        .confirmationDialog(Text("Clear your watch history?"), isPresented: $confirmingClear, titleVisibility: .visible) {
            Button(role: .destructive) { model.clearHistory() } label: { Text("Clear History") }
        } message: {
            Text("Resume positions are forgotten too, on every device that syncs.")
        }
    }

    private var list: some View {
        List {
            if !model.playlistCards.isEmpty {
                Section {
                    shelf {
                        ForEach(model.playlistCards) { card in
                            Button { onOpenPlaylist(card.target) } label: { PlaylistCardView(card: card) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("library.playlistCard")
                        }
                    }
                } header: {
                    shelfHeader(Text("Playlists"), count: model.playlistCount, action: onOpenPlaylists)
                        .accessibilityIdentifier("library.playlists")
                }
            }
            if !model.channelItems.isEmpty {
                Section {
                    shelf {
                        ForEach(model.channelItems) { item in
                            Button { onOpenChannel(item.channel.id, item.channel.name) } label: {
                                VStack(spacing: Tokens.Spacing.xs) {
                                    AvatarView(item.avatar, size: 64)
                                    // Left out at accessibility sizes, where it would be a letter
                                    // or two wide; VoiceOver still reads it.
                                    if !typeSize.isAccessibilitySize {
                                        Text(verbatim: item.channel.name)
                                            .font(.caption)
                                            .foregroundStyle(Tokens.Colors.textSecondary)
                                            .lineLimit(1)
                                            .frame(width: 76)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: item.channel.name))
                            .accessibilityIdentifier("library.channelItem")
                        }
                    }
                } header: {
                    shelfHeader(Text("Channels"), count: model.channelCount, action: onOpenChannels)
                        .accessibilityIdentifier("library.channels")
                }
            }
            if !model.continueWatching.isEmpty {
                Section {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: Tokens.Spacing.l) {
                            ForEach(model.continueWatching) { row in
                                Button { onSelect(row) } label: {
                                    VideoCell(VideoCellContent(row: row, pixelWidth: Int(220 * displayScale)), thumbnailWidth: 220)
                                        .equatable()
                                        .frame(width: 220)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Tokens.Spacing.screenInset)
                    }
                    .scrollIndicators(.hidden)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Continue Watching")
                }
            }
            if !model.queue.isEmpty {
                Section {
                    ForEach(model.queue) { row in
                        cell(row)
                            .swipeActions { Button(role: .destructive) { model.removeFromQueue(row.id) } label: { Text("Remove") } }
                    }
                    .onMove { model.moveQueue(from: $0, to: $1) }
                } header: {
                    Text("Queue")
                }
            }
            if !model.history.isEmpty {
                Section {
                    ForEach(model.history) { row in
                        cell(row)
                            .accessibilityIdentifier("library.history")
                            .swipeActions { Button(role: .destructive) { model.removeFromHistory(row.id) } label: { Text("Remove") } }
                    }
                } header: {
                    Text("History")
                } footer: {
                    Button(role: .destructive) { confirmingClear = true } label: { Text("Clear History") }
                        .padding(.top, Tokens.Spacing.s)
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("library.list")
    }

    @ViewBuilder
    private func searchResults(_ results: [FeedRow]) -> some View {
        if results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                Section {
                    ForEach(results) { row in
                        cell(row).accessibilityIdentifier("library.historyResult")
                    }
                } header: {
                    Text("History")
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// A section title that opens the full list ("Playlists 12 ›"), like Music's Library.
    private func shelfHeader(_ title: Text, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.xs) {
                title.font(Tokens.Typography.sectionTitle).foregroundStyle(Tokens.Colors.textPrimary)
                Image(systemName: "chevron.forward")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(count, format: .number)
                    .font(.subheadline)
                    .foregroundStyle(Tokens.Colors.textSecondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityAddTraits(.isHeader)
    }

    /// A horizontal row of cards inside the list, edge to edge.
    private func shelf(@ViewBuilder content: () -> some View) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Tokens.Spacing.l) { content() }
                .padding(.horizontal, Tokens.Spacing.screenInset)
        }
        .scrollIndicators(.hidden)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private func cell(_ row: FeedRow) -> some View {
        Button { onSelect(row) } label: {
            VideoCell(VideoCellContent(row: row, pixelWidth: Int(140 * displayScale)), style: .row, thumbnailWidth: 140)
                .equatable()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onOpenChannel(row.channelID, row.channelName) } label: {
                Label { Text("Go to Channel") } icon: { Image(systemName: "person.crop.circle") }
            }
        }
    }
}

extension VideoCellContent {
    init(row: FeedRow, pixelWidth: Int) {
        self.init(title: row.title, channelName: row.channelName, detail: row.detail, durationText: row.durationText,
                  thumbnailURL: row.thumbnails.best(forPixelWidth: pixelWidth)?.url, isLive: row.isLive,
                  progress: row.progress, isPeerTube: row.id.isPeerTube)
    }
}
/// A playlist on Library's shelf: its first video's thumbnail (or a symbol), title and count.
private struct PlaylistCardView: View {
    let card: LibraryPlaylistCard

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: Tokens.Radius.thumbnail).fill(Tokens.Colors.accent.opacity(0.15))
                if let url = card.thumbnailURL {
                    RemoteImage(url, pointSize: CGSize(width: Self.width, height: Self.width * 9 / 16))
                } else {
                    Image(systemName: card.symbol).font(.title).foregroundStyle(Tokens.Colors.accent)
                }
            }
            .frame(width: Self.width, height: Self.width * 9 / 16)
            .clipShape(.rect(cornerRadius: Tokens.Radius.thumbnail))
            Text(verbatim: card.title)
                .font(Tokens.Typography.cellMeta.weight(.semibold))
                .foregroundStyle(Tokens.Colors.textPrimary)
                .lineLimit(1)
            if let subtitle = card.subtitle {
                Text(verbatim: subtitle)
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: Self.width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    static let width: CGFloat = 176
}
#endif
