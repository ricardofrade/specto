import SwiftUI
import UniformTypeIdentifiers
import Library

/// Settings → Backup: export everything as JSON (or subscriptions as a Takeout CSV other apps
/// import), and restore a backup, which only ever adds.
struct BackupSection: View {
    let environment: AppEnvironment
    @State private var document: ExportDocument?
    @State private var exporting = false
    @State private var restoring = false
    @State private var title = ""
    @State private var message: String?

    var body: some View {
        Section {
            Button { export(json: true) } label: {
                Label { Text("Export Backup…") } icon: { Image(systemName: "square.and.arrow.up") }
            }
            .accessibilityIdentifier("settings.exportBackup")
            Button { export(json: false) } label: {
                Label { Text("Export Subscriptions as CSV…") } icon: { Image(systemName: "tablecells") }
            }
            Button { restoring = true } label: {
                Label { Text("Restore from Backup…") } icon: { Image(systemName: "square.and.arrow.down") }
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("A backup holds your subscriptions, watch history, saved playlists and instance addresses, never passwords or tokens. Restoring adds what's missing and keeps everything else.")
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: document?.contentType ?? .json,
                      defaultFilename: document?.name) { result in
            if case .failure(let error) = result { show(String(localized: "Couldn't Export"), error.localizedDescription) }
        }
        .fileImporter(isPresented: $restoring, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            restore(url)
        }
        .alert(Text(verbatim: title), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(role: .cancel) {} label: { Text("OK") }
        } message: {
            Text(message ?? "")
        }
    }

    private func export(json: Bool) {
        let store = BackupStore(environment.database)
        do {
            let day = Date.now.formatted(.iso8601.year().month().day())
            document = json
                ? ExportDocument(data: try store.encoded(), contentType: .json, name: "Specto Backup \(day)")
                : ExportDocument(data: Data(try store.subscriptionsCSV().utf8), contentType: .commaSeparatedText,
                                 name: "subscriptions")
            exporting = true
        } catch {
            show(String(localized: "Couldn't Export"), String(localized: "Couldn't create the backup."))
        }
    }

    private func restore(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let backup = try BackupStore.decode(try Data(contentsOf: url))
            let added = try BackupStore(environment.database).restore(backup)
            environment.instancesChanged()   // New instances and channels: rebuild sources and refresh.
            // A labelled list rather than one sentence: no plural forms to get wrong.
            show(String(localized: "Backup Restored"), [String(localized: "Channels: \(added.subscriptions)"),
                       String(localized: "Watched videos: \(added.history)"),
                       String(localized: "Playlists: \(added.playlists)"),
                       String(localized: "Instances: \(added.instances)")].joined(separator: "\n"))
        } catch Backup.Failure.newerVersion {
            show(String(localized: "Couldn't Restore"),
                 String(localized: "This backup is from a newer version of the app. Update the app, then try again."))
        } catch {
            show(String(localized: "Couldn't Restore"), String(localized: "That file isn't a backup from this app."))
        }
    }

    private func show(_ title: String, _ message: String) {
        self.title = title
        self.message = message
    }
}

/// The bytes to save, and what kind of file they are.
struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText]
    let data: Data
    let contentType: UTType
    let name: String

    init(data: Data, contentType: UTType, name: String) {
        self.data = data
        self.contentType = contentType
        self.name = name
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
        name = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
