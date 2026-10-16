import SwiftUI

/// Placeholder until the feed is built; proves the app → Features → domain wiring.
public struct FeedScreen: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No instance yet",
                systemImage: "play.rectangle.on.rectangle",
                description: Text("Add your Piped, Invidious or YT Zero instance to see your feed.")
            )
            .navigationTitle("Feed")
        }
    }
}

#Preview {
    FeedScreen()
}
