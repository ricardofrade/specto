import SwiftUI
import Core
import Library
import Playback
import PlaybackUI
import DesignSystem

/// What the Watch screen shows: the video, and its details once loaded.
public struct WatchContent: Sendable, Equatable {
    public let video: VideoSummary
    /// The channel's first letter, for its monogram.
    /// The channel, from the details once they arrive (a video opened by link knows only its ID).
    public private(set) var channelID: ChannelID
    public private(set) var channelName: String
    public private(set) var channelInitial: String
    /// The title, from the details when the video arrived by link (only its ID known).
    public private(set) var title: String
    public var details: VideoDetails? {
        didSet { applyDetails() }
    }
    /// The description with tappable links and timestamps, built once when details arrive.
    public private(set) var descriptionText: AttributedString?
    /// Long enough to need More (about six lines on a phone).
    public private(set) var descriptionIsLong = false
    public private(set) var chapters: [ChapterRow] = []
    /// Scrubbing previews for this video, sized for the phone's preview bubble.
    public var storyboard: Storyboard?
    public var error: String?
    /// Pre-formatted once when details arrive, never in `body`.
    public private(set) var relatedRows: [FeedRow] = []

    public init(video: VideoSummary, details: VideoDetails? = nil, error: String? = nil) {
        self.video = video
        channelID = video.channelID
        channelName = video.channelName
        channelInitial = Self.initial(video.channelName)
        title = video.title
        self.details = details
        self.error = error
        applyDetails()
    }

    private mutating func applyDetails() {
        relatedRows = Self.format(details?.related ?? [])
        descriptionText = details.map { DescriptionText.attributed($0.description) }
        descriptionIsLong = details.map { DescriptionText.isLong($0.description) } ?? false
        if let summary = details?.summary, !summary.title.isEmpty { title = summary.title }
        if let summary = details?.summary, !summary.channelName.isEmpty {
            channelID = summary.channelID
            channelName = summary.channelName
            channelInitial = Self.initial(summary.channelName)
        }
    }

    private static func initial(_ name: String) -> String {
        name.first.map { String($0).uppercased() } ?? "•"
    }

    public mutating func setChapters(_ chapters: [Chapter]) {
        self.chapters = ChapterRow.rows(chapters)
    }

    private static func format(_ videos: [VideoSummary]) -> [FeedRow] {
        let formatter = RowFormatter()
        return videos.prefix(15).map { formatter.row($0, positionSeconds: nil, durationSeconds: nil) }
    }

    public static func == (lhs: WatchContent, rhs: WatchContent) -> Bool {
        lhs.video == rhs.video && lhs.details?.summary == rhs.details?.summary
            && lhs.chapters == rhs.chapters && lhs.error == rhs.error
    }
}

public struct WatchScreen: View {
    private let session: PlaybackSession
    private let content: WatchContent
    private let makeComments: (() -> CommentsModel)?
    @State private var comments: CommentsModel?
    private let showsRelated: Bool
    private let actions: PlayerActions
    private let onSelectRelated: (VideoSummary) -> Void
    private let onOpenChannel: (ChannelID, String) -> Void
    /// Closes a player that isn't presented (an open iPhone Duo's half); nil dismisses.
    private let onClose: (() -> Void)?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dismiss) private var dismiss
    @State private var size = CGSize(width: 390, height: 844)
    /// The iPhone Duo's fold: bent into tabletop or book, the layout follows the crease.
    @State private var fold = FoldState()

    /// - Parameters:
    ///   - comments: nil when no instance can load comments.
    ///   - showsRelated: YouTube's own "Up next" suggestions; a setting, off for some.
    ///   Created once per video, however often the parent re-renders.
    public init(session: PlaybackSession, content: WatchContent, comments: (() -> CommentsModel)? = nil,
                showsRelated: Bool = true, actions: PlayerActions = .none,
                onSelectRelated: @escaping (VideoSummary) -> Void,
                onOpenChannel: @escaping (ChannelID, String) -> Void,
                onClose: (() -> Void)? = nil) {
        self.onClose = onClose
        self.session = session
        self.content = content
        self.makeComments = comments
        self.showsRelated = showsRelated
        self.actions = actions
        self.onSelectRelated = onSelectRelated
        self.onOpenChannel = onOpenChannel
    }

    public var body: some View {
        layout
            .background {
                LiveBackdrop(session: session, storyboard: content.storyboard,
                             thumbnail: content.video.thumbnails.best(forPixelWidth: 64)?.url)
            }
            .overlay(alignment: .topLeading) {
                // Swipe down also closes; this is the visible, VoiceOver-reachable way.
                Button { if let onClose { onClose() } else { dismiss() } } label: {
                    Image(systemName: onClose == nil ? "chevron.down" : "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text("Close player"))
                .accessibilityIdentifier("watch.close")
                .padding(Tokens.Spacing.s)
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .onFoldChange { fold = $0 }
            .task(id: content.video.id) { comments = makeComments?() }
    }

    @ViewBuilder
    private var layout: some View {
        if let crease = fold.active {
            // A partly folded iPhone Duo. Tabletop (the crease across): the video alone above,
            // and a control deck on the half resting on the table, so nothing needs a tap on
            // the picture. Book (the crease down the middle): video beside the details.
            let tabletop = crease.width > crease.height
            if fold.isSimulated {
                simulatedFold(crease, tabletop: tabletop)    // UI tests: no fold hardware.
            } else {
                arranged(tabletop: tabletop)
            }
        } else {
            sizedLayout
        }
    }

    @ViewBuilder
    private func arranged(tabletop: Bool) -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            ArrangementView {
                if tabletop { cleanPlayer } else { player.frame(maxHeight: .infinity) }
            } secondary: {
                if tabletop { deck } else { tabs }
            }
            .arrangementViewStyle(.split)
        } else {
            sizedLayout
        }
        #else
        sizedLayout     // Built with an SDK before iOS 27: no fold arrangement.
        #endif
    }

    /// The same halves, split at the simulated crease.
    @ViewBuilder
    private func simulatedFold(_ crease: CGRect, tabletop: Bool) -> some View {
        if tabletop {
            VStack(spacing: 0) {
                cleanPlayer.frame(height: crease.minY)
                Color.black.frame(height: crease.height)
                deck
            }
        } else {
            HStack(spacing: 0) {
                player.frame(width: crease.minX).frame(maxHeight: .infinity).background(.black)
                Color.black.frame(width: crease.width)
                tabs
            }
        }
    }

    private var tabs: some View {
        WatchTabs(content: content, comments: comments, session: session) { details(showsChapters: false) }
    }

    /// Tabletop's upper half: the picture only; the controls are on the deck below.
    private var cleanPlayer: some View {
        PlayerArea(session: session, actions: actions, captionsAvailable: !actions.captions.isEmpty,
                   toggleCaptions: actions.toggleCaptions, storyboard: content.storyboard, chapters: content.chapters,
                   showsControls: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
    }

    private var deck: some View {
        TabletopDeck(session: session, content: content, actions: actions)
    }

    @ViewBuilder
    private var sizedLayout: some View {
        switch WatchLayout.choose(width: size.width, height: size.height, horizontal: horizontalSizeClass) {
        case .fullScreen:
            playerArea
                .ignoresSafeArea()
                .persistentSystemOverlays(.hidden)
        case .compact:
            VStack(spacing: 0) {
                player
                ScrollView { details(showsChapters: true) }
                    .scrollEdgeEffectStyle(.soft, for: .top)
            }
        case .band:
            VStack(spacing: 0) {
                player
                WatchTabs(content: content, comments: comments, session: session) { details(showsChapters: false) }
            }
        case .sidePanel:
            // iPad landscape and wide windows: the video fills its column (no bars above and
            // below), the details scroll under it, and Up Next and Comments get the side.
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    player
                    ScrollView { details(showsChapters: true, showsUpNext: false) }
                        .scrollEdgeEffectStyle(.soft, for: .top)
                }
                WatchTabs(content: content, comments: comments, session: session, firstTitle: Text("Up next")) {
                    upNextList
                }
                .frame(width: min(420, size.width * 0.34))
            }
        }
    }

    /// Changing layout rebuilds this area: the new surface attaches and the session ignores the
    /// old one's late detach, so the video layer just moves and playback never reloads.
    private var player: some View {
        playerArea.aspectRatio(16 / 9, contentMode: .fit)
    }

    /// The player in whatever box the layout gives it (16:9, or the whole screen in landscape).
    private var playerArea: some View {
        PlayerArea(session: session, actions: actions, captionsAvailable: !actions.captions.isEmpty,
                   toggleCaptions: actions.toggleCaptions, storyboard: content.storyboard, chapters: content.chapters)
            .overlay {
                if let casting = actions.casting { CastingOverlay(casting: casting) }
            }
            .overlay(alignment: .bottom) {
                if let upNext = actions.upNext {
                    UpNextCard(upNext: upNext, cancel: actions.cancelUpNext, playNow: actions.playUpNextNow)
                        .padding(Tokens.Spacing.m)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                SkipNotice(segment: session.lastSkipped).padding(Tokens.Spacing.m)
            }
            .overlay(alignment: .bottomTrailing) {
                if let segment = session.skippable {
                    SkipOfferButton(segment: segment, skip: session.skipOffered)
                        .padding(Tokens.Spacing.m)
                        .padding(.bottom, 40)   // Clear of the scrubber.
                        .transition(.opacity)
                }
            }
            .animation(Tokens.Motion.standard, value: session.skippable)
    }

    /// - Parameter showsChapters: the band and side panel have a Chapters tab instead.
    /// Up Next on its own, for the side panel.
    private var upNextList: some View {
        LazyVStack(alignment: .leading, spacing: Tokens.Spacing.m) {
            ForEach(content.relatedRows) { row in
                Button { onSelectRelated(row.video) } label: {
                    VideoCell(VideoCellContent(row: row, pixelWidth: Int(140 * displayScale)), style: .row, thumbnailWidth: 140)
                        .equatable()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Tokens.Spacing.m)
    }

    private func details(showsChapters: Bool, showsUpNext: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.l) {
            Text(content.title)
                .font(Tokens.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Button { onOpenChannel(content.channelID, content.channelName) } label: {
                HStack(spacing: Tokens.Spacing.s) {
                    AvatarView(VideoCellContent.Avatar(url: nil, initial: content.channelInitial), size: 30)
                    Text(content.channelName)
                        .font(Tokens.Typography.cellMeta.weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .foregroundStyle(Tokens.Colors.textSecondary)
                }
                .padding(.leading, Tokens.Spacing.xs)
                .padding(.trailing, Tokens.Spacing.m)
                .padding(.vertical, Tokens.Spacing.xs)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("watch.channel")
            .accessibilityHint(Text("Opens the channel"))
            WatchActionRow(session: session, actions: actions)
            if showsChapters, !content.chapters.isEmpty {
                ChapterChips(chapters: content.chapters, session: session)
            }
            if let error = content.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
            if let description = content.descriptionText, !description.characters.isEmpty {
                DescriptionView(text: description, isLong: content.descriptionIsLong, session: session)
            }
            if showsUpNext, showsRelated, !content.relatedRows.isEmpty {
                Text("Up next").font(.headline).padding(.top, Tokens.Spacing.m)
                    .accessibilityAddTraits(.isHeader)
                ForEach(content.relatedRows) { row in
                    Button { onSelectRelated(row.video) } label: {
                        VideoCell(VideoCellContent(row: row, pixelWidth: Int(160 * displayScale)),
                                  style: .row, thumbnailWidth: 160)
                            .equatable()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Tokens.Spacing.screenInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The surface plus transport controls that show on tap and fade during playback.
/// Double-tap a side to jump 10 seconds, hold for 2× while held, pinch to fill the screen.
private struct PlayerArea: View {
    let session: PlaybackSession
    /// For the controls over the video (PiP, AirPlay, Settings).
    let actions: PlayerActions
    let captionsAvailable: Bool
    let toggleCaptions: () -> Void
    let storyboard: Storyboard?
    let chapters: [ChapterRow]
    /// False on a Duo's tabletop: the deck below has the controls, the picture stays clean.
    var showsControls = true
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var size = CGSize(width: 16, height: 9)
    /// Pinched open: the video fills the area, cropping its edges.
    @State private var fills = false
    @State private var jump: (forward: Bool, id: Int)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var holding = false
    @State private var rateBeforeHold: Float?

    var body: some View {
        ZStack {
            #if os(iOS)
            ArrowKeys { forward in skip(forward: forward) }
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            #endif
            PlayerSurface(session: session)
                .scaleEffect(fills ? fillScale : 1)
                .accessibilityIdentifier("watch.surface")
                // "<state> <engine> <height or -> <seconds>": read by UI tests (never stalls, engine policy, quality).
                .accessibilityValue(Text(verbatim: "\(session.state) \(session.engineKind?.rawValue ?? "none") \(session.videoHeight.map { "\($0)p" } ?? "-") \(session.position.components.seconds)"))
            // Smaller in the portrait player, so a line fits between the controls and the bar.
            SubtitleView(session.subtitle, baseSize: size.height < 320 ? 13 : 17)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.horizontal, Tokens.Spacing.xl)
                .padding(.bottom, controlsVisible && showsControls ? 56 : Tokens.Spacing.m)
                .animation(Tokens.Motion.standard, value: controlsVisible)
            if let jump {
                Label { Text(jump.forward ? "Forward 10 seconds" : "Back 10 seconds") } icon: {
                    Image(systemName: jump.forward ? "goforward.10" : "gobackward.10")
                }
                .labelStyle(.iconOnly)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(Tokens.Spacing.l)
                .glassEffect(in: .circle)
                .frame(maxWidth: .infinity, alignment: jump.forward ? .trailing : .leading)
                .padding(.horizontal, size.width * 0.12)
                .transition(.motion(.opacity.combined(with: .scale), reduceMotion: reduceMotion))
                .id(jump.id)
            }
            if holding {
                Label { Text(verbatim: "2×") } icon: { Image(systemName: "forward.fill") }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Tokens.Spacing.m).padding(.vertical, Tokens.Spacing.s)
                    .glassEffect(in: .capsule)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, Tokens.Spacing.m)
            }
            if session.state == .loading || session.state == .buffering {
                ProgressView().tint(.white)
                    .accessibilityLabel(Text("Loading"))
            }
        }
        .clipped()
        .background(.black)
        .contentShape(.rect)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .gesture(SpatialTapGesture(count: 2)
            .onEnded { value in skip(forward: value.location.x > size.width / 2) }
            .exclusively(before: TapGesture().onEnded { toggleControls() }))
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($holding) { value, state, _ in
                if case .second(true, _) = value { state = true }
            })
        .simultaneousGesture(MagnifyGesture().onEnded { value in
            withAnimation(Tokens.Motion.standard) { fills = value.magnification > 1 }
        })
        // After the video's gestures: inside them, a tap on Pause was taken by the video's own
        // tap (show or hide the controls) and never reached the button.
        .overlay {
            if controlsVisible, showsControls {
                PlayerControlCluster(isPlaying: session.state == .playing,
                                     captionsAvailable: captionsAvailable) { action in
                    handle(action)
                }
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if controlsVisible, showsControls {
                PlayerScrubber(session: session, storyboard: storyboard, chapters: chapters,
                               onInteraction: { show() })
                    .padding(.horizontal, Tokens.Spacing.l)
                    .padding(.bottom, Tokens.Spacing.s)
                    .transition(.opacity)
            }
        }
        .animation(Tokens.Motion.standard, value: controlsVisible)
        // After the video's gestures, so tapping these never also toggles the controls (which
        // would close a menu as it opens).
        // Faded, never removed: removing them would also close a menu that's open.
        .overlay(alignment: .topTrailing) {
            PlayerTopControls(session: session, actions: actions)
                .equatable()
                .simultaneousGesture(TapGesture().onEnded { show(lingering: true) })
                .padding(Tokens.Spacing.m)
                .opacity(controlsVisible && showsControls ? 1 : 0)
                .allowsHitTesting(controlsVisible && showsControls)
                .accessibilityHidden(!controlsVisible || !showsControls)
                .animation(Tokens.Motion.standard, value: controlsVisible)
        }
        .onChange(of: holding) { _, isHolding in
            if isHolding {
                rateBeforeHold = session.rate
                session.setRate(2)
            } else if let rate = rateBeforeHold {
                session.setRate(rate)
                rateBeforeHold = nil
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: holding) { _, isHolding in isHolding }
        .onChange(of: session.state) { _, state in
            if state == .playing { scheduleHide() } else { show() }
        }
        .sensoryFeedback(.selection, trigger: session.state == .playing)
    }

    /// How much to scale a 16:9 picture so it covers the whole area.
    private var fillScale: CGFloat {
        let box = size.width / max(size.height, 1), video: CGFloat = 16 / 9
        return box > video ? box / video : video / box
    }

    private func skip(forward: Bool) {
        let target = forward ? session.position + .seconds(10) : max(.zero, session.position - .seconds(10))
        Task { await session.seek(to: target, precise: true) }
        let id = (jump?.id ?? 0) + 1
        withAnimation(Tokens.Motion.snappy) { jump = (forward, id) }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(Tokens.Motion.standard) { if jump?.id == id { jump = nil } }
        }
    }

    private func handle(_ action: PlayerControlAction) {
        switch action {
        case .togglePlayback: session.state == .playing ? session.pause() : session.resume()
        case .skipBack: Task { await session.seek(to: max(.zero, session.position - .seconds(10)), precise: true) }
        case .skipForward: Task { await session.seek(to: session.position + .seconds(10), precise: true) }
        case .captions: toggleCaptions()
        }
        scheduleHide()
    }

    private func toggleControls() {
        if controlsVisible { hide() } else { show(); scheduleHide() }
    }

    /// - Parameter lingering: a menu over the video was opened: stay long enough to choose
    ///   (hiding the controls would close it).
    private func show(lingering: Bool = false) {
        hideTask?.cancel()
        withAnimation(Tokens.Motion.standard) { controlsVisible = true }
        scheduleHide(after: lingering ? .seconds(15) : Tokens.Motion.controlsAutoHide)
    }

    /// Controls stay up under VoiceOver, which can't reach controls that fade away.
    private func hide() {
        guard !UIAccessibility.isVoiceOverRunning else { return }
        withAnimation(Tokens.Motion.standard) { controlsVisible = false }
    }

    private func scheduleHide(after delay: Duration = Tokens.Motion.controlsAutoHide) {
        hideTask?.cancel()
        guard session.state == .playing else { return }
        hideTask = Task {
            try? await Task.sleep(for: delay)
            if !Task.isCancelled { hide() }
        }
    }
}

extension VideoCellContent {
    init(row: FeedRow, pixelWidth: Int) {
        self.init(title: row.title, channelName: row.channelName, detail: row.detail, durationText: row.durationText,
                  thumbnailURL: row.thumbnails.best(forPixelWidth: pixelWidth)?.url, isLive: row.isLive,
                  progress: row.progress)
    }
}

/// The description: six lines, More to read the rest. Timestamps seek; YouTube links open in
/// this app (its URL scheme); other links open in the browser.
private struct DescriptionView: View {
    let text: AttributedString
    let isLong: Bool
    let session: PlaybackSession
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Text(text)
                .font(Tokens.Typography.body)
                .lineLimit(expanded ? nil : 6)
                .selectableText()
                .accessibilityIdentifier("watch.description")
            if isLong {
                Button { expanded.toggle() } label: {
                    Text(expanded ? "Less" : "More").font(Tokens.Typography.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Tokens.Colors.accent)
                .accessibilityIdentifier("watch.descriptionMore")
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let seconds = DescriptionText.seconds(in: url) else { return .systemAction }
            Task { await session.seek(to: .seconds(seconds), precise: true) }
            return .handled
        })
    }
}

/// Autoplay's card over the player when a video ends: what's next, the countdown, Cancel and
/// Play Now.
struct UpNextCard: View {
    let upNext: UpNextCountdown
    let cancel: () -> Void
    let playNow: () -> Void
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(spacing: Tokens.Spacing.m) {
            RemoteImage(upNext.video.thumbnails.best(forPixelWidth: Int(112 * displayScale))?.url,
                        pointSize: CGSize(width: 112, height: 63))
                .frame(width: 112, height: 63)
                .clipShape(.rect(cornerRadius: Tokens.Radius.thumbnail))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                Text(upNext.label).font(Tokens.Typography.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Text(upNext.video.title).font(Tokens.Typography.cellMeta.weight(.semibold)).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: cancel) {
                Label { Text("Cancel") } icon: { Image(systemName: "xmark") }.labelStyle(.iconOnly)
            }
            .buttonStyle(.glass)
            .accessibilityIdentifier("watch.upNextCancel")
            Button(action: playNow) {
                Label { Text("Play Now") } icon: { Image(systemName: "play.fill") }.labelStyle(.iconOnly)
            }
            .buttonStyle(.glassProminent)
            .accessibilityIdentifier("watch.upNextPlay")
        }
        .padding(Tokens.Spacing.s)
        .glassEffect(in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch.upNext")
    }
}
