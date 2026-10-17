import SwiftUI
import SearchFeature
import DesignSystem

/// The system search keyboard above a results grid. Nothing is sent until the query is submitted.
struct TVSearchView: View {
    @Bindable var model: SearchModel
    let actions: VideoActions

    var body: some View {
        ScrollView {
            switch model.phase {
            case .idle:
                EmptyView()
            case .loading:
                ProgressView().frame(maxWidth: .infinity)
            case .empty:
                ContentUnavailableView.search(text: model.query)
            case .failed(let message):
                ContentUnavailableView {
                    Label { Text("Search failed") } icon: { Image(systemName: "exclamationmark.triangle") }
                } description: {
                    Text(message)
                }
            case .results:
                LazyVGrid(columns: [GridItem(.adaptive(minimum: TVMetrics.cardWidth), spacing: TVMetrics.gridSpacing,
                                             alignment: .top)],
                          spacing: TVMetrics.rowSpacing) {
                    ForEach(model.rows) { row in
                        VideoCard(row: row, actions: actions)
                            .task { await model.loadMoreIfNeeded(after: row.id) }
                    }
                }
            }
        }
        .searchable(text: $model.query)
        .onSubmit(of: .search) { Task { await model.submit() } }
    }
}
