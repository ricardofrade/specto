import SwiftUI

/// The artwork's colours as a soft backdrop, like Music's Now Playing: a tiny decode, heavily
/// blurred, under a wash of the system background so text keeps its contrast in light and dark.
public struct AmbientBackdrop: View {
    private let url: URL?
    @Environment(\.colorScheme) private var colorScheme

    public init(_ url: URL?) {
        self.url = url
    }

    public var body: some View {
        RemoteImage(url, pointSize: CGSize(width: 32, height: 18))
            .blur(radius: 40, opaque: true)
            .saturation(1.4)
            .overlay(Tokens.Colors.background.opacity(colorScheme == .dark ? 0.5 : 0.7))
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}
