# 0015 — Watching beside browsing on iPhone Duo, Home's muted preview, channel banners

Date: 2026-10-17. Status: accepted.

## Decisions

1. **iPhone Duo open flat: the player docks beside the tabs.**
   - **The layout:** playing a video no longer covers the screen. The player takes the half beyond the crease, and the tabs keep the other half. The player goes on the trailing half when the crease runs top to bottom, and on the top half when it runs across.
   - **Browsing goes on:** tapping another video swaps it in place, and channels open in the browsing half (`SceneRouter.splitWatching`).
   - **Changing pose:** bending into tabletop or book, or closing the device, returns to the presented player. The session keeps playing throughout, as before.
   - **How it reads the crease:** from `ReservedRegion.Kind.division` with `.includeInactive`. `FoldState.crease` is the frame, folded or flat.
2. **Tabletop gets its own player, not a split of the usual one.**
   - **Top half:** only the video, with no controls over it.
   - **Bottom half, which rests on the table:** the `TabletopDeck`. Title, the timeline with chapters and SponsorBlock colours, big transport controls that never fade, and Up Next. Nothing needs a tap on the picture.
   - **Book:** keeps video beside the details.
   - **On hardware:** both poses use `ArrangementView`. Simulated folds use the same halves split by hand.
3. **Simulated folds for UI tests (`-SimulateFold flat|bent`, `-FoldAxis`).** The simulator can't change pose from the command line, so `DuoLayoutsUITests` checks the layouts on a large simulator with a crease through the middle. The device is still the check for the hardware itself.
4. **Home's featured video plays a muted preview behind its title** (`PreviewPlayer`).
   - **A separate player:** its own small AVPlayer, deliberately outside `PlaybackSession`. It's decoration, never playback the person controls. It uses the instance's HLS when there is one, else the lowest H.264 stream through `LocalHLS`.
   - **What it plays:** about 24 seconds starting a fifth of the way in, after a second and a half on screen, then a fade back to the artwork.
   - **When it doesn't play:** with Wi-Fi off, on cellular or a hotspot, in Low Data, Low Power or Reduce Motion, while anything else plays, or with the setting off.
   - **A side benefit:** the manifest it loads makes tapping the video instant.
5. **Contract: `ChannelPage.banner`.**
   - **Piped:** sends `bannerUrl` already through its proxy.
   - **Invidious:** sends Google's image host directly. The adapter rewrites it to the instance's `/ggpht/` proxy, as it does avatars, so the device never fetches from Google.
   - **The channel page:** shows the banner fading into the page, with the avatar overlapping its edge. Without a banner, it shows the avatar blurred.
