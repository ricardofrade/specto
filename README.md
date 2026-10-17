# Specto

A privacy-respecting video app for iPhone, iPad, Apple TV and CarPlay that plays YouTube through **your own** [Piped](https://github.com/TeamPiped/Piped), [Invidious](https://invidious.io) or [YT Zero](https://ytzero.app/) instance. Specto has no servers of its own, no accounts and no analytics. It talks only to the instances you add (and, if you turn it on, iCloud).

*Specto* is Latin for "I watch". The icon is an eye whose pupil is a play button.

## What it does

**Watching**
- **Native playback:** mpv (an LGPL-only build) for VP9, AV1 and high resolutions, and AVPlayer when it's just as good, for system Picture in Picture, AirPlay and lower power use.
- **Player settings:** quality (with a cellular data saver), audio tracks for dubbed videos, speed, subtitles in your system caption style, and a sleep timer.
- **Navigation within a video:** chapters, scrubbing previews, SponsorBlock (skip each kind of segment automatically, on a button, or not at all), double-tap to skip, hold for 2×.
- **Continuity:** autoplay with an "Up next" countdown, a queue, audio-only mode, CarPlay, Handoff, Shortcuts and Siri.
- **Shorts:** a vertical, swipeable player.

**Your library**
- **On your device:** subscriptions and a Home feed, Watch Later, your own playlists, saved channel playlists, history and resume positions.
- **Sync:** everything syncs between your devices through **your** iCloud, including your instances, so the Apple TV gets the iPhone's.
- **Import and backup:** import subscriptions from Google Takeout, NewPipe, FreeTube, Piped or OPML; export a full backup or a CSV, and restore.

**Finding things**
- Search videos, channels and playlists, with suggestions and recent searches.
- When you have no subscriptions yet, Home shows what's trending in your region.
- Mark videos as watched, or hide a channel from Home without unsubscribing.

**Everywhere**
- **iPhone and iPad:** Liquid Glass design, light and dark mode, iPad windows and keyboard shortcuts, layouts for the foldable iPhone, Home Screen widgets.
- **Apple TV:** a Siri Remote design with a Top Shelf and a profile per person.
- **Mac:** the iPad app runs on Apple silicon Macs.
- **Languages:** English, Portuguese (Portugal and Brazil), Spanish, French and German.

## Requirements

- **To run:** iOS / iPadOS 26 or later, or tvOS 26 or later.
- **To build:** Xcode 27 (the foldable iPhone layouts use the iOS 27 SDK; Xcode 26 builds everything else) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- **To watch anything:** a Piped, Invidious or YT Zero instance you run or trust. The app has no built-in instance.

## Getting started

```sh
# iPhone / iPad (and CarPlay)
xcodegen generate --spec App/iOS/project.yml
open App/iOS/Specto.xcodeproj        # scheme: Specto

# Apple TV
xcodegen generate --spec App/tvOS/project.yml
open App/tvOS/SpectoTV.xcodeproj     # scheme: SpectoTV
```

The Xcode projects are generated, so edit `project.yml`, never the `.xcodeproj`.

In the app, add your instance under Settings → Instances & Subscriptions. For YT Zero, you approve the device with a pairing code. Then import subscriptions or subscribe to channels.

### iCloud sync (optional)

Sync runs only when the build names an iCloud container. Set `CLOUDKIT_CONTAINER` to your container ID and add the matching iCloud capability to your App ID. Without it, everything stays on the device. See [ADR 0004](docs/adr/0004-tvos-and-cloudkit-sync.md).

## Project layout

```
App/iOS/          iPhone and iPad app, CarPlay scene, widgets (XcodeGen: project.yml)
App/tvOS/         Apple TV app and Top Shelf extension
App/Shared/       Composition root shared by both apps
Packages/
  Core/           Models, the VideoSource protocol, Piped / Invidious / YT Zero adapters, routing
  Library/        GRDB persistence and CloudKit sync: subscriptions, history, playlists, backups
  Playback/       PlaybackSession, the mpv and AVPlayer engines, format and codec policy
  DesignSystem/   Tokens and Liquid Glass components
  Features/       One target per screen: Feed, Watch, Search, Channel, Library, Playlist, Instances
docs/             Design notes, decision records (docs/adr), milestones, licences
scripts/          CI, contract tests, string catalog sync, licence and dependency checks
```

The architecture is deliberately lean: SwiftUI with Observation (`@Observable` models and a router), Swift 6 strict concurrency, and no third-party architecture framework. Every screen renders from the local database first, then refreshes from the network. [`CLAUDE.md`](CLAUDE.md) holds the project's rules, and [`docs/adr`](docs/adr) records why each decision was made.

## Testing

| What | How |
|---|---|
| Unit tests (Swift Testing) | From a package folder: `xcodebuild test -scheme <Package> -destination 'platform=iOS Simulator,name=iPhone 18 Pro'` (multi-target packages use the `<Package>-Package` scheme) |
| Everything CI runs | `scripts/ci.sh` |
| Adapters against real instances | `scripts/contract-tests.sh` (instance URLs from `.env.local`, never committed) |
| UI tests against a real instance | `scripts/live-ui-tests.sh` |
| Dependency rules | `scripts/check-dependencies.sh` |

GitHub Actions runs CI on every push, plus nightly contract and live UI tests. The nightly run needs these repository secrets: `PIPED_URL`, `INVIDIOUS_URL`, `YTZERO_URL`, `INSTANCE_USERNAME`, `INSTANCE_PASSWORD`.

## Translations

All text lives in one String Catalog, `App/Shared/Localizable.xcstrings`, shared by both apps and every package.

1. After changing text, run `scripts/sync-strings.py`.
2. Add translations in `scripts/translations/<language>.json`. English plural forms go in `en.json`.

New translations enter the catalog as "needs review" until a native speaker checks them. Siri phrases are in `App/iOS/Resources/AppShortcuts.xcstrings`.

## Privacy

- **No backend, no analytics, no ads.** Specto contacts only your instances, your iCloud if sync is on, SponsorBlock (on by default; it can be turned off) and DeArrow (off by default). Both are looked up by hash prefix only, so they never learn which video you watch.
- **Video goes through your instance's proxy,** so the device never talks to Google's servers directly.
- **Credentials stay protected:** tokens are kept in the Keychain and travel between your devices only inside end-to-end-encrypted iCloud fields.

## Licences

Specto has no licence of its own yet. The mpv and FFmpeg it ships are LGPL builds with no GPL or nonfree components, in a replaceable dynamic framework. Every dependency and its licence is listed in [`docs/licenses.md`](docs/licenses.md), and the app shows them under Settings → Open-Source Licences.

Specto isn't affiliated with or endorsed by YouTube or Google.
