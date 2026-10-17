import SwiftUI
import Core
import Library
import LibraryFeature
import DesignSystem

/// Library on Apple TV: Continue Watching and Queue shelves, then the history as a grid.
struct TVLibraryView: View {
    let model: LibraryModel
    let playlists: SavedPlaylistsModel
    let own: UserPlaylistsModel
    let actions: VideoActions

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TVMetrics.sectionSpacing) {
                if model.isEmpty && playlists.rows.isEmpty {
                    ContentUnavailableView {
                        Label { Text("Nothing here yet") } icon: { Image(systemName: "books.vertical") }
                    } description: {
                        Text("Videos you watch and queue show up here.")
                    }
                }
                if !model.continueWatching.isEmpty {
                    row(Text("Continue Watching"), model.continueWatching)
                }
                if !model.queue.isEmpty {
                    row(Text("Queue"), model.queue, remove: (Text("Remove from Queue"), model.removeFromQueue))
                }
                // Watch Later once it has something; playlists the person made always.
                if !own.shelfRows.isEmpty {
                    VStack(alignment: .leading, spacing: TVMetrics.gridSpacing) {
                        Text("Your Playlists").font(.title3.weight(.semibold))
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: TVMetrics.gridSpacing) {
                                ForEach(own.shelfRows) { row in
                                    UserPlaylistCard(row: row, open: actions.openUserPlaylist)
                                        .frame(width: TVMetrics.cardWidth)
                                }
                            }
                            .padding(.vertical, TVMetrics.gridSpacing)
                        }
                        .scrollClipDisabled()
                    }
                    .focusSection()
                }
                if !playlists.rows.isEmpty {
                    VStack(alignment: .leading, spacing: TVMetrics.gridSpacing) {
                        Text("Playlists").font(.title3.weight(.semibold))
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: TVMetrics.gridSpacing) {
                                ForEach(playlists.rows) { row in
                                    PlaylistCard(row: row, open: actions.openPlaylist,
                                                 remove: { playlists.remove(row.id) })
                                        .frame(width: TVMetrics.cardWidth)
                                }
                            }
                            .padding(.vertical, TVMetrics.gridSpacing)
                        }
                        .scrollClipDisabled()
                    }
                    .focusSection()
                }
                if !model.history.isEmpty {
                    VStack(alignment: .leading, spacing: TVMetrics.gridSpacing) {
                        Text("History").font(.title3.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: TVMetrics.cardWidth), spacing: TVMetrics.gridSpacing,
                                                     alignment: .top)],
                                  spacing: TVMetrics.rowSpacing) {
                            ForEach(model.history) { row in
                                VideoCard(row: row, actions: actions,
                                          remove: (Text("Remove from History"), { model.removeFromHistory(row.id) }))
                            }
                        }
                    }
                    .focusSection()
                }
            }
        }
        .task {
            await model.start()
            await playlists.start()
            await own.start()
        }
    }

    private func row(_ title: Text, _ rows: [FeedRow], remove: (Text, (VideoID) -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: TVMetrics.gridSpacing) {
            title.font(.title3.weight(.semibold))
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: TVMetrics.gridSpacing) {
                    ForEach(rows) { row in
                        VideoCard(row: row, actions: actions, remove: remove.map { label, action in (label, { action(row.id) }) })
                            .frame(width: TVMetrics.cardWidth)
                    }
                }
                .padding(.vertical, TVMetrics.gridSpacing)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}
