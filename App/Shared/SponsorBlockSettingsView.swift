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
                            HStack(spacing: 12) {
                                // Its colour on the timeline.
                                Circle().fill(category.color).frame(width: 14, height: 14)
                                    .overlay { Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1) }
                                    .accessibilityHidden(true)
                                Text(verbatim: category.title)
                            }
                        }
                        .accessibilityIdentifier("sponsorBlock.\(category.rawValue)")
                    }
                } header: {
                    Text("Segments")
                } footer: {
                    Text("Segments show on the timeline in their colour. With a Skip button, the player offers to skip while the segment plays.")
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
                #if os(iOS)
                Label { Text("SponsorBlock") } icon: { SettingsTile("forward.end.fill", .green) }
                #else
                Text("SponsorBlock")
                #endif
            }
        }
        .accessibilityIdentifier("settings.sponsorBlock")
    }
}

extension SkipSegment.Category {
    /// SponsorBlock's colour for the category, as on its seek bar.
    var color: Color {
        let rgb = self.rgb
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
