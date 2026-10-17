# 0005 — Play video in AVPlayer when it's as good as mpv

Date: 2026-10-17. Status: accepted (owner approved the proposal).

## Context

All video played in mpv, and AVPlayer was used only for audio mode, AirPlay and CarPlay. mpv can't drive Picture-in-Picture directly: libmpv renders through OpenGL or software, not into a layer AVKit can take over. So PiP was a handoff (docs/spikes/pip.md) that re-prepared the video in AVPlayer, taking about 1.8 s. It was manual only and never started automatically when the user left the app.

Many videos don't need mpv. Most have H.264 (or, on capable hardware, AV1) MP4 renditions and AAC audio, which AVPlayer plays through on-device HLS. mpv is only better when it can play something AVPlayer can't:
- VP9 above 1080p;
- webm-only videos.

## Decision

`PlaybackPlanner` picks the engine for video:

- **AVPlayer** when its best stream is at least as tall as mpv's pick, matches it on HDR, and has AAC audio. YT Zero's single H.264/AAC HLS rendition also plays in AVPlayer.
  - **With AVPlayer**, a system `AVPictureInPictureController` on its layer starts PiP automatically when the user leaves the app.
  - **Returning to the app** brings the video back inline.
- **mpv** otherwise.
  - **PiP** keeps the handoff.
- **Live HLS** stays on mpv until it's verified in AVPlayer.
- **"How tall can the video be"** is now the tallest a 16:9 video can be drawn in the window in either orientation, `min(short side, long side × 9/16)`, not the screen's short side. Portrait iPads stopped decoding resolution they can't show.
- **Leaving AirPlay** re-plans instead of forcing mpv.
- **Off switch:** `prefersSystemPlayer: false` restores the old all-mpv behaviour.

## Consequences

- **Benefits on iPhone and the 11-inch iPad:** most videos now get automatic PiP and AVPlayer's lower power use.
- **13-inch iPad and the Apple TV:** VP9 1440p and 4K stay on mpv where they're available, so PiP there is still the manual handoff. That trade is deliberate: resolution first.
- **Decoder logging:** AVPlayer doesn't report the decoder the way mpv does (`decoder` stays nil), so decoder logging covers mpv sessions only.
- **Verified** on an 11-inch iPad simulator against a real Piped instance (`AutoPictureInPictureUITests`):
  - AVPlayer is chosen.
  - Pressing Home starts PiP with the video playing.
  - Reopening the app returns it inline and still playing.
- **Device check (owner):** automatic PiP on the iPhone, where the simulator doesn't support PiP.
