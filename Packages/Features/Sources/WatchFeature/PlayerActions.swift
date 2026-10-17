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
    /// Opens "Save to Playlist" (Watch Later and the person's playlists); nil hides the button.
    public var saveToPlaylist: (() -> Void)?
    /// The video's link, for Share; and one that starts at the current position.
    public var shareURL: URL?
    public var shareURLAtCurrentTime: (() -> URL?)?
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
    /// Autoplay's countdown to the next video (nil: none), and what the card's buttons do.
    public var upNext: UpNextCountdown?
    public var cancelUpNext: () -> Void = {}
    public var playUpNextNow: () -> Void = {}
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

/// Over the video, top trailing, shown and faded with the transport controls (as in Apple's TV
/// app): Picture in Picture, AirPlay, and Settings (subtitles, audio track, quality, speed,
/// sleep timer).
struct PlayerTopControls: View, Equatable {
    let session: PlaybackSession
    let actions: PlayerActions

    /// The player redraws several times a second (position); rebuilding an open menu closes it.
    /// Only what the menus show counts; the session's own values update them through
    /// observation.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.session === rhs.session
                && lhs.actions.captions == rhs.actions.captions && lhs.actions.selectedCaption == rhs.actions.selectedCaption
                && lhs.actions.qualities == rhs.actions.qualities && lhs.actions.selectedQuality == rhs.actions.selectedQuality
                && lhs.actions.audioTracks == rhs.actions.audioTracks && lhs.actions.selectedAudio == rhs.actions.selectedAudio
                && lhs.actions.sleepChoice == rhs.actions.sleepChoice && lhs.actions.sleepStatus == rhs.actions.sleepStatus
                && (lhs.actions.startPictureInPicture == nil) == (rhs.actions.startPictureInPicture == nil)
        }
    }

    var body: some View {
        GlassEffectContainer(spacing: Tokens.Spacing.s) {
            HStack(spacing: Tokens.Spacing.s) {
                if let startPiP = actions.startPictureInPicture, session.mode == .video {
                    Button(action: startPiP) {
                        Label { Text("Picture in Picture") } icon: { Image(systemName: "pip.enter") }
                            .labelStyle(.iconOnly)
                            .frame(width: 22, height: 22)
                    }
                    .accessibilityIdentifier("watch.pip")
                }
                RoutePicker()
                    .frame(width: 22, height: 22)
                    .padding(Tokens.Spacing.s)
                    .glassEffect(.regular.interactive(), in: .circle)
                PlaybackSettingsMenu(session: session, actions: actions)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .font(.body.weight(.semibold))
        }
    }
}

/// Under the title: Save, Queue and Share with their names, and "…" for the rest (audio only,
/// casting, a link at the current time).
struct WatchActionRow: View {
    let session: PlaybackSession
    let actions: PlayerActions

    var body: some View {
        GlassEffectContainer(spacing: Tokens.Spacing.s) {
            HStack(spacing: Tokens.Spacing.s) {
                if let save = actions.saveToPlaylist {
                    Button(action: save) {
                        Label { Text("Save") } icon: { Image(systemName: "bookmark") }
                    }
                    .accessibilityIdentifier("watch.save")
                }
                Button(action: actions.toggleQueue) {
                    Label { Text(actions.isQueued ? "Queued" : "Queue") } icon: {
                        Image(systemName: actions.isQueued ? "checkmark" : "text.badge.plus")
                    }
                }
                .accessibilityIdentifier("watch.queue")
                if let link = actions.shareURL {
                    ShareLink(item: link) {
                        Label { Text("Share") } icon: { Image(systemName: "square.and.arrow.up") }
                    }
                    .accessibilityIdentifier("watch.share")
                }
                Menu {
                    Button {
                        actions.switchMode(session.mode == .audioOnly ? .video : .audioOnly)
                    } label: {
                        Label { Text(session.mode == .audioOnly ? "Watch Video" : "Audio Only") } icon: {
                            Image(systemName: session.mode == .audioOnly ? "play.rectangle" : "headphones")
                        }
                    }
                    .accessibilityIdentifier("watch.audioMode")
                    if let link = actions.shareURLAtCurrentTime?() {
                        ShareLink(item: link) {
                            Label { Text("Share at Current Time") } icon: { Image(systemName: "clock.arrow.circlepath") }
                        }
                    }
                    if !actions.castTargets.isEmpty {
                        Menu {
                            ForEach(actions.castTargets) { target in
                                Button(target.name) { actions.cast(target) }
                            }
                        } label: {
                            Label { Text("Cast") } icon: { Image(systemName: "tv.badge.wifi") }
                        }
                        .accessibilityIdentifier("watch.cast")
                    }
                } label: {
                    Label { Text("More") } icon: { Image(systemName: "ellipsis") }
                        .labelStyle(.iconOnly)
                        .frame(height: 20)
                }
                .accessibilityIdentifier("watch.more")
            }
            .buttonStyle(.glass)
            .font(Tokens.Typography.cellMeta.weight(.semibold))
            .labelStyle(ActionLabelStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Icon and name; just the icon when the name wouldn't fit (large text, longer languages).
private struct ActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tokens.Spacing.xs) {
                configuration.icon
                configuration.title.lineLimit(1)
            }
            configuration.icon
        }
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

/// "Skip intro": offered while a segment plays whose category skips by hand.
struct SkipOfferButton: View {
    let segment: SkipSegment
    let skip: () -> Void

    var body: some View {
        Button(action: skip) {
            Label { Text("Skip \(segment.category.localizedName)") } icon: { Image(systemName: "forward.end.fill") }
                .font(Tokens.Typography.caption.weight(.semibold))
        }
        .buttonStyle(.glass)
        .accessibilityIdentifier("watch.skipSegment")
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
            if !actions.captions.isEmpty {
                Picker(selection: Binding(get: { actions.selectedCaption }, set: { actions.selectCaption($0) })) {
                    Text("Off").tag(CaptionTrack?.none)
                    // Instances label tracks themselves, e.g. "English (auto-generated)".
                    ForEach(actions.captions, id: \.self) { track in
                        Text(verbatim: track.label).tag(Optional(track))
                    }
                } label: {
                    Label { Text("Subtitles") } icon: {
                        Image(systemName: actions.selectedCaption == nil ? "captions.bubble" : "captions.bubble.fill")
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("watch.subtitles")
            }
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
                .frame(width: 22, height: 22)
        }
        .accessibilityIdentifier("watch.settings")
    }
}
