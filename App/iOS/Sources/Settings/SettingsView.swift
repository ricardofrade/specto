import SwiftUI
import Library
import DesignSystem
import InstancesFeature
import Playback
import WatchFeature

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
                        Label { Text("Instances & Subscriptions") } icon: { SettingsTile("server.rack", .blue) }
                    }
                }
                .accessibilityIdentifier("settings.instances")
            }

            Section {
                NavigationLink { feedPage } label: {
                    Label { Text("Home & Feed") } icon: { SettingsTile("house.fill", .orange) }
                }
                .accessibilityIdentifier("settings.feed")
                NavigationLink { playbackPage } label: {
                    Label { Text("Video Quality") } icon: { SettingsTile("play.rectangle.fill", .red) }
                }
                .accessibilityIdentifier("settings.playback")
                NavigationLink { searchPage } label: {
                    Label { Text("Search") } icon: { SettingsTile("magnifyingglass", .gray) }
                }
                .accessibilityIdentifier("settings.search")
                NavigationLink { notificationsPage } label: {
                    LabeledContent {
                        if settings.notifiesNewUploads { Text("On") } else { Text("Off") }
                    } label: {
                        Label { Text("Notifications") } icon: { SettingsTile("bell.badge.fill", .red) }
                    }
                }
                .accessibilityIdentifier("settings.notifications")
            }

            Section {
                SponsorBlockSettingsLink(settings: settings)
                NavigationLink { deArrowPage } label: {
                    LabeledContent {
                        if settings.brandedTitles || settings.brandedThumbnails { Text("On") } else { Text("Off") }
                    } label: {
                        Label { Text("DeArrow") } icon: { SettingsTile("textformat.alt", .purple) }
                    }
                }
                .accessibilityIdentifier("settings.deArrow")
            } header: {
                Text("Community")
            }

            Section {
                NavigationLink { Form { BackupSection(environment: environment) }.navigationTitle(Text("Backup")) } label: {
                    Label { Text("Backup") } icon: { SettingsTile("externaldrive.fill", .teal) }
                }
                .accessibilityIdentifier("settings.backup")
                #if OFFLINE_DOWNLOADS
                NavigationLink { offlinePage } label: {
                    Label { Text("Offline listening") } icon: { SettingsTile("arrow.down.circle.fill", .indigo) }
                }
                .accessibilityIdentifier("settings.offline")
                #endif
            }

            Section {
                NavigationLink {
                    DiagnosticsView(collector: environment.diagnostics)
                } label: {
                    Label { Text("Diagnostics") } icon: { SettingsTile("stethoscope", .gray) }
                }
                NavigationLink {
                    LicensesView()
                } label: {
                    Label { Text("Open-Source Licences") } icon: { SettingsTile("doc.text.fill", .gray) }
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
                                onImported: { environment.subscriptionsChanged($0) },
                                checkHealth: { await environment.checkInstanceHealth() },
                                startsAdding: environment.instances.isEmpty,
                                signIn: { instance, username, password in
                                    try await environment.signIn(instance, username: username, password: password,
                                                                 deviceName: UIDevice.current.name)
                                },
                                signOut: { environment.signOut($0) },
                                preferred: $settings.preferredInstance,
                                syncsWithICloud: environment.cloudSync != nil)
            }
        }
    }

    private var feedPage: some View {
        Form {
            Section {
                Toggle(isOn: $settings.hideShorts) { Text("Hide Shorts") }
                Toggle(isOn: $settings.hideLive) { Text("Hide live streams") }
                Toggle(isOn: $settings.hideWatched) { Text("Hide watched videos") }
                Toggle(isOn: $settings.homePreviews) { Text("Preview the featured video") }
                    .accessibilityIdentifier("settings.homePreviews")
            } header: {
                Text("Home")
            } footer: {
                Text("The video at the top of Home plays a few muted seconds behind its title, on Wi-Fi only.")
            }
            Section {
                Toggle(isOn: $settings.showsRelated) { Text("Show “Up next” suggestions") }
                Toggle(isOn: $settings.autoplay) { Text("Autoplay the next suggestion") }
            } header: {
                Text("Watching")
            }
        }
        .navigationTitle(Text("Home & Feed"))
    }

    private var searchPage: some View {
        Form {
            Section {
                Toggle(isOn: $settings.searchSuggestions) { Text("Suggestions while typing") }
            } footer: {
                Text("What you type is sent to your instance, which asks YouTube for suggestions. Recent searches stay on this device.")
            }
        }
        .navigationTitle(Text("Search"))
    }

    private var notificationsPage: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { settings.notifiesNewUploads }, set: { setNotifications($0) })) {
                    Text("New videos from subscriptions")
                }
            } footer: {
                if notificationsDenied {
                    Text("Notifications are off for this app. Turn them on in the Settings app.")
                } else {
                    Text("Checked in the background a few times a day, from your own instances. Turn them off for one channel in Library → Channels.")
                }
            }
        }
        .navigationTitle(Text("Notifications"))
    }

    private var playbackPage: some View {
        Form {
            Section {
                QualityLimitPicker(title: Text("On Wi-Fi"), limit: $settings.wifiQualityLimit)
                    .accessibilityIdentifier("settings.wifiQuality")
                // A Mac running the iPad app has no cellular connection.
                if !ProcessInfo.processInfo.isiOSAppOnMac {
                    QualityLimitPicker(title: Text("On cellular"), limit: $settings.cellularQualityLimit)
                        .accessibilityIdentifier("settings.cellularQuality")
                }
            } footer: {
                Text("The highest quality to play. Cellular includes personal hotspots, and Low Data Mode plays at up to 480p. You can still pick a quality for a video in the player.")
            }
            Section {
                Picker(selection: $settings.preferredFormat) {
                    ForEach(StreamFormat.allCases, id: \.self) { format in
                        Text(verbatim: format.title).tag(format)
                    }
                } label: {
                    Text("Format")
                }
                .accessibilityIdentifier("settings.format")
            } footer: {
                Text("Auto picks the best stream this device decodes and uses Apple's player when it's as good, for Picture in Picture. A format a video doesn't have falls back to Auto. You can also pick one per video in the player.")
            }
        }
        .navigationTitle(Text("Video Quality"))
    }

    private var deArrowPage: some View {
        Form {
            Section {
                Toggle(isOn: $settings.brandedTitles) { Text("Community titles (DeArrow)") }
                Toggle(isOn: $settings.brandedThumbnails) { Text("Community thumbnails (DeArrow)") }
            } footer: {
                Text("DeArrow titles are looked up anonymously by a short hash, never the video itself. Community thumbnails ask DeArrow's thumbnail service for each video.")
            }
        }
        .navigationTitle(Text("DeArrow"))
    }

    #if OFFLINE_DOWNLOADS
    private var offlinePage: some View {
        Form {
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
            } footer: {
                Text("Audio of queued videos is saved for listening without a connection, such as in the car. Watched items are removed first.")
            }
        }
        .navigationTitle(Text("Offline listening"))
        .task { offlineUsed = await environment.offlineUsage() }
        .onChange(of: settings.offlineLimitBytes) {
            Task { offlineUsed = await environment.applyOfflineLimit() }
        }
    }
    #endif
}

/// A Settings row's icon: a white symbol on a coloured rounded square, as in the Settings app.
struct SettingsTile: View {
    let symbol: String
    let color: Color

    init(_ symbol: String, _ color: Color) {
        self.symbol = symbol
        self.color = color
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: .rect(cornerRadius: 7))
            .accessibilityHidden(true)
    }
}
