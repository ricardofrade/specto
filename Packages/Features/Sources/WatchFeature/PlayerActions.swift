import SwiftUI
import Core
import Playback
import PlaybackUI
import DesignSystem

/// What the Watch screen can do beyond transport controls; the app supplies the behaviour.
public struct PlayerActions {
    public struct CastTarget: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public var switchMode: (PlaybackMode) -> Void
    public var isQueued: Bool = false
    public var toggleQueue: () -> Void = {}
    /// nil when PiP isn't available for this playback.
    public var startPictureInPicture: (() -> Void)?
    public var castTargets: [CastTarget]
    public var cast: (CastTarget) -> Void
    /// Set while casting: the receiver's name and controls.
    public var casting: Casting?

    public struct Casting {
        public let deviceName: String
        public let isPlaying: Bool
        public let togglePlayback: () -> Void
        public let stop: () -> Void
        public init(deviceName: String, isPlaying: Bool, togglePlayback: @escaping () -> Void, stop: @escaping () -> Void) {
            self.deviceName = deviceName
            self.isPlaying = isPlaying
            self.togglePlayback = togglePlayback
            self.stop = stop
        }
    }

    public init(switchMode: @escaping (PlaybackMode) -> Void, startPictureInPicture: (() -> Void)?,
                castTargets: [CastTarget], cast: @escaping (CastTarget) -> Void, casting: Casting?) {
        self.switchMode = switchMode
        self.startPictureInPicture = startPictureInPicture
        self.castTargets = castTargets
        self.cast = cast
        self.casting = casting
    }

    public static let none = PlayerActions(switchMode: { _ in }, startPictureInPicture: nil, castTargets: [],
                                           cast: { _ in }, casting: nil)
}

/// Audio-only, PiP, AirPlay and Cast, in one glass row under the video.
struct PlayerActionsBar: View {
    let session: PlaybackSession
    let actions: PlayerActions

    var body: some View {
        GlassEffectContainer(spacing: Tokens.Spacing.s) {
            HStack(spacing: Tokens.Spacing.s) {
                Button {
                    actions.switchMode(session.mode == .audioOnly ? .video : .audioOnly)
                } label: {
                    Label { Text(session.mode == .audioOnly ? "Video" : "Audio only") } icon: {
                        Image(systemName: session.mode == .audioOnly ? "play.rectangle" : "headphones")
                    }
                }
                .accessibilityIdentifier("watch.audioMode")
                Button(action: actions.toggleQueue) {
                    Label { Text(actions.isQueued ? "Queued" : "Add to Queue") } icon: {
                        Image(systemName: actions.isQueued ? "checkmark" : "text.badge.plus")
                    }
                    .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("watch.queue")
                if let startPiP = actions.startPictureInPicture, session.mode == .video {
                    Button(action: startPiP) {
                        Label { Text("Picture in Picture") } icon: { Image(systemName: "pip.enter") }
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityIdentifier("watch.pip")
                }
                RoutePicker()
                    .frame(width: 32, height: 32)
                    .padding(.horizontal, Tokens.Spacing.xs)
                if !actions.castTargets.isEmpty {
                    Menu {
                        ForEach(actions.castTargets) { target in
                            Button(target.name) { actions.cast(target) }
                        }
                    } label: {
                        Label { Text("Cast") } icon: { Image(systemName: "tv.badge.wifi") }
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityIdentifier("watch.cast")
                }
            }
            .buttonStyle(.glass)
            .font(Tokens.Typography.cellMeta)
        }
        .padding(.horizontal, Tokens.Spacing.screenInset)
        .padding(.vertical, Tokens.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shown over the video while it plays on a Cast receiver.
struct CastingOverlay: View {
    let casting: PlayerActions.Casting

    var body: some View {
        VStack(spacing: Tokens.Spacing.m) {
            Image(systemName: "tv.badge.wifi").font(.largeTitle)
            Text("Playing on \(casting.deviceName)").font(.headline)
            HStack {
                Button(action: casting.togglePlayback) {
                    Image(systemName: casting.isPlaying ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
                }
                .accessibilityLabel(casting.isPlaying ? Text("Pause") : Text("Play"))
                Button(role: .destructive, action: casting.stop) { Text("Stop Casting") }
            }
            .buttonStyle(.glass)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch.casting")
    }
}

/// A brief notice after SponsorBlock skips a segment.
struct SkipNotice: View {
    let segment: SkipSegment?
    @State private var visible: SkipSegment?

    var body: some View {
        Group {
            if let visible {
                Text("Skipped \(visible.category.localizedName)")
                    .font(Tokens.Typography.caption.weight(.semibold))
                    .padding(.horizontal, Tokens.Spacing.m)
                    .padding(.vertical, Tokens.Spacing.s)
                    .glassEffect(in: .capsule)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onChange(of: segment) { _, new in
            guard let new else { return }
            withAnimation(Tokens.Motion.standard) { visible = new }
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Skipped \(new.category.localizedName)"))
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(Tokens.Motion.standard) { if visible == new { visible = nil } }
            }
        }
    }
}
