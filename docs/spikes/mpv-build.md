# Spike: LGPL-only mpv build (M0 task 4)

Date: 2026-10-16. Result: **go**, with MPVKit's non-GPL product wrapped in our own dynamic framework.

## What was tried

1. **MPVKit** (github.com/mpvkit/MPVKit) ships prebuilt xcframeworks with two products: `MPVKit` (non-GPL) and `MPVKit-GPL`. We use only `MPVKit`, pinned `from: "1.0.0"`, which is its newest stable release. `1.1.0-n9.0.2` is newer but marked prerelease, so it's excluded by the stable-only dependency rule.
2. **Building libmpv and FFmpeg ourselves.** Not needed: MPVKit's build is open (its `Sources/BuildScripts` and `mpvkit/*-build` repos), reproducible, and audited below.

## License audit

Audited from MPVKit's build scripts and the shipped binaries. Full report from the audit: FFmpeg's configure line, mpv's meson options and each dependency's options.

- **FFmpeg** (avcodec, avformat, avutil, avfilter, avdevice, swscale, swresample): no `--enable-gpl`, no `--enable-nonfree`. It does use `--enable-version3`, because gmp requires it, so the effective license is **LGPLv3+**. The built binaries say so: "libavcodec license: LGPL version 3 or later".
- **mpv** is built with `-Dgpl=false`, which the binary's embedded configuration confirms. mpv's own Copyright file notes that this flag excludes GPL-only code.
- **Dual-licensed dependencies:** for gmp, nettle/hogweed and gnutls's bundled libunistring we elect **LGPLv3+**, not GPLv2+. gnutls is built with `--disable-openssl-compatibility --disable-tools`, which excludes its GPL parts.
- **Other dependencies:**
  - libbluray: LGPLv2.1+, with the Java BD-J part disabled.
  - libplacebo, fribidi: LGPLv2.1+.
  - uchardet: MPL 1.1, elected over its LGPL/GPL options.
  - FreeType: FTL, elected over GPLv2.
  - dav1d: BSD-2.
  - uavs3d: BSD-3.
  - libass, HarfBuzz, lcms2, libunibreak, libdovi: permissive.
  - OpenSSL 3, MoltenVK, shaderc: Apache-2.0.
- **libsmbclient (GPLv3)** is linked only by `MPVKit-GPL`. None of its symbols appear in our binary.

**Enforced in CI:** `scripts/check-licenses.sh` scans the built `MPVRuntime` binary. It fails on GPL or nonfree FFmpeg, `--enable-gpl`, `--enable-nonfree`, `-Dgpl=true` or `smbc_`, and requires the FFmpeg libraries to report LGPL. It was verified against the real binary (passes) and against a planted GPL marker (fails).

## Linking: static archives inside one dynamic framework

MPVKit's xcframeworks are **static** archives. Statically linking LGPL code into an App Store app would oblige us to ship a relink kit: the app's object files plus link instructions. Instead, `Packages/MPVRuntime` is a SwiftPM `.dynamic` library that links MPVKit and re-exports libmpv (`@_exported import Libmpv`). The shipped app then contains one replaceable `MPVRuntime.framework` holding all LGPL code. That satisfies LGPL's replaceability requirement with source and notices alone.

How it was made to work:

- **`-all_load` fails.** FFmpeg's static libraries intentionally duplicate internal symbols (`ff_vk_*`, `aes_v8_*`), so force-loading every object collides.
- **Instead, the framework references one client-API symbol** (`mpv_client_api_version`). That pulls libmpv's client object and its real dependency graph in through normal linking. All 54 `mpv_*` functions and the FFmpeg API are exported, as `xcrun nm -gU` confirms.
- **System frameworks MPVKit doesn't declare** must be linked explicitly: UIKit, OpenGLES, IOSurface, CoreText, CoreGraphics, QuartzCore.
- **The module is named `MPVRuntime`, not `LibMPV`.** macOS's case-insensitive file system makes `LibMPV` collide with MPVKit's `Libmpv` module.

**Size:** 36 MB (Debug, simulator, arm64). Measure the Release device slice and its effect on the 400 ms cold-launch gate on device; it is one dylib, so dyld cost should be small.

## Feature coverage (non-GPL build)

| Feature | Present |
|---|---|
| VideoToolbox hwdec (H.264, HEVC, VP9, AV1) | yes |
| `vo=gpu-next` with Vulkan over MoltenVK | yes |
| AV1 software (dav1d) | yes, but **built without assembly**: slow. Our policy uses AV1 only with hardware decode, so this is acceptable. |
| VP9 software (libvpx-free FFmpeg decoder, NEON) | yes |
| DASH, HLS, MP4 and MKV demuxers | yes |
| Slices | iOS device, iOS simulator (arm64 and x86_64), tvOS device, tvOS simulator |

## Risks

- **"Learning" disclaimer.** MPVKit's README says it is "only suitable for learning libmpv" and points production users to AetherEngine. AetherEngine is an FFmpeg-based engine, not libmpv, under a non-standard license, so it doesn't fit our mpv decision. **Mitigation:** the build is open and reproducible, and the `MPVRuntime` wrapper isolates the rest of the code from where libmpv comes from. If MPVKit stalls, we build the same configuration ourselves from its scripts.
- **Unpinned dependency:** uavs3d is built from unpinned master upstream.
- **Legal questions for counsel** (not engineering):
  - Whether LGPLv3's "Installation Information" clause and App Store terms count as further restrictions.
  - Whether the EULA must permit the reverse engineering LGPL requires for the library.
  - Publishing the exact LGPL sources, MPVKit's patches included, alongside each release.

## How to rebuild

`MPVRuntime` resolves MPVKit's binaries through SwiftPM: `xcodebuild build -scheme MPVRuntime` in `Packages/MPVRuntime`. To rebuild the binaries from source, run MPVKit's `make build` with its build scripts, which need meson, ninja and nasm on the host. Its non-GPL flags are the ones audited above.

## Owner checks

- **Release size:** confirm the Release `MPVRuntime.framework` size, and its cold-launch impact on the iPhone 15 Pro Max.
- **Counsel:** get answers to the legal questions above before public distribution.
