import SwiftUI
import DesignSystem

/// First launch: what Specto is, in three lines, and one button to add the person's instance.
struct WelcomeView: View {
    let addInstance: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: Tokens.Spacing.xl) {
                mark
                    .padding(.top, Tokens.Spacing.xl)
                VStack(spacing: Tokens.Spacing.s) {
                    Text("Welcome to Specto")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Watch YouTube through a server you run or trust.")
                        .font(.title3)
                        .foregroundStyle(Tokens.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
                    feature("server.rack", Text("Your own instance"),
                            Text("Videos, search and subscriptions come from your Piped, Invidious, YT Zero or PeerTube server. No server? Pick a public PeerTube one."))
                    feature("hand.raised.fill", Text("Private by design"),
                            Text("No accounts, no ads, no analytics. Specto has no servers of its own."))
                    feature("icloud.fill", Text("On all your devices"),
                            Text("Subscriptions, history and playlists sync through your iCloud, Apple TV included."))
                }
                .padding(.horizontal, Tokens.Spacing.s)
                Button(action: addInstance) {
                    Text("Add Your Instance").font(.headline).frame(maxWidth: 360).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("welcome.addInstance")
            }
            .frame(maxWidth: 520)
            .padding(Tokens.Spacing.screenInset)
            .frame(maxWidth: .infinity)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) { appeared = true }
        }
        .accessibilityIdentifier("welcome")
    }

    /// The icon's eye on its gradient, as on the Home Screen.
    private var mark: some View {
        Image(systemName: "eye.fill")
            .font(.system(size: 44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 96, height: 96)
            .background(Tokens.Colors.brand, in: .rect(cornerRadius: 22))
            .shadow(color: Tokens.Colors.accent.opacity(0.35), radius: 16, y: 8)
            .accessibilityHidden(true)
    }

    private func feature(_ symbol: String, _ title: Text, _ detail: Text) -> some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.m) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Tokens.Colors.accent)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.headline)
                detail.font(.subheadline).foregroundStyle(Tokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
