# 0014 — Explore, and trending by category

Date: 2026-10-17. Status: accepted.

## Context

Trending showed only on an empty Home. The redesign gives it its own tab, Explore, because it's the only discovery a privacy client has without recommendations. Invidious also takes a trending `type` (music, gaming, movies), but checked against a real instance only Gaming returns its own list: YouTube no longer has Music or Movies trending, and Invidious answers those with the general list. Piped and YT Zero have no categories.

## Decisions

1. **Contract: `VideoSource.trending(region:category:)` with `TrendingCategory` (`all`, `gaming`).** Music and Movies are left out: showing them would repeat the general list under another name.
   - **Default implementation:** answers `.all` from `trending(region:)` and throws `unsupported(.trendingCategories)` for the rest. Adapters without categories change nothing.
   - **Invidious:** declares the new `.trendingCategories` capability and sends `type=`.
   - **Routing:** the router sends category requests only to instances with that capability.
2. **Explore caches every list (`TrendingStore`, migration v11, one list per category):**
   - It opens on the last list it saw and refreshes behind it, at most hourly unless pulled. This follows the stale-while-revalidate rule every screen follows.
   - Listed videos are exempt from the feed's prune.
   - The lists are this device's: they're the instance's, not the person's, so they don't sync.
3. **Category chips show only when an Invidious instance is configured.** Otherwise Explore is the general list for the person's region.
4. **Search before typing shows the top of the general list,** so the first trending fetch happens after launch, not only when Explore opens.
5. **Invidious stamps its general trending list with the fetch time** ("0 seconds ago" on every video). When every video in the list shares one date, the adapter drops the dates instead of showing a wrong "1 second ago". The Gaming list has real dates and keeps them.
