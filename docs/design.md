# Design

How Specto looks and why. Apple's own TV and Music apps are the reference: artwork-led, glass controls over content, the same structure everywhere.

## Principles

- **Artwork leads.** Each Home opens on the newest unwatched video, large: a hero card on iPhone and iPad, a full-bleed billboard under the tab bar on Apple TV. Shelves (Continue Watching, Queue) and the Latest grid follow.
- **Glass controls float over content.** Glass is used for controls (Play, actions, chapter chips, the transport bar), never glass on glass. The Watch screen sits on a blurred, colour-sampled backdrop of the video's artwork.
- **Light and dark.** Every screen works in both appearances.
  - **Backdrop:** washed with the system background.
  - **Thumbnails:** a hairline edge, so dark artwork stays visible on dark backgrounds.
  - **Screenshot tour:** `DesignTourUITests` covers both appearances.
- **One structure everywhere.** The same hierarchy on every device and pose; layouts change by size class and space, never by device model.

## Player (iPhone, iPad)

- **Controls and scrubber:** a glass control cluster over the video, and a scrubber with elapsed and remaining time. Dragging shows preview frames (storyboards, Piped only); SponsorBlock segments and chapter starts are marked on the track. Controls fade after 3 s of playback and stay put under VoiceOver.
- **Gestures:** double-tap the left or right half to jump 10 s, hold for 2×, pinch to switch between fill and fit.
- **Landscape:** a phone turned sideways plays full screen (`WatchLayout.fullScreen`).
- **Subtitles:** drawn by the app over either engine, so they look the same with mpv and AVPlayer. Choose them from the actions row, toggle them with the captions button.
- **Speed and audio:** a speed menu (0.5×–2×), audio-only, the queue, PiP, AirPlay and Cast, all icon-only so the row fits narrow phones.
- **iPad keyboard:**
  - Space plays and pauses, and ←/→ jump 10 s. The player has keyboard focus while open.
  - A Playback menu holds the rest.
  - Shortcuts act only while a video is open, so typing in Search is never affected.

## Library, widgets and system integration

- **Library tab:** Continue Watching, the queue (drag to reorder) and the history. Removing items syncs as tombstones.
- **Widgets:** Continue Watching in small, medium, large and Lock Screen sizes. They draw from the App Group snapshot and its small local thumbnails, and never wait on the network.
- **Opening videos from outside the app:** widgets, Top Shelf, Shortcuts, notifications and Handoff all go through `AppEnvironment.pendingVideo`, and the root view plays it.

## iPhone Duo

Apple's guidance (Tech Talks 111461–111466) is to adapt rather than build a layout per pose.

- **Closed (outer display):**
  - The system moves the tab bar to a vertical side strip. Content stays in the safe area.
  - The player's close button is a deliberate overlay on the video, not a toolbar item, so it doesn't move to the strip.
- **Open (inner display):** the sidebar-adaptable tab bar and the size-based Watch layouts (band, side panel).
- **Grids:** where the device can fold (`FoldState.isPresent`), use an even number of columns, so no card straddles the crease.
- **Partly folded:** the Watch screen switches to `ArrangementView` with `.split` (iOS 27.1).
  - **Tabletop:** video above the fold, controls and Up Next on the half resting on the table.
  - **Book:** video and details side by side.
  - **Detection:** `onFoldChange` (DesignSystem) reads `ReservedRegion.Kind.division`.
- **Netflix's approach:** we adopted the immersive full-screen player. We didn't adopt a clips feed on the outer display; that would be a separate short-video product feature.
- **Verified:** the closed pose, on the iPhone Duo simulator.
- **Not yet verified:** the folded poses need Xcode's Device Hub. `DuoPosesUITests` (`DUO_POSES=1`) screenshots while someone changes the pose.

## Apple TV

- **Home:**
  - A billboard (Play, Add to Queue, channel). Coming down from the tab bar always lands on Play.
  - Then the Continue Watching and Queue shelves and the Latest grid, each a focus section.
- **Player:** a glass transport bar that fades, with sponsor marks.
  - **Swiping the remote** scrubs, with large preview frames.
  - **Down** opens subtitles, speed, chapters and Up Next.
  - **Up Next** also appears when a video ends with nothing queued.
- **Artwork:** YouTube artwork is 16:9, so Apple's vertical posters don't apply; the billboard carries the theatrical feel instead.
- **Verified:** `TVBrowseAndPlayUITests` drives the Siri Remote against a real instance.

## 2026 refresh (October 2026)

Compared with Apple's own apps under iOS 26/27, Specto's building blocks were current but its composition wasn't. These changes close that gap:

- **Brand colour.** The violet from the icon is the app's accent (`AccentColor`: `#6A2CF0`, and `#A88BFF` in dark mode for contrast) in both apps, instead of system blue.
- **Layered Liquid Glass icon.** `App/iOS/Resources/AppIcon.icon` is made for Icon Composer: a violet-to-coral gradient, the eye and the play-shaped pupil on separate glass layers. The system renders it in light, dark, clear and tinted Home Screen styles. The tvOS icon stack still comes from `scripts/make-icons.swift`.
- **The player, like Apple's TV app.**
  - **On the video:** PiP, AirPlay and Settings (subtitles, audio track, quality, speed, sleep timer) float at the top right and fade with the transport controls. They fade rather than disappear, so an open menu survives the controls hiding. They also skip redraws, because the player redraws several times a second and an open menu would close if rebuilt.
  - **Under the title:** Save, Queue and Share with their names (icons alone when a name doesn't fit), and "…" for Audio Only, Share at Current Time and Cast. Share sends YouTube's own link.
- **Navigation like Apple's media apps.**
  - **Tabs:** Home, Explore, Library and Search. Settings left the tab bar: it's a sheet opened from the gear at the top right of Home, Explore and Library (⌘, with a keyboard or on a Mac), as Music, Podcasts and TV keep account and settings out of their tabs.
  - **Settings:** the root lists groups with coloured icon tiles, as in the Settings app. Home & Feed, Video Quality, SponsorBlock, DeArrow, Backup and Offline listening each have their own page.
  - **Explore:** the instance's trending list for the person's region. Number one shows large, then rows on a phone and a grid on wider windows. The list is cached (`TrendingStore`), so Explore opens on the last one seen and refreshes behind it.
  - **Search before typing:** recent searches as chips, the person's channels, and the top of the trending list, instead of an empty screen.
  - **Library:** Playlists and Channels are shelves (thumbnail cards and avatars) with headers that open the full lists, instead of rows with counts.
  - **Home:** a strip of channel avatars filters Home to one channel.
