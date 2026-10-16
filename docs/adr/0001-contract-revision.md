# 0001 — Contract revision before M0 implementation

Date: 2026-10-16. Status: accepted.

## Context

The `Core` and `Playback` stubs were written before any engine or adapter existed. Reviewing them against the M0 brief and the product goals showed gaps that would have forced breaking changes once `MPVEngine`, the adapters and `Library` were built on top. Nothing implements the contracts yet, so changing them now costs nothing.

## Decisions

### Core (`VideoSource.swift`)

| Change | Why |
|---|---|
| `VideoStream`/`AudioStream` gain `container`, `itag`, `initRange`, `indexRange`, `contentLength` | AVPlayer can't play webm/Opus, so audio-only needs to know the container. Byte ranges make on-device HLS possible (M0 spike 6). |
| `StreamManifest.captions: [CaptionTrack]` | Captions are an accessibility baseline, and both engines support WebVTT. |
| `streams(for:)` → `watchPage(for:) -> WatchPage` (details + manifest) | Every source returns details and streams from one endpoint. The Watch screen needs description, likes and related videos, and one call is also the call to prefetch. |
| `subscriptionFeed(cursor:)` → `feed(for: [ChannelID])` | Subscriptions are local (privacy, iCloud sync, import), not stored on an instance account. Piped serves a batched unauthenticated feed. |
| Add `comments(for:cursor:)`, `playlist(_:cursor:)` and their models | The `.comments` and `.playlists` capabilities existed with nothing to call. |
| `publishedText` on `VideoSummary` and `Comment` | Some endpoints return only relative text ("3 days ago"). |
| `SourceError.unavailable` and `isRetryableElsewhere` | Routing must not retry a private or removed video on every instance, but should retry when an instance is blocked or failing. |
| Doc: stream URLs must be proxied | googlevideo URLs are bound to the requesting IP. |

### Playback

| Change | Why |
|---|---|
| `PlaybackRequest.source: MediaSource` (`.adaptive(video:audio:)`, `.hls(URL)`) | Live streams are HLS-only, and on-device HLS needs a home. |
| `PlaybackRequest.caption` | The selected caption track. |
| `PlaybackState.failed(PlaybackError)` instead of `String` | Typed failures enable recovery: `.streamExpired` → refetch and resume. |
| `PlaybackEvent.stats(PlaybackStats)` | M0 task 5's debug screen needs dropped frames. Throughput feeds `FormatSelector`. |
| `FormatSelector.select(from:for:...)` and `selectAudio(from:for:preferredLanguage:)` | Selection depends on the engine (AVPlayer: MP4/AAC only). |
| Engine contract: no events for previous media after `load` | The session's resume logic relies on it. |

### `PlaybackSession` fixes

1. A stale position from the previous media could be saved under the new video's ID. Fix: positions are accepted and saved only while media is loaded.
2. Switching videos lost up to `saveInterval` of the outgoing video's progress. Fix: save the outgoing video's position before switching.
3. Two quick taps raced: a slower earlier load could start playing or mark the session failed. Fix: a generation counter; stale loads are ignored.
4. Saves ran as independent tasks and could land out of order. Fix: saves are chained.

`PlaybackSessionTests` covers each fix with `FakeEngine`. Breaking fixes 1 and 2 was confirmed to fail the tests. Fix 4 has a test but can't be made to fail deterministically.

## Considered and rejected

- **Splitting `position` into a separate observable object** to limit re-renders. Unnecessary: `@Observable` tracks per property, so views that don't read `position` aren't invalidated by it. Keep progress UI in small leaf views instead.
