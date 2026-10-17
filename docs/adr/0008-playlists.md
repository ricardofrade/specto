# 0008 — Playlists: channel playlists, saving, Play All

Date: 2026-10-17. Status: accepted.

## Decisions

1. **`VideoSource.channelPlaylists(_:cursor:)`** joins the contract and returns `Page<PlaylistSummary>`. Unsupported sources throw `.unsupported(.playlists)`; YT Zero is one, so a channel shows no Playlists tab when only YT Zero is configured.
   - **Piped:** the channel's `playlists` tab, through `channels/tabs`. Every page needs the tab's `data`, so the cursor carries `data` and `nextpage` together, as JSON.
   - **Invidious:** `/api/v1/channels/:id/playlists`.
     - **Thumbnails:** its playlist thumbnails point at i.ytimg.com, so they are rewritten to the instance's `/vi/<id>/mqdefault.jpg`. The device never contacts Google.
     - **Channel name:** its `author` field reads "Playlist", so the channel screen fills in the channel's name instead.
2. **Saved playlists live in GRDB** (`savedPlaylist`, migration v6) and sync through CloudKit as a fourth record type.
   - They aren't YouTube data a linked YT Zero account owns, so they sync in both scopes (ADR 0006).
   - Removal is a tombstone.
   - Opening a saved playlist refreshes its title, count and thumbnail.
3. **Play All doesn't touch the queue.** The queue is the person's own list, and in builds with offline audio, queued videos download, so a 300-video playlist would fill the disk.
   - **What it does instead:** Play All, or tapping a video inside a playlist, sets a playlist context on the environment.
   - **Auto-advance:** it plays the queue first, then the next video in the context.
   - **Size limit:** Play All loads at most 500 videos.
4. **The open player follows auto-advance on iPhone and iPad**, not just on Apple TV. When the session moves to another video, the Watch screen switches to it. Before this, queue auto-advance on iOS kept showing the previous video's details.
5. **Library's first section links to Channels and Playlists**, each with its count, in the style of Music's Library.

## Device check

None beyond the simulator tests (`PlaylistsUITests` against a real Piped instance). On a device: Play All a playlist, lock the phone, and check that the next video starts in audio mode when one ends.
