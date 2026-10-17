import SwiftUI
import Library
import DesignSystem
import InstancesFeature

/// Settings: instances and subscriptions, feed, playback and community features, diagnostics,
/// and the open-source notices the LGPL requires us to ship.
struct SettingsView: View {
    let environment: AppEnvironment
    @Bindable var settings: AppSettings
    #if OFFLINE_DOWNLOADS
    @State private var offlineUsed = ""
    #endif
    @State private var notificationsDenied = false

    private func setNotifications(_ on: Bool) {
        guard on else {
            settings.notifiesNewUploads = false
            return
        }
        Task {
            let allowed = await NewUploadNotifier.requestAuthorization()
            settings.notifiesNewUploads = allowed
            notificationsDenied = !allowed
            if allowed { NewUploadNotifier.markSeen() }
        }
    }

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
                Toggle(isOn: $settings.hideWatched) { Text("Hide watched videos") }
                Toggle(isOn: $settings.showsRelated) { Text("Show “Up next” suggestions") }
                Toggle(isOn: $settings.autoplay) { Text("Autoplay the next suggestion") }
            } header: {
                Text("Feed")
            }

            Section {
                Toggle(isOn: $settings.searchSuggestions) { Text("Suggestions while typing") }
            } header: {
                Text("Search")
            } footer: {
                Text("What you type is sent to your instance, which asks YouTube for suggestions. Recent searches stay on this device.")
            }

            Section {
                QualityLimitPicker(title: Text("On Wi-Fi"), limit: $settings.wifiQualityLimit)
                    .accessibilityIdentifier("settings.wifiQuality")
                // A Mac running the iPad app has no cellular connection.
                if !ProcessInfo.processInfo.isiOSAppOnMac {
                    QualityLimitPicker(title: Text("On cellular"), limit: $settings.cellularQualityLimit)
                        .accessibilityIdentifier("settings.cellularQuality")
                }
            } header: {
                Text("Video quality")
            } footer: {
                Text("The highest quality to play. Cellular includes personal hotspots, and Low Data Mode plays at up to 480p. You can still pick a quality for a video in the player.")
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

            Section {
                Toggle(isOn: Binding(get: { settings.notifiesNewUploads }, set: { setNotifications($0) })) {
                    Text("New videos from subscriptions")
                }
            } header: {
                Text("Notifications")
            } footer: {
                if notificationsDenied {
                    Text("Notifications are off for this app. Turn them on in the Settings app.")
                } else {
                    Text("Checked in the background a few times a day, from your own instances.")
                }
            }

            BackupSection(environment: environment)

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
