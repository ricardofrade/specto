# Project: Apple-native YouTube client

A privacy-respecting video client for iOS, iPadOS (including the foldable iPhone), CarPlay (audio mode), tvOS and Apple silicon Macs ("Designed for iPad").
Users add their own Piped, Invidious or YT Zero instance (YouTube), or a PeerTube server, including public ones from joinpeertube.org's index (ADR 0016). The app has no backend of its own.
App Review can use a public PeerTube server, or the owner's demo instance.

Milestone plan (source of truth for scope): https://claude.ai/code/artifact/9bfaa959-0680-4460-8503-40b749eedc45
All milestones M0–M7 are built; what remains are owner actions and device checks (listed at the end of each brief). Later decisions are in `docs/adr` (0006 onwards) and `docs/design.md`. Briefs: `docs/milestones/M0.md`–`M7.md`; what came after M7 is in `docs/milestones/post-M7.md`.

## Non-negotiable decisions

- Apple platforms only. No KMP, no Compose Multiplatform, no cross-platform UI. Android is a decision point after M7.
- Swift 6 language mode with strict concurrency. App and feature targets use main-actor default isolation.
- SwiftUI + Observation (`@Observable`). No TCA or other architecture frameworks.
- Video playback: mpv (libmpv), **LGPL build only**, and AVPlayer whenever it can play a stream as good as mpv's pick (system PiP, ADR 0005); `PlaybackPlanner` decides. Audio-only mode, CarPlay and AirPlay: AVPlayer.
- Persistence: GRDB for feeds, history and resume positions. SwiftData only for simple settings, if at all. On tvOS the database lives in Caches (tvOS has no persistent storage); instances, subscriptions and watch state sync through CloudKit (ADR 0004, ADR 0006).
- Liquid Glass via system components first; custom glass only through `GlassEffectContainer`.
- Every screen renders from the local database first, then refreshes from the network (stale-while-revalidate).

## Repository layout

```
App/iOS/            iOS + iPadOS app with its CarPlay scene (XcodeGen project: App/iOS/project.yml)
App/tvOS/           Apple TV app and Top Shelf extension (XcodeGen project: App/tvOS/project.yml)
App/Shared/         Composition root compiled into both apps; iOS-only parts behind #if os(iOS)
Packages/
  Core/             Models, VideoSource protocol, Piped/Invidious/YT Zero/PeerTube adapters, routing, health checks
  Library/          GRDB persistence: subscriptions, feed items, history, resume positions
  Playback/         PlaybackSession, PlaybackEngine protocol, MPVEngine, AVPlayerEngine, codec policy
  DesignSystem/     Tokens, Liquid Glass components
  Features/         One package, one target per feature, named `<Name>Feature` (FeedFeature, WatchFeature, …)
                    so `LibraryFeature` can't clash with the `Library` package
docs/milestones/    One brief per milestone
docs/adr/           Architecture decision records: why a contract or rule changed
docs/spikes/        Spike results
```

Dependency rules (enforced by `scripts/check-dependencies.sh`; never work around them):

- Apps → Features → Domain (`Core`, `Library`, `Playback`) → Infrastructure. Arrows point downward only.
- Features never import each other. Shared UI goes in `DesignSystem`; shared logic goes in a domain package.
- `Core`, `Library` and `Playback`'s model types never import SwiftUI. `Core` never imports UIKit.

## Concurrency

- Networking, persistence and image decoding live behind actors or nonisolated async APIs. Nothing slow on the main actor.
- All models are `Sendable` value types.
- `PlaybackSession` and engines are `@MainActor`; engines do heavy work on their own threads internally.
- No `@unchecked Sendable` without a comment explaining why it is safe.
- Closures handed to system frameworks (KVO, `MPMediaItemArtwork`, `MPRemoteCommand` handlers, AVFoundation callbacks) must be `@Sendable` and hop to the main actor themselves. A closure written inside `@MainActor` code inherits that isolation, and Swift 6 traps at runtime when the framework calls it on another thread. A crash during the first M4 run had exactly this cause.

## UI and performance rules

- Info.plist must contain `CADisableMinimumFrameDurationOnPhone = YES` (unlocks 120 Hz on iPhone).
- No formatting, date math, sorting or filtering inside `body`. Pre-format strings in the model or store layer.
- List and grid cells: stable identity, `Equatable` where it helps, no `GeometryReader`, no `AnyView`, shallow trees.
- Start with `LazyVStack`/`LazyVGrid`. Switch a screen to `UICollectionView` + `UIHostingConfiguration` only if Instruments shows it can't hold 120 Hz.
- Images: decode and downsample to the exact pixel size off the main thread; request the thumbnail size that matches the cell.
- Never stack glass on glass. Player controls show on tap and fade during playback.
- Layouts are chosen by available size and size class, never by device model. On iPhone Duo, use the documented fold APIs only: `onFoldChange` (DesignSystem, `ReservedRegion`) and `ArrangementView` (iOS 27.1). See `docs/design.md`.
- The iPhone/iPad app also runs on Apple silicon Macs ("Designed for iPad"); CI builds it. Branch on `ProcessInfo.processInfo.isiOSAppOnMac` only for what a Mac lacks (cellular), never for layout.
- All user-facing text is localizable: `Text("…")` and `String(localized:)`, never string concatenation. One catalog, `App/Shared/Localizable.xcstrings`, serves both apps and every package (packages use the main bundle's default). After adding or changing text run `scripts/sync-strings.py`; add translations in `scripts/translations/<lang>.json` (they enter the catalog as "needs review" until a person checks them). Languages: English (plural forms in `en.json`), pt-PT, pt-BR, es, fr, de; every new string needs all five translations, and counts use plural forms (`{"one", "other"}`), never "1 videos". Siri phrases live in `App/iOS/Resources/AppShortcuts.xcstrings` and must keep `${applicationName}`.
- Anything that opens a video from outside the app (widgets, Top Shelf, Shortcuts, notifications, Handoff) sets `AppEnvironment.pendingVideo`; the root view plays it. Extensions read `HomeSnapshot` (App Group), never the database.
- Tests that depend on "most recent" ordering must not save twice in the same millisecond.
- Every screen supports light and dark appearance; check both (`DesignTourUITests` with `xcrun simctl ui <device> appearance dark`).

## Playback rules

- The player lives in `PlaybackSession`, outside the view hierarchy. Views attach and detach a `RenderSurfaceHost`; playback never stops because a view was rebuilt.
- A stale `detach` must be a no-op: SwiftUI may create the new view before tearing down the old one (fold, unfold, split-screen).
- Codec policy: AV1 only when `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)` is true; then VP9 (software, capped resolution); then H.264 up to 1080p. Query at runtime, never by device model.
- mpv uses `hwdec=videotoolbox`. Log which decoder each session actually uses.
- mpv has no adaptive bitrate: choose the format up front from measured throughput (`FormatSelector`).
- AVPlayer plays only MP4/AAC and HLS, never webm or Opus. `FormatSelector` picks per engine; don't bypass it.
- YouTube stream URLs must come through the instance's proxy: googlevideo URLs are bound to the IP that requested them (the instance, not the device). PeerTube media comes from PeerTube servers directly (ADR 0016).
- PeerTube IDs carry their server (`pt:<host>:…`). YouTube front-ends are wrapped in `YouTubeOnly`; adapters decline others' content with `SourceError.belongsElsewhere`, which the router passes on without a health mark. SponsorBlock and DeArrow are YouTube-only.
- Failures are typed (`PlaybackError`). On `.streamExpired`, refetch the manifest and resume at the current position instead of showing an error.
- Resume positions are saved only while media is loaded, in order, and always for the outgoing video before a switch.

## Licensing

- mpv and FFmpeg must be built without GPL or nonfree components. Do not add any GPL dependency anywhere in the project.
- Record every third-party dependency and its license in `docs/licenses.md`.

## Performance gates (measured locally and on a device)

| Gate | Target | Signpost / metric name |
|---|---|---|
| Cold launch to first rendered feed | < 400 ms | `launch.firstFeedFrame` |
| Tap to first video frame (warm, manifest cached) | < 300 ms | `playback.tapToFirstFrame` |
| Manifest fetch | tracked, not gated (depends on the instance) | `playback.manifest` |
| Scroll hitch ratio | < 5 ms/s | XCTest scroll-deceleration hitch metric |
| Resize/fold during playback | zero stalls | UI test resizing the window while playing |

Use `os_signpost` with the names above so tests and Instruments agree.
GitHub Actions is disabled (hosted macOS runners use up the free minutes): run `scripts/ci.sh` locally. Simulator numbers are a regression trend with tolerance; the gate itself is measured on a physical device.
Tap-to-play hits 300 ms only if the manifest is already cached: prefetch manifests for visible feed items and start fetching on touch-down.

## Testing

- Unit tests with Swift Testing (`import Testing`). Performance and UI tests with XCTest.
- Source adapters: decoding tests against recorded JSON fixtures (hosts sanitised to `instance.example`); live contract tests against real instances catch API drift. Locally, `scripts/contract-tests.sh` and `scripts/live-ui-tests.sh` read `.env.local` (`PIPED_URL`, `INVIDIOUS_URL`, `YTZERO_URL`, `INSTANCE_USERNAME`, `INSTANCE_PASSWORD`); the disabled nightly workflow needs the same as repository secrets. Never commit private instance URLs or credentials. PeerTube tests use a public server (video.blender.org).
- UI tests: launch hooks `-UITestFreshStart`, `-SeedInstance`/`-SeedInvidious`/`-SeedPeerTube <url>`, `-SeedSubscriptions`, `-SeedDemoFeed N`, `-SeedHistory N`. Screenshots also go to `SHOTS_DIR` when set (xcodebuild can hang after a run and lose the result bundle). The iPhone Duo's fold layouts are checked with `-SimulateFold flat|bent -FoldAxis vertical|horizontal` on an iPad simulator (`DuoLayoutsUITests`); real poses need the device.
- `PlaybackSession` is tested against `FakeEngine` (`Packages/Playback/Tests`). Gate a fake load to reproduce races.
- Packages are iOS/tvOS only, so `swift test` won't run them. From the package directory:
  `xcodebuild test -scheme <Package> -destination 'platform=iOS Simulator,name=<newest iPhone Pro>'`
- Before declaring a task done: build for an iOS simulator, run the affected tests, and report results.

## App Store rules

- No downloading or saving media in the App Store build (guideline 5.2.3). Offline audio is compiled only with `OFFLINE_DOWNLOADS`, which only the Debug configuration sets.
- No YouTube name, logo or trade dress in the app name, icon or screenshots.
- No built-in YouTube front-end (Piped, Invidious, YT Zero): the user always supplies one. PeerTube may offer public servers from joinpeertube.org's index to choose from (ADR 0016); nothing is preconfigured or added without the person choosing.
- Ship `PrivacyInfo.xcprivacy`. Support self-hosted instances on the local network (local-network permission, ATS exception for LAN HTTP).

## Working conventions for Claude Code

- Find simulators with `xcrun simctl list devices available`; prefer the newest iPhone Pro and an iPad.
- Build with `xcodebuild` from the command line; fix errors before moving on.
- Signing: `App/Signing.xcconfig` (committed placeholders) includes `App/Local.xcconfig` (not committed) with `SPECTO_BUNDLE_PREFIX` and `DEVELOPMENT_TEAM`; bundle IDs and the App Group follow the prefix. Installing on the owner's devices needs their OK each time.
- The app projects are generated: edit `App/iOS/project.yml` or `App/tvOS/project.yml`, never the `.xcodeproj`. Run `xcodegen generate --spec <project.yml>`, then build the `Specto` scheme (iOS) or `SpectoTV` scheme (tvOS, `-destination 'generic/platform=tvOS Simulator'`).
- Code in `App/Shared` compiles for both platforms: guard iOS-only APIs with `#if os(iOS)`, and iOS-only modifiers in packages with `DesignSystem/PlatformModifiers.swift`.
- Run `scripts/check-dependencies.sh` after touching any `Package.swift`. A new package must be added to its allow-list deliberately.
- Anything that needs a physical device (AV1 hardware decode, PiP, ProMotion, CarPlay, Apple TV) cannot be verified in the simulator. Say so explicitly and list the exact manual check for the owner to run.
- Keep changes scoped to the current milestone brief. Briefs and this file are guidelines: if an item turns out wrong, fix the doc and say why rather than working around it.
- The interfaces in `Packages/Core/Sources/Core/VideoSource.swift` and `Packages/Playback/Sources/Playback/` are the current contracts. Change them when the work needs it, keep the tests green, and record the reason in `docs/adr/`.
