# 0007 — Data saver and the manual quality picker

Date: 2026-10-17. Status: accepted.

## Context

`FormatSelector` already picks the stream from the surface height and the measured throughput, because mpv has no adaptive bitrate. People still want two things that measurement alone doesn't give them:

- **A ceiling on cellular** (data costs money even when the connection is fast).
- **A quality picked by hand** for one video.

## Decisions

1. **One function decides the height.** `VideoQuality.maxHeight(surface:manual:limit:isConstrained:)` lives in Playback, so it can be tested without a network. The rules, in order:
   - **A manual pick wins outright.** It can even exceed the surface height.
   - **Otherwise the surface height applies,** capped by Settings' limit for the current network.
   - **Low Data Mode caps at 480p** unless the person's limit is already lower.
2. **The network comes from `NWPathMonitor`** (`NetworkMonitor` in Core).
   - **"Cellular"** means `isExpensive`, which also covers personal hotspots.
   - **Low Data Mode** is `isConstrained`.
   - The monitor is read when planning, so a change of network applies from the next video or quality change. Playback isn't reloaded in the middle.
3. **Settings has two limits**, "On Wi-Fi" and "On cellular": Best available, 1080p, 720p, 480p or 360p. Both default to Best available, so the planner's behaviour is unchanged until someone sets a limit. The Apple TV shows only the Wi-Fi limit (it's never on an expensive network).
4. **The manual pick lasts for the current video only.** YouTube works the same way. It also stops a 360p choice made on a train from silently sticking at home.
   - **The measured throughput is ignored for a manual pick:** the person asked for that height.
   - **Changing quality** replans and reloads at the current position, then reloads subtitles and SponsorBlock segments, because the session clears them on load.
5. **Contract additions:**
   - `PlaybackRequest.maxVideoHeight`: AVPlayer applies it to HLS through `preferredMaximumResolution`. Adaptive sources are already chosen at a height, and mpv ignores it for HLS.
   - `PlaybackSession.videoHeight`: the planned stream's height, which the picker's "Auto (720p)" label and UI tests read.
6. **The player's bar doesn't grow.** Quality and Playback Speed are submenus of one Playback Settings menu (a gear). The sleep timer joins them later.

## Consequences

- The surface's accessibility value is now `<state> <engine> <height or -> <seconds>`. Tests read the first two fields and the last, so they're unaffected.
- **Device check for the owner:** with "On cellular" set to 480p, turn Wi-Fi off and play a video. The player's Quality menu should show "Auto (480p)" or lower.
