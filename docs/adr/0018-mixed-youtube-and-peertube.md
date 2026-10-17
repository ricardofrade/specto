# 0018 — YouTube and PeerTube side by side

Date: 2026-10-17. Status: accepted.

With Piped, Invidious, YT Zero and a PeerTube server all added, ADR 0016 already kept the two
networks' content apart: YouTube's front-ends decline PeerTube IDs, and PeerTube steps aside
for general queries beside a YouTube instance. That was correct but invisible: there was no way
to search PeerTube, nor to see where a video came from or who keeps which subscriptions. This
record covers how the app now shows and steers it.

## Decisions

1. **Instances are grouped by network.**
   - **Each section says how its network works.** YouTube's footer names who keeps the
     subscriptions: "kept in your account on <instance>" when an account is linked (ADR 0017),
     otherwise "in the app", with iCloud mentioned only when sync is actually running. With
     several YouTube instances, it also says which is asked first.
   - **PeerTube's footer** says subscriptions stay in the app, videos play from their own
     server, and Search looks on every server listed.
2. **"Prefer" for a YouTube instance.**
   - `InstanceRouter(preferred:)` asks that instance first while its circuit is closed; the
     others follow by speed, and failover is unchanged. A cooling-down preferred instance
     drops back into the speed order until it recovers.
   - **Stored per device** (`AppSettings.preferredInstance`), not synced. A preference often
     depends on the network the device is on (say, a LAN instance at home).
3. **Search has a YouTube | PeerTube switch** when both are set up; the pick is remembered.
   - **PeerTube searches every server at once** (`PeerTubeSearch`). Each server indexes
     different videos, so asking only the first would hide most of them. Results interleave
     one per server; a federated video known to several servers appears once, from the
     earliest server in the person's order. A failing server is left out; only all failing is
     an error. PeerTube pages by offset, so one cursor serves every server.
   - **With PeerTube alone and several servers,** search merges them the same way.
   - **YouTube's suggestions aren't fetched while PeerTube is picked,** so a PeerTube search
     doesn't send its words to YouTube.
4. **PeerTube's videos carry a mark** (`marksPeerTube`, set when both networks are present)
   on every video cell and on Apple TV cards. A PeerTube channel's page names its home server.
   With PeerTube alone the mark would say nothing, so it's off.
5. **`-SeedYTZero <URL> <token>`** seeds a linked YT Zero for UI tests, so all four kinds run
   together (`FourInstancesUITests`). The token is read from the git-ignored
   `.ytzero-test-token` by `scripts/live-ui-tests.sh` and passed as `TEST_RUNNER_YTZERO_TOKEN`.

## Deferred

- **The same channel on both networks** (Blender is on YouTube and on video.blender.org).
  Following both shows each video twice on Home. Merging by title and length risks hiding
  different videos, so it waits until it bothers someone. A likely shape: offer to merge when
  the second copy is followed, then show each pair once, from the preferred network.
