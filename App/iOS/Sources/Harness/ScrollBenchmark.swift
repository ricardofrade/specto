import SwiftUI

/// 1,000 feed-shaped placeholder cells for the scroll hitch test. Cells follow the
/// CLAUDE.md rules (pre-formatted strings, Equatable, shallow tree) so the number is a
/// baseline for the real feed.
struct ScrollBenchmark: View {
    private let rows = (0..<1_000).map(BenchmarkRow.init)

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(rows) { row in
                    BenchmarkCell(row: row)
                }
            }
            .padding(.horizontal, 16)
        }
        .accessibilityIdentifier("perf.scroll")
    }
}

nonisolated private struct BenchmarkRow: Identifiable, Equatable {
    let id: Int
    let title: String
    let subtitle: String
    let hue: Double

    init(_ index: Int) {
        id = index
        title = "Placeholder video \(index + 1) with a title long enough to wrap onto two lines"
        subtitle = "Channel \(index % 37) · \(index * 1_311 % 900)K views · \(index % 11 + 1) days ago"
        hue = Double(index % 24) / 24
    }
}

private struct BenchmarkCell: View, Equatable {
    let row: BenchmarkRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hue: row.hue, saturation: 0.5, brightness: 0.8))
                .aspectRatio(16 / 9, contentMode: .fit)
            Text(row.title)
                .font(.headline)
                .lineLimit(2)
            Text(row.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
