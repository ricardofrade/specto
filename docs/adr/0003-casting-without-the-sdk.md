# 0003 — Casting without Google's Cast SDK

Date: 2026-10-16. Status: accepted.

## Context

M4 asks for Google Cast to the default media receiver, tested on the owner's Chromecast with Google TV. Google's Cast iOS SDK is a closed-source binary:

- it collects usage data;
- it's distributed outside SwiftPM's normal channels;
- it would be the only proprietary, telemetry-bearing dependency in an app whose premise is privacy.

## Decision

Implement a minimal **Cast v2 sender** against the open protocol, in our own `Cast` package (about 400 lines, no dependencies):

- **Discovery:** Bonjour `_googlecast._tcp` via `NWBrowser`. Needs `NSBonjourServices` and the local-network permission.
- **Transport:** TLS to port 8009, with frames of a 4-byte length plus a protobuf `CastMessage`. Only six fields are hand-encoded. Receivers use self-signed certificates, so trust rests on the local network itself.
- **Flow:**
  1. `CONNECT` to `receiver-0`.
  2. `LAUNCH` the default media receiver (`CC1AD845`).
  3. Read `RECEIVER_STATUS` for the app's `transportId`, then `CONNECT` to it.
  4. Send media `LOAD` with the content URL, type, metadata and start time.
  5. `PLAY`, `PAUSE`, `SEEK` and `STOP` use the `mediaSessionId`. Heartbeat `PING`/`PONG` runs every 5 s.
- **What gets cast:** the receiver fetches media itself, so it needs a URL served by the instance:
  - HLS: Piped's `hls`, or a YT Zero playback ticket.
  - DASH: Invidious's `dashUrl` with `local=true`.
  - A muxed file.

  On-device HLS can't be cast, because those playlists exist only inside the app.

## Verification

- **Unit tests:** protobuf byte layout, framing (including partial frames), and state from `MEDIA_STATUS`.
- **Live, read-only:** `CastLiveProbeTests` discovered both receivers on the owner's network ("Chromecast", "Sony BRAVIA"). It completed a real TLS and protobuf exchange with the Chromecast (`GET_STATUS` → `RECEIVER_STATUS`) without launching anything.
- **Not yet done:** an actual `LOAD`, which plays on the TV. It's waiting for the owner's go-ahead, since it switches on and plays on a TV in their home.

## Consequences

- No proprietary SDK, telemetry or binary in the app.
- **No Cast dialog:** we don't get Google's standard Cast dialog or its mini-controller; the app provides its own (a Cast menu, plus a "Playing on …" overlay with controls).
- **Format coverage:** casting depends on the instance offering HLS or DASH. Piped VOD `hls` and Invidious `dashUrl` cover the common cases.
- **Guest mode:** proximity pairing isn't supported. It's an SDK-only feature and needs a cloud relay anyway.
