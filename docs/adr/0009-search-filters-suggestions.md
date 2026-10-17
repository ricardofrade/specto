# 0009 — Search filters, suggestions and recent searches; sleep timer

Date: 2026-10-17. Status: accepted.

## Search

1. **The contract gains `search(_:filter:cursor:) -> Page<SearchResult>` and `suggestions(for:)`.**
   - `SearchResult` is a video, a channel or a playlist.
   - **Defaults:** the default implementation maps video-only sources onto the new call (other filters are unsupported), and `suggestions` returns none. YT Zero works unchanged.
   - **Piped:** `filter=videos|channels|playlists` and `/suggestions`.
   - **Invidious:** `type=video|channel|playlist` and `/api/v1/search/suggestions`.
2. **Invidious channel avatars now go through the instance's `/ggpht/` proxy.** Search results and channel pages returned `yt3.ggpht.com` / `yt3.googleusercontent.com` URLs, which made the device fetch from Google directly. That was an existing leak on channel pages, fixed here. `InvidiousDTO.proxied` rewrites them, and tests assert the host.
3. **Suggestions are on by default and can be turned off in Settings.**
   - What's typed goes to the person's own instance, which asks YouTube from its own IP, just like a search.
   - Requests are debounced by 250 ms and capped at 8 results.
   - The Search empty state no longer claims "nothing is sent until you search". It now says suggestions and results come from your instances.
4. **Recent searches are kept in GRDB** (`recentSearch`, migration v7) on this device only. They are never synced or sent anywhere.
   - They're limited to the newest 20, de-duplicated case-insensitively.
   - **Ties:** two searches in the same millisecond are ordered by insertion (`rowid`), not by luck.
   - **Where they show:** on iPhone and iPad, Recent is the idle Search screen (swipe to remove, Clear). On Apple TV, recent searches are the field's suggestions before typing.
5. **Changing the filter searches the submitted query again.** On iOS the filters are search scopes. On tvOS they are search scopes too, which tvOS shows without the on-presentation activation.

## Sleep timer

6. **`SleepTimer` (Playback)** offers 15, 30, 45 and 60 minutes, or the end of the current video.
   - **Countdown:** it counts down a minute at a time and publishes a pre-formatted status ("12 min left").
   - **When it fires:** it pauses the session.
   - **End of video:** auto-advance asks `stopsAtEndOfVideo()` before playing the next video.
   - **Tests:** the sleep function is injected, so tests run instantly. A cancelled countdown never writes its status; a test caught that race.
7. **Where it lives in the UI:**
   - **iPhone and iPad:** a submenu of Playback Settings.
   - **Apple TV:** Subtitles, Speed, Quality and Sleep Timer became one row of menus in the player's info panel. Six shelves no longer fit on a 1080p screen.
