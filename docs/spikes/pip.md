# Spike: Picture-in-Picture for the mpv path (M0 task 7)

Date: 2026-10-16. Result: **PiP by handing off to AVPlayer** with on-device HLS (spike 6). Verified in the iPad simulator; the owner verifies on iPhone.

## The direct path: mpv frames into `AVSampleBufferDisplayLayer` — blocked

PiP needs either an `AVPlayerLayer` or an `AVSampleBufferDisplayLayer` fed with `CMSampleBuffer`s. mpv renders with `vo=gpu-next` (Vulkan through MoltenVK) straight into its own `CAMetalLayer`, through `wid`. To get frames out instead:

- **libmpv's render API only supports `MPV_RENDER_API_TYPE_OPENGL` and `MPV_RENDER_API_TYPE_SW`.** There's no Metal or Vulkan render target. The OpenGL route means OpenGL ES on iOS, deprecated since iOS 12, and gives up the gpu-next/Metal path spike 5 depends on.
- **Software rendering** (`SW`) into `CVPixelBuffer`s costs a full-frame CPU copy and colour conversion per frame. That's acceptable at PiP size (about 640×360 at 30 fps), but it means switching the VO at runtime, keeping two render paths, and burning battery for as long as PiP stays up.
- **mpv 0.41 has no AVFoundation video output.** `-Davfoundation=enabled` in MPVKit's build only adds `ao_avfoundation`, the audio output.

**Conclusion:** keeping PiP on mpv is possible only through a deprecated or CPU-bound path. Not recommended.

## The fallback that works: hand off to AVPlayer

`PlaybackUI/PictureInPictureHandoff`:

1. Takes the current video's best H.264 MP4 (≤1080p) and original AAC tracks, and builds on-device HLS from them (`LocalHLS.prepare`).
2. Creates an `AVPlayer` and `AVPlayerLayer` under mpv's layer, waits for `readyToPlay`, and seeks exactly to mpv's position.
3. Starts `AVPictureInPictureController` once `isPictureInPicturePossible`, and pauses mpv.
4. When PiP stops, passes AVPlayer's position back; mpv seeks there and resumes.

## Measurements

iPad Pro 13" (M5) simulator, iOS 27, the owner's Piped instance, Big Buck Bunny, 1080p H.264 + AAC (`PiPSpikeUITests`):

| Step | Time |
|---|---|
| Prepare (fetch two segment indexes, write playlists) | **181 ms** |
| AVPlayer ready at mpv's position, PiP possible | **919 ms** |
| Total, request → PiP window started (includes the system's PiP animation) | **1772 ms** |
| Return | mpv resumed at AVPlayer's position (0:08) |

The **iPhone simulator reports PiP unsupported** (`isPictureInPictureSupported() == false`). The iPhone path has to be checked on a device.

## Trade-offs

- **PiP is H.264 (or AV1-in-MP4 on hardware-AV1 devices).** A VP9-only 1440p/2160p session continues in PiP at the best MP4 rendition. At PiP size the difference isn't visible.
- **About 1–2 s from request to PiP.** For automatic PiP when the app goes to the background, this preparation must be done ahead of time. M4 should **pre-arm** the AVPlayer item while playing (prepare plus preroll, kept paused), so backgrounding only flips which engine plays. Then `canStartPictureInPictureAutomaticallyFromInline` works.
- **Two decoders briefly overlap** during the handoff. It's fine for a few hundred milliseconds; don't keep both running.

## Recommendation (M4: PiP in production)

- Pre-arm the handoff while playing. Use `AVPictureInPictureController.ContentSource` with the player layer, and enable automatic PiP from inline.
- Route the `PlaybackSession` between engines on PiP start and stop. `EngineKind.avPlayer` already exists; this becomes the `AVPlayerEngine` path.
- Audio session `.playback` with `UIBackgroundModes` `audio` is already in Info.plist.

## Owner checks

- **iPhone 15 Pro Max:** run with `-Harness pip -DebugPipedURL <Piped API> -DebugVideoID aqz-KE-bpKQ`, tap Start PiP, and confirm the PiP window plays, then Stop PiP returns to mpv at the right position.
- **Same device:** check that background audio continues after locking the screen during PiP.
