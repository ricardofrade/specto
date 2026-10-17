# 0016 — PeerTube as a source, and public servers to choose from

Date: 2026-10-17. Status: accepted.

## Context

Every source so far fronts YouTube (Piped, Invidious, YT Zero). That's the app's main risk at App Review, and it leaves someone without a server of their own with nothing to watch. PeerTube servers host their own videos, often under free licences, behind a clean public API. joinpeertube.org keeps an index of public servers. Yattee 2.0 offers that index as a list to pick from.

## Decisions

1. **`SourceKind.peerTube` and `PeerTubeSource`** cover search, trending (with Gaming as PeerTube's category 7), channels with banners, playlists, comments, subscriptions (each channel's latest uploads) and playback.
   - **Streams:** the server's HLS playlist, which AVPlayer and mpv play as is, with a plain MP4 file as the fallback.
   - **Scrubbing previews:** come from the server's storyboards.
   - **Up Next:** the channel's latest videos, because PeerTube has no recommendations.
   - **Not available:** SponsorBlock and DeArrow are YouTube's, so they're skipped for PeerTube videos.
2. **IDs carry their server: `pt:<host>:<uuid>`.** Channels use their `name@host` handle, and playlists their UUID.
   - **Why:** PeerTube content is addressed per server, and YouTube IDs never contain a colon, so the two can't collide.
   - **Routing:** `YouTubeOnly` wraps the YouTube front-ends and declines PeerTube IDs. `PeerTubeSource` declines anything not from its server. The new `SourceError.belongsElsewhere` moves the router to the next instance without counting against the one that declined.
   - **Why at the edges:** none of the router's call sites had to change.
3. **Mixed setups:**
   - **With a YouTube front-end added:** search and Explore's main list stay YouTube's. PeerTube appears as its own "PeerTube" list in Explore, and its channels, videos and subscriptions work everywhere.
   - **PeerTube only:** it answers search and Explore too, under "Trending on PeerTube".
   - **The feed:** refreshes YouTube channels in one batch and PeerTube channels per server. One unreachable server doesn't sink the rest.
4. **Public servers (revising the "no built-in instance" rule):**
   - **YouTube front-ends:** still never built in, as before.
   - **PeerTube:** Add Instance lists public servers from joinpeertube.org's index, healthy and non-NSFW only, the most videos first, and the person's language first.
   - **Why this keeps to the rule's intent:** nothing is preconfigured or added without the person choosing.
   - **App Review:** a reviewer can use the app fully on a public PeerTube server, with no YouTube involved.
5. **Privacy:** PeerTube media comes from PeerTube servers, never Google.
   - **Why the proxy rule doesn't apply:** "streams through the instance's proxy" exists because googlevideo binds stream URLs to the requester's IP. That doesn't arise here.
   - **What PeerTube servers see:** a federated video's files may come from the server that hosts it, so that server sees the request. This is how PeerTube works for everyone.
