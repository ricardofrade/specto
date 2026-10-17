# 0010 — Shorts: their own shelf and a vertical player; mpv requests bounded ranges

Date: 2026-10-17. Status: accepted.

## Context

Subscription feeds from Piped leave Shorts out, and Invidious doesn't flag them. Shorts only show up reliably on each channel's Shorts tab, where there are no upload dates. Building the player also turned up a broader playback bug.

## Decisions

1. **Shorts never mix into Home's grid.**
   - **The shelf:** they have their own Shorts shelf of tall cards. "Hide Shorts" (still the default) hides it.
   - **The player:** tapping a card opens a full-screen vertical pager. The page on screen plays in the app's single session, and swiping plays the next. When a Short ends, auto-advance (ADR 0008's playlist context) plays the next one and the pager follows. Closing stops playback. Apple TV has no Shorts.
2. **Channel pages have a Shorts tab** (`VideoSource.channelShorts`).
   - **Piped:** the `shorts` channel tab. Its `uploaderUrl` is `/channel/UC…/shorts`, so the channel-ID parser now finds the `channel` segment instead of assuming it's second to last.
   - **Invidious:** `/api/v1/channels/:id/shorts`. Its `published: 0` ("56 years ago") becomes no date at all.
3. **Home's shelf fills itself, within a budget.**
   - **How:** after a feed refresh, at most three channels' Shorts tabs are fetched, each at most every 12 hours, the longest-waiting first. Hidden channels are skipped, and a failed channel still counts as visited.
   - **Ordering:** undated Shorts are ordered by fetch order (`saveNewestFirst` staggers `fetchedAt`).
   - **Index:** only the Shorts query uses `COALESCE(publishedAt, fetchedAt)`. The feed query keeps walking the `publishedAt` index, for the launch budget.
   - **Saving and pruning:** saving keeps a known date and duration when a later source lacks them. Undated videos are pruned 30 days after they were last fetched.
4. **mpv fetches in bounded ranges.** googlevideo answers 403 to open-ended requests (no `Range`, or `bytes=0-`) for many streams, while bounded ranges of up to 10 MiB work.
   - **Why only mpv was affected:** mpv's FFmpeg HTTP made exactly the open-ended request, so those streams failed as `streamExpired`, and recovery failed the same way. AVPlayer was never affected, because local HLS requests byte ranges.
   - **The fix:** `stream-lavf-o=request_size=4194304,initial_request_size=524288,multiple_requests=1` (FFmpeg 8.0+; MPVKit ships 8.1.2).
   - **Verified:** the Shorts UI test reproduced the failure and now passes; the player regression UI tests pass.
5. **Settings read flags with `bool(forKey:)`,** so `-feed.hideShorts NO` on the command line works in UI tests without changing saved settings.

## Device check

None beyond the simulator, but worth noticing on a device: mpv playback of long VP9 videos (bounded requests add a round trip every 4 MiB).
