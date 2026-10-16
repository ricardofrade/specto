# Spike: on-device HLS for AVPlayer (M0 task 6)

Date: 2026-10-16. Result: **go** for H.264 (verified) and AV1-in-MP4 (on hardware-AV1 devices, owner to verify). Not applicable to VP9, because webm can't go in HLS.

## Hypothesis

YouTube's adaptive MP4 streams are fragmented MP4 with a segment index (`sidx`). With each stream's `initRange`/`indexRange` (from Piped and Invidious), the app can write HLS playlists itself and hand them to AVPlayer. Nothing needs remuxing on a server. If this holds, AirPlay video and native Picture-in-Picture work for the AVPlayer path.

## What was built (`Packages/Playback/Sources/Playback/LocalHLS/`)

- **`SegmentIndex`:** parses `sidx` (versions 0 and 1). Segment offsets are anchored on the first byte after the box plus `first_offset`. Hierarchical indexes are rejected.
- **`HLSPlaylists`:** writes a master playlist (one video variant with `CODECS`, `RESOLUTION`, `FRAME-RATE`, `VIDEO-RANGE=PQ` for HDR, and an `AUDIO` group) and per-stream VOD media playlists (`EXT-X-MAP` for the init segment, `EXT-X-BYTERANGE` per segment). Requires RFC 6381 `codecs` strings, now on `VideoStream`/`AudioStream`.
- **`LocalHLS.prepare(video:audio:)`:** fetches both index ranges concurrently with HTTP `Range` requests and builds an `AVURLAsset` for `localhls://<uuid>/master.m3u8`. A `PlaylistLoader` (`AVAssetResourceLoaderDelegate`) serves the three playlists from memory. Segment URIs stay the proxied `https` stream URLs, so AVPlayer fetches media with ordinary byte-range requests.

## Results

- **Unit tests:** `SegmentIndexTests`, `HLSPlaylistsTests` (hand-built `sidx` boxes, exact playlist text).
- **Live test** (`LocalHLSIntegrationTests`, runs when `PIPED_URL` is set): the owner's Piped instance, Big Buck Bunny, 720p60 H.264 + 128 kbps AAC as separate streams. AVPlayer reached `readyToPlay`, played past 2 s, and reported a presentation size of 1280×720. The whole test took **4.1 s**, including fetching the index ranges, building the playlists and 2 s of playback. Simulator, iPhone 18 Pro, iOS 27.
- **Index fetch cost:** two small range requests (a few hundred bytes to a few KB each), done in parallel.

## Trade-offs

| | mpv path | On-device HLS (AVPlayer) |
|---|---|---|
| Codecs | AV1, VP9, H.264 | H.264; AV1 only where AVFoundation decodes it in hardware; **no VP9** (webm) |
| Max resolution on non-AV1 devices | VP9 1440p/2160p (software, capped) | H.264 ≤ 1080p |
| Adaptive bitrate | none (picked up front) | single variant today; adding more variants to the master playlist would give real ABR for free |
| AirPlay video | no | **yes** |
| Picture-in-Picture | needs frames in an `AVSampleBufferDisplayLayer` (spike 7) | **native** |
| System integration (Now Playing, interruptions) | manual | built in |

## Recommendation

1. Keep mpv as the default video engine. It is the only path to VP9 and the quality ladder above 1080p on devices without AV1 hardware.
2. Use on-device HLS + AVPlayer for **AirPlay**, for **PiP** (spike 7) and for **audio-only/CarPlay** (an audio-only playlist works the same way). Rendition choice goes through `FormatSelector.select(…, for: .avPlayer, …)`.
3. **Follow-up (M2/M4):** emit several video variants in the master playlist (e.g. 480p/720p/1080p H.264, plus AV1 when supported). AVPlayer's ABR then handles weak networks on this path, which mpv can't.
4. Piped also returns a proxied HLS manifest (`hls`) for normal videos. It's a ready-made AVPlayer source when present, but it's server-generated and its renditions aren't under our control. On-device HLS stays the primary path.

## Owner checks (device)

- **AV1:** on the iPhone 15 Pro Max, a `LocalHLS` asset from an AV1 MP4 stream (`av01…` codec, mp4 container) plays in AVPlayer.
- **AirPlay:** AirPlay an on-device HLS asset to an Apple TV, and confirm video and audio stay in sync while seeking.
