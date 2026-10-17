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
    @State private var confirmingClear = false
    @Environment(\.displayScale) private var displayScale

    public init(model: LibraryModel, onSelect: @escaping (FeedRow) -> Void,
                onOpenChannel: @escaping (ChannelID, String) -> Void = { _, _ in }) {
        self.model = model
        self.onSelect = onSelect
        self.onOpenChannel = onOpenChannel
    }

    public var body: some View {
        Group {
            if model.isEmpty {
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
        .task { await model.start() }
        .confirmationDialog(Text("Clear your watch history?"), isPresented: $confirmingClear, titleVisibility: .visible) {
            Button(role: .destructive) { model.clearHistory() } label: { Text("Clear History") }
        } message: {
            Text("Resume positions are forgotten too, on every device that syncs.")
        }
    }

    private var list: some View {
        List {
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
