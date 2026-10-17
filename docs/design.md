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
- **Player:** glass transport bar that fades. Down opens Chapters and Up Next. Up Next also appears when a video ends with nothing queued.
- **Artwork:** YouTube artwork is 16:9, so Apple's vertical posters don't apply; the billboard carries the theatrical feel instead.
- **Verified:** `TVBrowseAndPlayUITests` drives the Siri Remote against a real instance.
