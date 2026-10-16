import SwiftUI
import Library
import InstancesFeature

/// Settings: instances and subscriptions, feed, playback and community features, diagnostics,
/// and the open-source notices the LGPL requires us to ship.
struct SettingsView: View {
    let environment: AppEnvironment
    @Bindable var settings: AppSettings
    #if OFFLINE_DOWNLOADS
    @State private var offlineUsed = ""
    #endif

    var body: some View {
        Form {
            Section {
                NavigationLink(value: SceneRouter.SettingsRoute.instances) {
                    LabeledContent {
                        Text("\(environment.instances.count)")
                    } label: {
                        Label { Text("Instances & Subscriptions") } icon: { Image(systemName: "server.rack") }
                    }
                }
                .accessibilityIdentifier("settings.instances")
            }

            Section {
                Toggle(isOn: $settings.hideShorts) { Text("Hide Shorts") }
                Toggle(isOn: $settings.showsRelated) { Text("Show “Up next” suggestions") }
            } header: {
                Text("Feed")
            }

            Section {
                Toggle(isOn: $settings.skipsSponsors) { Text("Skip sponsors (SponsorBlock)") }
                Toggle(isOn: $settings.brandedTitles) { Text("Community titles (DeArrow)") }
                Toggle(isOn: $settings.brandedThumbnails) { Text("Community thumbnails (DeArrow)") }
            } header: {
                Text("Community")
            } footer: {
                Text("SponsorBlock and DeArrow titles are looked up anonymously by a short hash, never the video itself. Community thumbnails ask DeArrow's thumbnail service for each video.")
            }

            #if OFFLINE_DOWNLOADS
            Section {
                Toggle(isOn: $settings.downloadsQueue) { Text("Download queued videos") }
                Picker(selection: $settings.offlineLimitBytes) {
                    Text("500 MB").tag(Int64(500_000_000))
                    Text("1 GB").tag(Int64(1_000_000_000))
                    Text("2 GB").tag(Int64(2_000_000_000))
                    Text("5 GB").tag(Int64(5_000_000_000))
                } label: { Text("Storage limit") }
                LabeledContent {
                    Text(offlineUsed)
                } label: { Text("Used") }
                // One element with a stable identifier: Form rows otherwise merge and drop it.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Used"))
                .accessibilityValue(Text(offlineUsed))
                .accessibilityIdentifier("settings.offlineUsed")
                Button(role: .destructive) {
                    Task {
                        await environment.deleteAllDownloads()
                        offlineUsed = await environment.offlineUsage()
                    }
                } label: { Text("Delete All Downloads") }
            } header: {
                Text("Offline listening")
            } footer: {
                Text("Audio of queued videos is saved for listening without a connection, such as in the car. Watched items are removed first.")
            }
            .task { offlineUsed = await environment.offlineUsage() }
            .onChange(of: settings.offlineLimitBytes) {
                Task { offlineUsed = await environment.applyOfflineLimit() }
            }
            #endif

            Section {
                NavigationLink {
                    DiagnosticsView(collector: environment.diagnostics)
                } label: {
                    Label { Text("Diagnostics") } icon: { Image(systemName: "stethoscope") }
                }
            } footer: {
                Text("Performance and crash reports stay on this device unless you share them.")
            }

            Section {
                NavigationLink {
                    LicensesView()
                } label: {
                    Label { Text("Open-Source Licences") } icon: { Image(systemName: "doc.text") }
                }
                LabeledContent { Text(Bundle.main.versionString) } label: { Text("Version") }
            } header: {
                Text("About")
            } footer: {
                Text("This app has no servers of its own and collects no data. It talks only to the instances you add.")
            }
        }
        .navigationTitle(Text("Settings"))
        .navigationDestination(for: SceneRouter.SettingsRoute.self) { route in
            switch route {
            case .instances:
                InstancesScreen(instances: InstanceStore(environment.database),
                                subscriptions: SubscriptionStore(environment.database),
                                secrets: environment.secrets, deviceName: UIDevice.current.name,
                                onChange: { environment.instancesChanged() },
                                onImported: { environment.subscriptionsChanged($0) })
            }
        }
    }
}

/// Third-party notices (docs/licenses.md, bundled) and the LGPL source offer.
private struct LicensesView: View {
    private let text: AttributedString = {
        guard let url = Bundle.main.url(forResource: "licenses", withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else { return AttributedString() }
        return (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("This app includes mpv and FFmpeg under the GNU Lesser General Public License, in a separate, replaceable framework. The exact source code, including any modifications, is available on request from the developer and from the projects listed below.")
                    .font(.callout)
                Text(text).font(.footnote.monospaced()).textSelection(.enabled)
            }
            .padding()
        }
        .navigationTitle(Text("Open-Source Licences"))
    }
}

private extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
