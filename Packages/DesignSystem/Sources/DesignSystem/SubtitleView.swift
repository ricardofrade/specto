import SwiftUI

/// A subtitle line over the video: white on a translucent black box, centred. The player sets the
/// font (it knows how much room there is).
public struct SubtitleView: View {
    private let text: String?

    public init(_ text: String?) {
        self.text = text
    }

    public var body: some View {
        if let text {
            Text(verbatim: text)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, Tokens.Spacing.s)
                .padding(.vertical, Tokens.Spacing.xs)
                .background(.black.opacity(0.7), in: .rect(cornerRadius: 6))
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("subtitle")
                .allowsHitTesting(false)
        }
    }
}
