import SwiftUI
import DesignSystem

/// Explore's heading, "Trending in Portugal": YouTube's lists are per country, so it opens
/// the list of countries. PeerTube's lists aren't, and its heading is plain.
public struct ExploreHeading: View {
    let model: ExploreModel
    let font: Font

    public init(model: ExploreModel, font: Font) {
        self.model = model
        self.font = font
    }

    public var body: some View {
        if model.choosesRegion {
            Menu {
                Picker(selection: Binding(get: { model.region }, set: { model.selectRegion($0) })) {
                    Text(verbatim: model.automaticTitle).tag(String?.none)
                    Section {
                        ForEach(model.regions) { region in
                            Text(verbatim: region.name).tag(Optional(region.code))
                        }
                    }
                } label: {
                    Text("Country")
                }
                .pickerStyle(.inline)
            } label: {
                title(chevron: true)
            }
            .tint(Tokens.Colors.textPrimary)
            .accessibilityIdentifier("explore.region")
            .accessibilityHint(Text("Choose the country"))
        } else {
            title(chevron: false)
        }
    }

    private func title(chevron: Bool) -> some View {
        Label {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: model.heading)
                if chevron {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .accessibilityHidden(true)
                }
            }
        } icon: {
            Image(systemName: "flame.fill")
        }
        .font(font)
        .foregroundStyle(Tokens.Colors.textPrimary)
        .accessibilityAddTraits(.isHeader)
    }
}
