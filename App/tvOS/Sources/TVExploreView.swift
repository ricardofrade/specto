import SwiftUI
import Core
import Library
import FeedFeature
import DesignSystem

/// Explore on Apple TV: number one as the billboard, the categories when the instances list
/// them (Invidious), then the rest as a grid.
struct TVExploreView: View {
    let model: ExploreModel
    let actions: VideoActions

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: TVMetrics.sectionSpacing) {
                if let featured = model.featured {
                    Billboard(row: featured, actions: actions)
                } else if model.isRefreshing || model.refreshError == nil {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 300)
                } else {
                    ContentUnavailableView {
                        Label { Text("Nothing to explore yet") } icon: { Image(systemName: "flame") }
                    } description: {
                        Text(model.refreshError ?? "")
                    }
                    .padding(.top, 200)
                }
                VStack(alignment: .leading, spacing: TVMetrics.gridSpacing) {
                    HStack(alignment: .firstTextBaseline, spacing: TVMetrics.gridSpacing) {
                        ExploreHeading(model: model, font: .title3.weight(.semibold))
                        Spacer()
                        if model.categories.count > 1 {
                            ForEach(model.categories, id: \.self) { category in
                                Button { model.select(category) } label: {
                                    Text(verbatim: category.title)
                                        .fontWeight(category == model.category ? .bold : .regular)
                                }
                                .accessibilityAddTraits(category == model.category ? .isSelected : [])
                            }
                        }
                    }
                    .focusSection()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: TVMetrics.cardWidth), spacing: TVMetrics.gridSpacing,
                                                 alignment: .top)],
                              spacing: TVMetrics.rowSpacing) {
                        ForEach(model.rows) { row in
                            VideoCard(row: row, actions: actions, showsAvatar: true)
                        }
                    }
                    .focusSection()
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .task { await model.start() }
    }
}

/// First launch on Apple TV: what Specto is, and where instances come from.
struct TVWelcomeView: View {
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 120) {
            Image(systemName: "eye.fill")
                .font(.system(size: 120, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 280, height: 280)
                .background(Tokens.Colors.brand, in: .rect(cornerRadius: 60))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 30) {
                Text("Welcome to Specto").font(.title.bold())
                Text("Watch YouTube through a server you run or trust. No accounts, no ads, no analytics.")
                    .font(.title3).foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Add your Piped, Invidious or YT Zero instance in Settings, or add it on your iPhone or iPad: it arrives here through iCloud, with your subscriptions.")
                    .font(.callout).foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: openSettings) { Text("Open Settings") }
                    .padding(.top, 20)
                    .accessibilityIdentifier("welcome.openSettings")
            }
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 200)
    }
}
