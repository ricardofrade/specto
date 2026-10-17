import SwiftUI
import Core
import Library
import FeedFeature
import DesignSystem

/// Continue Watching and Queue shelves above the subscriptions grid. Renders from the database
/// first; the feed refreshes from the network behind it.
struct HomeView: View {
    let environment: AppEnvironment
    let feed: FeedModel
    let shelvesVersion: Int
    let actions: VideoActions
    @State private var continueWatching: [FeedRow] = []
    @State private var queue: [FeedRow] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TVMetrics.sectionSpacing) {
                if environment.instances.isEmpty {
                    ContentUnavailableView {
                        Label { Text("Bring your own server") } icon: { Image(systemName: "server.rack") }
                    } description: {
                        Text("Add your Piped, Invidious or YT Zero instance in Settings.")
                    }
                }
                if !continueWatching.isEmpty {
                    Shelf(title: Text("Continue Watching"), rows: continueWatching, actions: actions)
                }
                if !queue.isEmpty {
                    Shelf(title: Text("Queue"), rows: queue, actions: actions)
                }
                if !feed.rows.isEmpty {
                    VStack(alignment: .leading, spacing: TVMetrics.gridSpacing) {
                        Text("Subscriptions").font(.title3.weight(.semibold))
                        if let error = feed.refreshError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Tokens.Colors.textSecondary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: TVMetrics.cardWidth), spacing: TVMetrics.gridSpacing,
                                                     alignment: .top)],
                                  spacing: TVMetrics.rowSpacing) {
                            ForEach(feed.rows) { row in
                                VideoCard(row: row, actions: actions)
                            }
                        }
                    }
                }
            }
        }
        .task { await feed.start() }
        .task(id: shelvesVersion) { reloadShelves() }
        .onChange(of: feed.rows.first?.id) { TopShelfPublisher.publish(environment.database) }
    }

    private func reloadShelves() {
        continueWatching = (try? WatchStateStore(environment.database).inProgress()) ?? []
        queue = (try? QueueStore(environment.database).rows()) ?? []
    }
}

/// A titled horizontal row of cards.
private struct Shelf: View {
    let title: Text
    let rows: [FeedRow]
    let actions: VideoActions

    var body: some View {
        VStack(alignment: .leading, spacing: TVMetrics.gridSpacing) {
            title.font(.title3.weight(.semibold))
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: TVMetrics.gridSpacing) {
                    ForEach(rows) { row in
                        VideoCard(row: row, actions: actions)
                            .frame(width: TVMetrics.cardWidth)
                    }
                }
                .padding(.vertical, TVMetrics.gridSpacing)   // Room for the focus lift.
            }
            .scrollClipDisabled()
        }
    }
}
