# Project: Apple-native YouTube client

A privacy-respecting YouTube client for iOS, iPadOS (including the foldable iPhone), CarPlay (audio mode) and tvOS.
Users add their own self-hosted Piped, Invidious or YT Zero instance; the app has no backend of its own.
App Review uses the owner's demo instance.

Milestone plan (source of truth for scope): https://claude.ai/code/artifact/9bfaa959-0680-4460-8503-40b749eedc45
Current milestone: **M7 — tvOS.** Briefs for finished milestones: `docs/milestones/M0.md`–`M6.md`.

## Non-negotiable decisions

- Apple platforms only. No KMP, no Compose Multiplatform, no cross-platform UI. Android is a decision point after M7.
- Swift 6 language mode with strict concurrency. App and feature targets use main-actor default isolation.
- SwiftUI + Observation (`@Observable`). No TCA or other architecture frameworks.
- Video playback: mpv (libmpv), **LGPL build only**. Audio-only mode, CarPlay and AirPlay: AVPlayer.
- Persistence: GRDB for feeds, history and resume positions. SwiftData only for simple settings, if at all.
- Liquid Glass via system components first; custom glass only through `GlassEffectContainer`.
- Every screen renders from the local database first, then refreshes from the network (stale-while-revalidate).

## Repository layout

```
App/iOS/            Xcode app target (iOS + iPadOS) with its CarPlay scene; App/tvOS follows in M7
Packages/
  Core/             Models, VideoSource protocol, Piped/Invidious/YT Zero adapters, routing, health checks
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
- Layouts are chosen by available size and size class, never by device model. No hinge or fold-angle APIs until Apple documents them.

## Playback rules

- The player lives in `PlaybackSession`, outside the view hierarchy. Views attach and detach a `RenderSurfaceHost`; playback never stops because a view was rebuilt.
- A stale `detach` must be a no-op: SwiftUI may create the new view before tearing down the old one (fold, unfold, split-screen).
- Codec policy: AV1 only when `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)` is true; then VP9 (software, capped resolution); then H.264 up to 1080p. Query at runtime, never by device model.
- mpv uses `hwdec=videotoolbox`. Log which decoder each session actually uses.
- mpv has no adaptive bitrate: choose the format up front from measured throughput (`FormatSelector`).
- AVPlayer plays only MP4/AAC and HLS, never webm or Opus. `FormatSelector` picks per engine; don't bypass it.
- Stream URLs must come through the instance's proxy: googlevideo URLs are bound to the IP that requested them (the instance, not the device).
- Failures are typed (`PlaybackError`). On `.streamExpired`, refetch the manifest and resume at the current position instead of showing an error.
- Resume positions are saved only while media is loaded, in order, and always for the outgoing video before a switch.

## Licensing

- mpv and FFmpeg must be built without GPL or nonfree components. Do not add any GPL dependency anywhere in the project.
- Record every third-party dependency and its license in `docs/licenses.md`.

## Performance gates (CI blocks a milestone on these)

| Gate | Target | Signpost / metric name |
|---|---|---|
| Cold launch to first rendered feed | < 400 ms | `launch.firstFeedFrame` |
| Tap to first video frame (warm, manifest cached) | < 300 ms | `playback.tapToFirstFrame` |
| Manifest fetch | tracked, not gated (depends on the instance) | `playback.manifest` |
| Scroll hitch ratio | < 5 ms/s | XCTest scroll-deceleration hitch metric |
| Resize/fold during playback | zero stalls | UI test resizing the window while playing |

Use `os_signpost` with the names above so tests and Instruments agree.
Hosted CI simulators are noisy and can't show 120 Hz: treat their numbers as a regression trend with tolerance. The gate itself is measured on a physical device.
Tap-to-play hits 300 ms only if the manifest is already cached: prefetch manifests for visible feed items and start fetching on touch-down.

## Testing

- Unit tests with Swift Testing (`import Testing`). Performance and UI tests with XCTest.
- Source adapters: decoding tests against recorded JSON fixtures run on every PR; live contract tests against real instances run nightly to catch API drift. Read instance URLs from environment variables `PIPED_URL`, `INVIDIOUS_URL`, `YTZERO_URL`. Never commit instance URLs or credentials.
- `PlaybackSession` is tested against `FakeEngine` (`Packages/Playback/Tests`). Gate a fake load to reproduce races.
- Packages are iOS/tvOS only, so `swift test` won't run them. From the package directory:
  `xcodebuild test -scheme <Package> -destination 'platform=iOS Simulator,name=<newest iPhone Pro>'`
- Before declaring a task done: build for an iOS simulator, run the affected tests, and report results.

## App Store rules

- No downloading or saving media in the App Store build (guideline 5.2.3). Offline audio is compiled only with `OFFLINE_DOWNLOADS`, which only the Debug configuration sets.
- No YouTube name, logo or trade dress in the app name, icon or screenshots.
- No built-in default instance; the user always supplies one. App Review uses the owner's demo instance.
- Ship `PrivacyInfo.xcprivacy`. Support self-hosted instances on the local network (local-network permission, ATS exception for LAN HTTP).

## Working conventions for Claude Code

- Find simulators with `xcrun simctl list devices available`; prefer the newest iPhone Pro and an iPad.
- Build with `xcodebuild` from the command line; fix errors before moving on.
- The app project is generated: edit `App/iOS/project.yml`, never the `.xcodeproj`. Run `xcodegen generate --spec App/iOS/project.yml`, then build the `Player` scheme of `App/iOS/Player.xcodeproj`.
- Run `scripts/check-dependencies.sh` after touching any `Package.swift`. A new package must be added to its allow-list deliberately.
- Anything that needs a physical device (AV1 hardware decode, PiP, ProMotion, CarPlay, Apple TV) cannot be verified in the simulator. Say so explicitly and list the exact manual check for the owner to run.
- Keep changes scoped to the current milestone brief. Briefs and this file are guidelines: if an item turns out wrong, fix the doc and say why rather than working around it.
- The interfaces in `Packages/Core/Sources/Core/VideoSource.swift` and `Packages/Playback/Sources/Playback/` are the current contracts. Change them when the work needs it, keep the tests green, and record the reason in `docs/adr/`.
