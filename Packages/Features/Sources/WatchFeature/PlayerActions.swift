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
    /// Subtitle tracks, the one showing, and how to change it.
    public var captions: [CaptionTrack] = []
    public var selectedCaption: CaptionTrack?
    public var selectCaption: (CaptionTrack?) -> Void = { _ in }
    public var toggleCaptions: () -> Void = {}
    /// Heights the Quality picker offers (tallest first), the manual pick (nil: automatic),
    /// and how to change it.
    public var qualities: [Int] = []
    public var selectedQuality: Int?
    public var selectQuality: (Int?) -> Void = { _ in }
    /// Audio tracks of a multi-language video (empty: nothing to choose), the one playing
    /// (nil: original), and how to change it.
    public var audioTracks: [AudioTrackOption] = []
    public var selectedAudio: String?
    public var selectAudio: (String?) -> Void = { _ in }
    /// The sleep timer's choice (nil: off), its countdown, and how to change it.
    public var sleepChoice: SleepTimer.Choice?
    public var sleepStatus: String?
    public var setSleep: (SleepTimer.Choice?) -> Void = { _ in }
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
                    .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("watch.audioMode")
                Button(action: actions.toggleQueue) {
                    Label { Text(actions.isQueued ? "Queued" : "Add to Queue") } icon: {
                        Image(systemName: actions.isQueued ? "checkmark" : "text.badge.plus")
                    }
                    .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("watch.queue")
                if !actions.captions.isEmpty {
                    Menu {
                        Picker(selection: Binding(get: { actions.selectedCaption }, set: { actions.selectCaption($0) })) {
                            Text("Off").tag(CaptionTrack?.none)
                            // Instances label tracks themselves, e.g. "English (auto-generated)".
                            ForEach(actions.captions, id: \.self) { track in
                                Text(verbatim: track.label).tag(Optional(track))
                            }
                        } label: { Text("Subtitles") }
                    } label: {
                        Label { Text("Subtitles") } icon: {
                            Image(systemName: actions.selectedCaption == nil ? "captions.bubble" : "captions.bubble.fill")
                        }
                        .labelStyle(.iconOnly)
                    }
                    .accessibilityIdentifier("watch.subtitles")
                }
                PlaybackSettingsMenu(session: session, actions: actions)
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

/// Quality and speed, each a submenu showing its current value.
private struct PlaybackSettingsMenu: View {
    let session: PlaybackSession
    let actions: PlayerActions

    var body: some View {
        Menu {
            if session.mode == .video, !actions.qualities.isEmpty {
                Picker(selection: Binding(get: { actions.selectedQuality }, set: { actions.selectQuality($0) })) {
                    if let height = session.videoHeight, actions.selectedQuality == nil {
                        Text("Auto (\(VideoQuality.label(height)))").tag(Int?.none)
                    } else {
                        Text("Auto").tag(Int?.none)
                    }
                    ForEach(actions.qualities, id: \.self) { height in
                        Text(verbatim: VideoQuality.label(height)).tag(Optional(height))
                    }
                } label: {
                    Label { Text("Quality") } icon: { Image(systemName: "slider.horizontal.3") }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("watch.quality")
            }
            if !actions.audioTracks.isEmpty {
                Picker(selection: Binding(get: { actions.selectedAudio }, set: { actions.selectAudio($0) })) {
                    ForEach(actions.audioTracks) { track in
                        Text(verbatim: track.label).tag(track.language)
                    }
                } label: {
                    Label { Text("Audio Track") } icon: { Image(systemName: "waveform") }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("watch.audioTrack")
            }
            Picker(selection: Binding(get: { session.rate }, set: { session.setRate($0) })) {
                ForEach(SpeedOptions.all, id: \.self) { option in
                    Text(verbatim: option.label).tag(option.rate)
                }
            } label: {
                Label { Text("Playback Speed") } icon: { Image(systemName: "gauge.with.dots.needle.67percent") }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("watch.speed")
            Picker(selection: Binding(get: { actions.sleepChoice }, set: { actions.setSleep($0) })) {
                Text("Off").tag(SleepTimer.Choice?.none)
                ForEach(SleepTimer.choices, id: \.self) { choice in
                    Text(verbatim: SleepTimer.label(for: choice)).tag(Optional(choice))
                }
            } label: {
                Label { Text("Sleep Timer") } icon: { Image(systemName: actions.sleepChoice == nil ? "moon" : "moon.fill") }
                if let status = actions.sleepStatus { Text(verbatim: status) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("watch.sleep")
        } label: {
            Label { Text("Playback Settings") } icon: { Image(systemName: "gearshape") }
                .labelStyle(.iconOnly)
        }
        .accessibilityIdentifier("watch.settings")
    }
}
