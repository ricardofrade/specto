# 0013 — SponsorBlock per category: skip, show a button, or play

Date: 2026-10-17. Status: accepted.

## Context

SponsorBlock skipped three hard-coded categories (sponsor, self-promotion, interaction reminders) and ignored the rest. People want intros and end cards handled differently: skipping an intro automatically can feel abrupt, but having to scrub past it every time is worse.

## Decisions

1. **Each category has one of three actions:** Skip (automatic, with the "Skipped …" notice), Show a Skip button, or Don't skip.
   - **Defaults:** the three original categories skip, and the others play, so nothing changes for anyone who never opens the screen.
   - **Storage:** the actions live in UserDefaults (`sponsorBlock.actions`, keyed by category). The on/off switch stays a separate setting.
2. **Only categories that aren't "Don't skip" are requested.** The lookup stays a hash prefix with a category filter, so turning a category off also keeps its segments off the wire.
3. **Contract change: `PlaybackSession.setSkipSegments(_:for:manual:)` and `skippable`.**
   - **What the session does:** for a category in `manual`, the session doesn't seek. Instead, `skippable` holds the segment while the playhead is inside it.
   - **`skipOffered()`:** seeks past that segment and counts it as skipped, so seeking back into it plays it. That's the same rule as automatic skips.
   - **Why the session owns it:** the decision depends on the playhead at engine-report rate, which the session already sees for automatic skips. A view-side check would duplicate the timing and drift.
4. **How each platform offers the skip:**
   - **iPhone and iPad:** a glass "Skip intro" button sits at the bottom trailing corner of the video, above the scrubber.
   - **Apple TV:** a hint reads "▶︎ to skip intro", and pressing right skips the segment instead of jumping ten seconds. A focusable button would take focus from the player, and the TV player already uses ◀︎ to undo an automatic skip.

## Revision: colours and "Only show on the timeline" (2026-10-17)

5. **A fourth action, "Only show on the timeline."** It matches the SponsorBlock extension's "show in seek bar".
   - **What it does:** the category is looked up and drawn on the timeline, but never skipped or offered. Useful for fillers or intros you want to see coming.
   - **Contract:** `setSkipSegments` gained `shownOnly:`. The session leaves those segments alone, and its tests cover them.
6. **Every category has SponsorBlock's own colour:** sponsor green, self-promotion yellow, intro cyan, and so on (`SkipSegment.Category.rgb`).
   - **Where it shows:** next to each category in Settings → SponsorBlock, and on the timeline on iPhone, iPad and Apple TV.
   - **On the timeline:** segments are drawn over the played part too, as the extension does, so a skipped sponsor stays visible.
   - **Why the colours are plain numbers:** `Core` doesn't import SwiftUI, so the apps and features turn the numbers into a `Color`.
