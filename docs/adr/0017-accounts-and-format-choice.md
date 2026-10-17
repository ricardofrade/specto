# 0017 — Signing in to Piped, Invidious and YT Zero; choosing the format

Date: 2026-10-17. Status: accepted.

## Accounts

1. **Signing in with a username and password:**
   - **Piped:** `POST /login` answers a token, used for `/subscriptions`, `/subscribe`, `/unsubscribe` and `/feed`.
   - **Invidious:** its sign-in form sets an `SID` session cookie, which `/api/v1/auth/subscriptions` and `/api/v1/auth/feed` accept.
   - **YT Zero:** a password sign-in approves this device's pairing code with that session, so a browser on a second device isn't needed. Pairing by code still works.
   - **Where the credentials go:** only to that instance. The app keeps only what it answers (token or session) in the Keychain, under the instance's key. That travels to the person's other devices inside end-to-end-encrypted iCloud fields, as YT Zero's always has. `InstanceStore.touch` marks the instance changed so it syncs.
2. **The first signed-in instance, in the person's order, owns YouTube subscriptions** (ADR 0002 widened from YT Zero to any account).
   - **Signing in never loses anything:** local YouTube subscriptions the account lacks are added to it first.
   - **The Instances screen shows the roles:** "Signed in", or "Signed in · Your subscriptions" on the owner.
   - **Signing out of Piped or Invidious** keeps the instance for browsing and playing.
   - **What isn't synced back:** Piped keeps no watch history, and Invidious's history isn't synced yet.
3. **PeerTube subscriptions stay local** (ADR 0016).

## Format

4. **`StreamFormat`: Auto, AV1, VP9, H.264 (MP4) or HLS.**
   - **Where it's set:** a default in Settings → Video Quality, and a per-video choice in the player's menu. The menu lists only formats the video has and the device decodes; AV1 needs hardware decoding.
   - **What a pick does:** a codec narrows the streams to it. AV1 and VP9 stay in mpv rather than turning into AVPlayer's H.264. HLS plays the instance's HLS stream.
   - **Fallback:** a format the video lacks falls back to Auto.
   - **Re-planning:** like a quality pick, it re-plans at the current position.
