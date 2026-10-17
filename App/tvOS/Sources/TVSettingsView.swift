import SwiftUI
import Library
import InstancesFeature
import DesignSystem

/// Instances, playback and community preferences, and the open-source notices.
struct TVSettingsView: View {
    let environment: AppEnvironment
    @Bindable private var settings = AppSettings.shared

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    InstancesScreen(instances: InstanceStore(environment.database),
                                    subscriptions: SubscriptionStore(environment.database),
                                    secrets: environment.secrets, deviceName: "Apple TV",
                                    onChange: { environment.instancesChanged() },
                                    onImported: { environment.subscriptionsChanged($0) })
                } label: {
                    LabeledContent {
                        Text("\(environment.instances.count)")
                    } label: {
                        Label { Text("Instances & Subscriptions") } icon: { Image(systemName: "server.rack") }
                    }
                }
            }
            Section {
                Toggle(isOn: $settings.hideShorts) { Text("Hide Shorts") }
                Toggle(isOn: $settings.skipsSponsors) { Text("Skip sponsors (SponsorBlock)") }
                Toggle(isOn: $settings.brandedTitles) { Text("Community titles (DeArrow)") }
            } footer: {
                Text("SponsorBlock and DeArrow titles are looked up anonymously by a short hash, never the video itself.")
            }
            Section {
                NavigationLink { LicensesView() } label: { Text("Open-Source Licences") }
                LabeledContent { Text(Bundle.main.versionString) } label: { Text("Version") }
            } footer: {
                Text("This app has no servers and collects no data. It talks only to the instances you add.")
            }
        }
        .navigationTitle(Text("Settings"))
    }
}
