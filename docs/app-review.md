# App Review: probe build notes (draft)

For the M2 probe submission and, refined, the M5 final submission. Owner action: submit from App Store Connect with the owner's developer account.

## Positioning

- **What it is:** a client for the user's own self-hosted video servers (Piped, Invidious, YT Zero). It ships with no server, no default instance, and no content of its own.
- **No branding:** no YouTube name, logo or trade dress in the app name, icon, screenshots or metadata.
- **No downloading or saving of media** (guideline 5.2.3). Playback only.
- **Privacy:** no analytics, no tracking, no account with us. The app talks only to servers the user adds.

## Review notes (paste into App Store Connect)

> This app is a player for self-hosted video servers that the user runs themselves (open-source Piped, Invidious, or YT Zero). It has no content or server of its own.
>
> To review, add our demo server:
> 1. Open the app → Settings → Add Instance.
> 2. Enter: `<demo instance URL>` → Next. (The app detects the server type.)
> 3. Settings → Import Subscriptions… is optional; the Search tab works immediately.
> 4. Tap any video to play. Swipe the player down to keep it playing in the mini-player.
>
> The demo server is available for the whole review period. Contact: `<email>`.

Fill in the demo instance URL and contact details at submission time. Never commit them.

## Demo instance checklist (owner)

- **Health:** a Piped API instance that answers `/healthcheck` with `OK` and plays videos from the reviewer's region.
- **Location:** not on a home network (the reviewer can't reach a LAN address). Use the owner's public demo host.
- **Reachability:** keep it up for the whole review, and confirm from outside the home network before submitting.

## Fallback if rejected

Planned in M5: TestFlight, an EU alternative marketplace (iOS/iPadOS), and direct install on the owner's devices.
