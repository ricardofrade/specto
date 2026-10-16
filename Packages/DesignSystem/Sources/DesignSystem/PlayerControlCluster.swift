import SwiftUI

public enum PlayerControlAction: Sendable {
    case skipBack
    case togglePlayback
    case skipForward
    case captions
}

/// The player's transport controls: one glass cluster, so the buttons blend and morph
/// together instead of stacking separate glass panes. Shown on tap, faded during playback
/// by the player (see `Tokens.Motion.controlsAutoHide`).
public struct PlayerControlCluster: View {
    private let isPlaying: Bool
    private let captionsAvailable: Bool
    private let action: (PlayerControlAction) -> Void
    @Namespace private var glass

    public init(isPlaying: Bool, captionsAvailable: Bool,
                action: @escaping (PlayerControlAction) -> Void) {
        self.isPlaying = isPlaying
        self.captionsAvailable = captionsAvailable
        self.action = action
    }

    public var body: some View {
        GlassEffectContainer(spacing: Tokens.Spacing.l) {
            HStack(spacing: Tokens.Spacing.l) {
                button("gobackward.10", label: "Back 10 seconds", size: 52, .skipBack)
                button(isPlaying ? "pause.fill" : "play.fill",
                       label: isPlaying ? "Pause" : "Play", size: 72, .togglePlayback)
                button("goforward.10", label: "Forward 10 seconds", size: 52, .skipForward)
                if captionsAvailable {
                    button("captions.bubble", label: "Captions", size: 52, .captions)
                }
            }
        }
        .animation(Tokens.Motion.standard, value: captionsAvailable)
    }

    private func button(_ symbol: String, label: LocalizedStringKey, size: CGFloat,
                        _ control: PlayerControlAction) -> some View {
        Button { action(control) } label: {
            Image(systemName: symbol)
                .font(size > 60 ? .title : .title3)
                .fontWeight(.semibold)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID(String(describing: control), in: glass)
        .accessibilityLabel(label)
    }
}

private struct PreviewBackdrop: View {
    @State private var playing = false
    @State private var captions = true

    var body: some View {
        ZStack {
            LinearGradient(colors: [.orange, .pink, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: Tokens.Spacing.xxl) {
                PlayerControlCluster(isPlaying: playing, captionsAvailable: captions) { control in
                    switch control {
                    case .togglePlayback: playing.toggle()
                    case .captions: captions.toggle()
                    default: break
                    }
                }
                Toggle("Captions available", isOn: $captions)
                    .padding(Tokens.Spacing.l)
                    .glassEffect(in: .rect(cornerRadius: Tokens.Radius.card))
                    .padding(.horizontal, Tokens.Spacing.xxl)
            }
        }
    }
}

/// Debug-screen entry point for checking the cluster in both appearances.
public struct PlayerControlClusterShowcase: View {
    public init() {}
    public var body: some View { PreviewBackdrop() }
}

#Preview("Light") {
    PreviewBackdrop().preferredColorScheme(.light)
}

#Preview("Dark") {
    PreviewBackdrop().preferredColorScheme(.dark)
}
