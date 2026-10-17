# After M7: what was added, and what's left

M0–M7 built the app the plan asked for. This brief records what came after M7, so the milestone plan can take it as its next section. The plan is a Claude Docs document, and its connector wasn't available in the session that wrote this.

## Built

**Library and finding things**
- [x] **Library:**
  - Continue Watching, the Queue and History, plus every subscription under Channels.
  - **History search:** matches every word of the title or channel, ignoring case and accents, across the whole history.
- [x] **Playlists:**
  - A channel's playlists, saving them, and Play All (ADR 0008).
  - **Watch Later and your own playlists,** synced as one record each (ADR 0012).
- [x] **Search:** filters, suggestions and recent searches (ADR 0009).
- [x] **Explore:** what's trending on Home before there are any subscriptions.
  - **Country:** the "Trending in …" heading opens YouTube's list of countries (Automatic follows the device).
  - Trending leaves out premieres that haven't started; live streams too, with **Hide live streams** (Settings, beside Hide Shorts, which also covers Home).
- [x] **Feed housekeeping:**
  - Mark a video watched.
  - Hide a channel from Home.
  - Turn off a channel's new-upload notifications.
- [x] **Channel strip above Home:** tap a channel to see only its videos.
- [x] **Backup:** export everything, export subscriptions as CSV, and restore.
- [x] **Shorts:** a Home shelf, a channel tab and a full-screen vertical player with a side rail (channel, Watch Later, Share) (ADR 0010).

**Watching**
- [x] **The player:** scrubber with previews, gestures, chapters, controls that float over the video, a "…" settings menu, and Share (including at the current time).
- [x] **Player settings:**
  - Quality, with a data saver per network (ADR 0007).
  - Audio tracks for dubbed videos, speed, and a sleep timer.
  - Subtitles in the system caption style.
- [x] **SponsorBlock per category:** skip automatically, show a Skip button, or don't skip (ADR 0013).
- [x] **Autoplay:** an "Up next" countdown when nothing is queued.
- [x] **Live streams:** HLS in AVPlayer from the live edge, with a LIVE badge instead of times and no resume position. Invidious has no live HLS, so the router leaves live streams to Piped or YT Zero.
- [x] **Descriptions are clickable:** links, timestamps, and YouTube links that open in the app.

**Everywhere**
- [x] **YouTube and PeerTube together** (ADR 0018):
  - Instances grouped by network, each section saying who keeps the subscriptions; "Prefer" puts one YouTube instance first.
  - Search switches between YouTube and PeerTube, and searches every PeerTube server at once.
  - PeerTube's videos carry a mark when YouTube's are around too; PeerTube channels name their server.
- [x] **Instances:**
  - Instances sync to every device, the YT Zero token included (ADR 0006).
  - Settings → Instances shows whether each one is reachable, and its latency.
- [x] **Apple TV profiles:** each person has their own library (ADR 0011).
- [x] **System integration:** widgets, deep links, Siri Shortcuts, Handoff, and background refresh with new-upload notifications. On iPad, keyboard shortcuts.
- [x] **Mac:** the iPad app, with a build check in CI.
- [x] **Languages:** English, Portuguese (Portugal and Brazil), Spanish, French and German, with localized Siri phrases.
- [x] **Accessibility:** the audit at the largest text size covers every main screen, Reduce Motion is honoured, and every screen is checked in light and dark.
- [x] **2026 design:**
  - Brand violet and a layered Liquid Glass icon (Icon Composer).
  - A denser Home on iPhone, with loading placeholders instead of spinners.
  - Contacts-style avatar placeholders, with real avatars filled in for every subscription.

**Engineering**
- [x] **CI on GitHub Actions:** package tests, the iOS, tvOS and Mac builds, the licence gate, and the performance and UI suite.
- [x] **Nightly runs:** contract and live UI tests against real instances.
- [x] **Fixes:**
  - mpv requests bounded byte ranges, because googlevideo answers 403 to open-ended ones.
  - The duplicate-group warnings from XcodeGen are gone.

## Left on purpose

- **Swipe actions on Home rows.**
  - **Why not:** Home is a `LazyVStack`, and SwiftUI's swipe actions only work in a `List`. Moving Home to a `List` would cost its layout and risk the 120 Hz scroll gate.
  - **Instead:** every action is in the long-press menu.

## Waiting on the owner

- **Signing:**
  - A paid team in Xcode, plus the Team ID and bundle ID, are needed to install on a device.
  - The CarPlay audio entitlement is requested from Apple.
- **GitHub secrets for the nightly runs:** `PIPED_URL`, `INVIDIOUS_URL`, `YTZERO_URL`, `INSTANCE_USERNAME`, `INSTANCE_PASSWORD`.
- **iCloud container:** set `CLOUDKIT_CONTAINER` to turn sync on (ADR 0004).
- **Translation review by native speakers:** new strings enter the catalog as "needs review".
- **Device checks from M3–M7:**
  - AV1 hardware decode, PiP, ProMotion and the performance gates.
  - CarPlay, and the Apple TV remote.
