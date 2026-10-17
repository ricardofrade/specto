# 0012 — Watch Later and the person's own playlists

Date: 2026-10-17. Status: accepted.

## Decisions

1. **One row per playlist, its videos as an ordered JSON list** (`userPlaylist`, migration v9).
   - **What a row holds:** the videos are stored as summaries, so a playlist shows titles and thumbnails on a device that never cached them.
   - **Size cap:** a playlist holds at most 500 videos. That keeps the synced record far below CloudKit's 1 MB.
2. **A playlist syncs as one record (`UserPlaylist`): the whole list wins or loses as a unit.**
   - **Why:** per-item records would need ordering keys and merging. For lists edited on one device at a time, last-writer-wins on the whole list is simpler, and the order can never come out mixed.
   - **The cost:** two devices editing the same playlist within one sync window keep only the later edit.
   - **Scope:** these playlists sync in both sync scopes (ADR 0006); a linked YT Zero account doesn't own them.
3. **Watch Later is a built-in playlist** (`id = "watch-later"`).
   - It always appears first and can't be renamed or deleted.
   - It's created on first use, and its title is shown localized.
   - Library counts it only once it has something in it.
4. **Where you save from:**
   - **iPhone and iPad:** "Save to Watch Later" and "Save to Playlist…" in a video's menu, and a Save button in the player. Both open a sheet with checkmarks and New Playlist.
   - **Apple TV:** "Save to Watch Later" on every card, plus a "Your Playlists" shelf in Library.
   - **Presentation:** the sheet presents from the player when it's open, because a sheet can't present over a full-screen cover from below it.
5. **Playing works like a saved playlist's Play All** (ADR 0008): it sets the playlist context, and the queue stays untouched.
6. **Backups carry them** (an optional `userPlaylists` field, so older backups still restore). Restoring adds missing playlists, and adds missing videos to Watch Later or to a playlist that's already here.
