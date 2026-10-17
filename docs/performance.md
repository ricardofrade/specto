# Launch performance

Gate: cold launch to the first rendered feed under 400 ms, measured on a device (`launch.firstFeedFrame`).
The simulator is only a trend: its dynamic loader (`dyld_sim`) has none of a device's launch optimisations.

## 2026-10-17: profile (iPhone 18 Pro simulator, Release)

`xctrace record --template 'App Launch'`, main thread, about 480 ms sampled:

| Where | ms | Notes |
|---|---:|---|
| dyld, before `main` | ~245 | Loading the app and its frameworks. The simulator exaggerates this phase. |
| Swift protocol-conformance lookups | ~40 | Runtime cost of the types SwiftUI touches first. |
| `AppEnvironment` init | ~33 | Database open and migrations ~11, audio session ~9, Now Playing ~4. |
| SwiftUI and UIKit first frame | rest | |

## Findings

- **Frameworks:** the app links only `MPVRuntime`. MPVKit's 27 stub frameworks are embedded but never loaded, so they add about 1 MB to the download and nothing to launch time.
- **`MPVRuntime`:** at 36 MB it's loaded at launch although nothing plays yet. Deferring it would mean loading mpv on first playback, a larger change to the engine. Do it only if a device trace shows its load above roughly 50 ms.
- **Done:** the audio session and Now Playing / remote commands are now set up on the first playback, not at launch (`AppEnvironment.prepareForPlayback`). Simulator launch went from 1.602 s to 1.507 s (−95 ms, run-to-run variation about 1 %).

## Device checks (owner)

1. Run `SpectoPerf` on the iPhone (`RELEASE_GATE=1 scripts/perf-gate.sh`) and record `launch.firstFeedFrame`.
2. If it misses 400 ms, record an App Launch trace on the device. If `MPVRuntime` dominates the pre-`main` phase, load mpv on first playback.
