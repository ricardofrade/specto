# 0002 — Sources, subscription source of truth, and sync

Date: 2026-10-16. Status: accepted.

## Context

The M1 brief asks for Piped, Invidious and YT Zero adapters, capability routing, and a decision on the subscription source of truth ("YT Zero when present, otherwise CloudKit"). Before designing, we studied each API: from source code, and live against the owner's own instances (sanitised references and fixtures under `Packages/Core/Tests/…/Fixtures`).

| | Piped | Invidious | YT Zero |
|---|---|---|---|
| What it is | Full YouTube API proxy | Full YouTube API proxy | Self-hosted **subscriptions inbox** (RSS-based) with its own accounts, feed, watch state and playback |
| Batched feed for N channels | `GET /feed/unauthenticated?channels=` (also POST). Only videos from the **last 30 days** that the instance has already seen; a new channel fills in on later calls | None. Cheapest is the per-channel Atom feed `/feed/channel/{ucid}` (15 entries, exact timestamps, **no duration**) | Server-side feed of the user's own subscriptions: `GET /api/feed` (offset pages, max 100) |
| Streams | DASH-style adaptive, AV1/VP9/H.264, proxied; byte ranges for on-device HLS | Same with `local=true`; codecs must be parsed from `type` | **H.264 + AAC only**, ≤1080p, through a 15-minute playback ticket (HLS rewritten to carry the ticket) |
| Accounts | Optional, not used | Optional, not used | Required: **device-code flow** → Bearer token (30-day sliding) |
| Watch state | — | — | Server-side resume position, history, watched flags |
| Errors | 500 with a Java stack trace; classify by exception class | `{"error": …}` with 404/500 | `{"error": …}`, and 428/400 during device auth |
| Maintenance | Active | Active | **Maintainer has stepped away**; 2026.09.10 is the last planned release. Unlicense. |

## Decisions

1. **Screens render from GRDB, always.** Sources only feed the local database (stale-while-revalidate), whichever source of truth applies.

2. **Subscription source of truth.**
   - **With a YT Zero instance linked:** YT Zero owns subscriptions and watch state.
     - **Mirroring:** its channel list, feed and resume positions are mirrored into GRDB.
     - **Writing back:** local actions (follow, unfollow, progress, mark watched) are sent to YT Zero.
     - **Cross-device:** another device linked to the same YT Zero sees the same state through the server, so no CloudKit is needed in this mode.
   - **Without YT Zero:** subscriptions and watch state live in GRDB and sync through the **CloudKit private database** (`CKSyncEngine`).
   - **Schema:** synced tables carry the sync metadata from M1 (`modifiedAt`, tombstone, record system fields). Sync itself ships in M7, as the plan says.
   - **Switching modes is an import, not a migration.** Linking YT Zero offers to push local subscriptions to it; unlinking copies the current list into local storage.

3. **YT Zero's maintenance risk is why the local + CloudKit path is first-class**, not a fallback. If YT Zero stops working, the user unlinks it and keeps everything.

4. **Contract additions (Core).**
   - **New `SubscriptionAccount` protocol** for sources that own the user's subscriptions and watch state. It covers:
     - the channel list
     - follow and unfollow
     - the feed page
     - progress read and write
     - watched state

     YT Zero implements it. `VideoSource` stays the stateless, per-request contract.
   - **YT Zero as a `VideoSource`** declares only what it does well: `.streams` (HLS via playback ticket), `.search`, `.comments` and `.channel` (its feed filtered by channel). It does not declare `.subscriptions`; that capability is the batched public feed.

5. **Feed without YT Zero.** `.subscriptions` routes to Piped's batched feed (chunks of 50 channels) or, on Invidious, per-channel Atom feeds fetched concurrently (at most 6 at a time).
   - **Missing durations** (Invidious Atom) are filled lazily when a video's details are fetched.
   - **Piped's 30-day window** is fine for a feed, because older items are already in GRDB from earlier refreshes. A first-time import backfills each channel through `channel(_:)`.

6. **Stream routing order: Piped and Invidious first, YT Zero last.** The first two offer AV1/VP9 and higher resolutions, while YT Zero is H.264 ≤1080p. YT Zero streams bypass `FormatSelector` (one rendition) and play as `.hls(ticketURL)`. `FormatSelector` still applies to the others.

7. **Secrets.**
   - **YT Zero access token:** stored in the Keychain (`kSecAttrAccessibleAfterFirstUnlock`), never in GRDB or UserDefaults.
   - **Instance URLs:** stored in GRDB. They are user data, never committed to the repository.

## Consequences

- **New Core API:** `SubscriptionAccount`, plus a device-auth helper for YT Zero.
- **Library modes:** the subscription repository has two backends (YT Zero mirror, local + CloudKit) behind one interface, so features don't care which is active.
- **Contract tests** cover each adapter against the owner's instances (`.env.local`, never committed), plus fixture-based decoding tests on every CI run.
