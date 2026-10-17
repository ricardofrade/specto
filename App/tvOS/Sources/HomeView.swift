import SwiftUI
import Core
import Library
import FeedFeature
import DesignSystem

/// A billboard for the newest unwatched video, Continue Watching and Queue shelves, then the
/// latest uploads. Renders from the database first; the feed refreshes from the network behind it.
struct HomeView: View {
    let environment: AppEnvironment
    let feed: FeedModel
    let actions: VideoActions
    let openSettings: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TVMetrics.sectionSpacing) {
                if environment.instances.isEmpty {
                    TVWelcomeView(openSettings: openSettings)
                }
                // No subscriptions yet: what's trending, to find channels to follow.
                if !environment.instances.isEmpty, !environment.hasSubscriptions, feed.featured == nil {
                    VStack(alignment: .leading, spacing: TVMetrics.gridSpacing) {
                        Text("Trending").font(.title3.weight(.semibold))
                        Text("Subscribe to channels on your iPhone or iPad, or here from a channel's page. Their new videos show up on Home.")
                            .font(.callout).foregroundStyle(Tokens.Colors.textSecondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: TVMetrics.cardWidth), spacing: TVMetrics.gridSpacing,
                                                     alignment: .top)],
                                  spacing: TVMetrics.rowSpacing) {
                            ForEach(feed.trending) { row in
                                VideoCard(row: row, actions: actions)
                            }
                        }
                    }
                    .padding(.top, 140)
                    .focusSection()
                    .task { await feed.loadTrendingIfNeeded() }
                }
                if let featured = feed.featured {
                    Billboard(row: featured, actions: actions)
                }
                if !feed.continueWatching.isEmpty {
                    Shelf(title: Text("Continue Watching"), rows: feed.continueWatching, actions: actions)
                }
                if !feed.queue.isEmpty {
                    Shelf(title: Text("Queue"), rows: feed.queue, actions: actions)
                }
                if let error = feed.refreshError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
                ForEach(feed.sections) { section in
                    VStack(alignment: .leading, spacing: TVMetrics.gridSpacing) {
                        Text(verbatim: section.title).font(.title3.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: TVMetrics.cardWidth), spacing: TVMetrics.gridSpacing,
                                                     alignment: .top)],
                                  spacing: TVMetrics.rowSpacing) {
                            ForEach(section.rows) { row in
                                VideoCard(row: row, actions: actions, showsAvatar: true)
                            }
                        }
                    }
                    .focusSection()
                }
            }
        }
        // The billboard runs under the glass tab bar, like the Apple TV app.
        .ignoresSafeArea(edges: .top)
        .task { await feed.start() }
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
        .focusSection()
    }
}
