import MetricKit
import SwiftUI

/// Privacy-respecting performance and crash reporting: MetricKit payloads (launch times,
/// hitches, hangs, crashes) are kept on the device, and the user decides whether to share
/// them. No third-party SDK, nothing sent automatically.
///
/// Nonisolated on purpose: MetricKit calls the subscriber on its own queue.
nonisolated final class DiagnosticsCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    // Immutable after init; file I/O is atomic per payload.
    let directory: URL
    private let keep = 30

    init(directory: URL? = nil) {
        self.directory = directory ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? .temporaryDirectory).appending(path: "Diagnostics", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        super.init()
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads { write(payload.jsonRepresentation(), kind: "metrics") }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads { write(payload.jsonRepresentation(), kind: "diagnostics") }
    }

    func write(_ json: Data, kind: String) {
        let name = "\(Date.now.formatted(.iso8601.dateSeparator(.dash).timeSeparator(.omitted)))-\(kind)-\(UUID().uuidString.prefix(6)).json"
        try? json.write(to: directory.appending(path: name), options: .atomic)
        prune()
    }

    func reports() -> [DiagnosticsReport] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .compactMap(DiagnosticsReport.init(file:))
    }

    func deleteAll() {
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func prune() {
        let files = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for file in files.dropFirst(keep) { try? FileManager.default.removeItem(at: file) }
    }
}

/// One stored payload, summarised for the list (formatting happens here, not in `body`).
nonisolated struct DiagnosticsReport: Identifiable, Hashable, Sendable {
    let id: String
    let file: URL
    let title: String
    let summary: String

    init?(file: URL) {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        id = file.lastPathComponent
        self.file = file
        let isDiagnostics = file.lastPathComponent.contains("-diagnostics-")
        let end = (json["timeStampEnd"] as? String).flatMap { try? Date($0, strategy: .iso8601) }
        title = (isDiagnostics ? String(localized: "Crashes and hangs") : String(localized: "Performance"))
            + (end.map { " · " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")
        if isDiagnostics {
            let crashes = (json["crashDiagnostics"] as? [Any])?.count ?? 0
            let hangs = (json["hangDiagnostics"] as? [Any])?.count ?? 0
            summary = String(localized: "\(crashes) crashes, \(hangs) hangs")
        } else {
            let launches = (json["applicationLaunchMetrics"] as? [String: Any])?["histogrammedTimeToFirstDraw"] != nil
            let hitches = (json["animationMetrics"] as? [String: Any])?["scrollHitchTimeRatio"] as? String
            summary = [hitches.map { String(localized: "Scroll hitches: \($0)") },
                       launches ? String(localized: "Launch times recorded") : nil]
                .compactMap { $0 }.joined(separator: " · ")
        }
    }
}

struct DiagnosticsView: View {
    let collector: DiagnosticsCollector
    @State private var reports: [DiagnosticsReport] = []

    var body: some View {
        List {
            Section {
                if reports.isEmpty {
                    Text("No reports yet. iOS delivers them about once a day.")
                        .foregroundStyle(.secondary)
                }
                ForEach(reports) { report in
                    ShareLink(item: report.file) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(report.title)
                            if !report.summary.isEmpty {
                                Text(report.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("Performance and crash reports from iOS, kept on this device. Nothing is sent unless you share a report.")
            }
            if !reports.isEmpty {
                Section {
                    Button(role: .destructive) {
                        collector.deleteAll()
                        reports = []
                    } label: { Text("Delete All Reports") }
                }
            }
        }
        .navigationTitle(Text("Diagnostics"))
        .task { reports = collector.reports() }
    }
}
