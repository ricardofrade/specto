import SwiftUI
import Core

/// Settings → SponsorBlock: on or off, and what to do with each kind of segment.
struct SponsorBlockSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.skipsSponsors) { Text("Use SponsorBlock") }
                    .accessibilityIdentifier("sponsorBlock.enabled")
            } footer: {
                Text("Segments are looked up anonymously by a short hash, never the video itself.")
            }
            if settings.skipsSponsors {
                Section {
                    ForEach(SkipSegment.Category.allCases, id: \.self) { category in
                        Picker(selection: action(for: category)) {
                            ForEach(SponsorAction.allCases, id: \.self) { action in
                                Text(action.title).tag(action)
                            }
                        } label: {
                            Text(verbatim: category.title)
                        }
                        .accessibilityIdentifier("sponsorBlock.\(category.rawValue)")
                    }
                } header: {
                    Text("Segments")
                } footer: {
                    Text("With a Skip button, the player offers to skip while the segment plays.")
                }
            }
        }
        .navigationTitle(Text("SponsorBlock"))
    }

    private func action(for category: SkipSegment.Category) -> Binding<SponsorAction> {
        Binding(get: { settings.sponsorActions[category] ?? .off },
                set: { settings.sponsorActions[category] = $0 })
    }
}

/// The Settings row that opens it, with whether it's on.
struct SponsorBlockSettingsLink: View {
    @Bindable var settings: AppSettings

    var body: some View {
        NavigationLink {
            SponsorBlockSettingsView(settings: settings)
        } label: {
            LabeledContent {
                if settings.skipsSponsors { Text("On") } else { Text("Off") }
            } label: {
                Text("SponsorBlock")
            }
        }
        .accessibilityIdentifier("settings.sponsorBlock")
    }
}
