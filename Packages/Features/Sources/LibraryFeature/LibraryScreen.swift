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
    @State private var confirmingClear = false
    @State private var query = ""
    @Environment(\.displayScale) private var displayScale

    public init(model: LibraryModel, onSelect: @escaping (FeedRow) -> Void,
                onOpenChannel: @escaping (ChannelID, String) -> Void = { _, _ in },
                onOpenChannels: @escaping () -> Void = {}, onOpenPlaylists: @escaping () -> Void = {}) {
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
                    Text("Videos you watch and queue show up here.")
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
            if model.channelCount > 0 || model.playlistCount > 0 {
                Section {
                    if model.channelCount > 0 {
                        destinationRow(count: model.channelCount, action: onOpenChannels) {
                            Label { Text("Channels") } icon: { Image(systemName: "person.2") }
                        }
                        .accessibilityIdentifier("library.channels")
                    }
                    if model.playlistCount > 0 {
                        destinationRow(count: model.playlistCount, action: onOpenPlaylists) {
                            Label { Text("Playlists") } icon: { Image(systemName: "list.bullet.rectangle") }
                        }
                        .accessibilityIdentifier("library.playlists")
                    }
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

    /// A row that pushes a list (Channels, Playlists), with its count, like Music's Library.
    private func destinationRow(count: Int, action: @escaping () -> Void,
                                @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            LabeledContent {
                HStack(spacing: Tokens.Spacing.xs) {
                    Text(count, format: .number)
                    Image(systemName: "chevron.forward").font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            } label: {
                label()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
                  progress: row.progress)
    }
}
#endif
