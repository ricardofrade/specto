# Third-party dependencies

Every dependency, its license and where it's used. No GPL or nonfree components anywhere (CLAUDE.md). Versions are the newest stable releases (no prereleases).

| Dependency | Version | License (as elected) | Used by | Source |
|---|---|---|---|---|
| GRDB.swift | 7.11.1 (`from: "7.11.1"`) | MIT | `Library` | https://github.com/groue/GRDB.swift |
| MPVKit (non-GPL product only) | 1.0.0 (`from: "1.0.0"`) | LGPL-3.0 (package) | `MPVRuntime` | https://github.com/mpvkit/MPVKit |

## Inside MPVKit (shipped in `MPVRuntime.framework`, a replaceable dynamic library)

| Component | License (as elected) | Build notes |
|---|---|---|
| mpv | LGPLv2.1+ | `-Dgpl=false` |
| FFmpeg (avcodec, avformat, avutil, avfilter, avdevice, swscale, swresample) | LGPLv3+ | no `--enable-gpl`, no `--enable-nonfree`; `--enable-version3` (gmp) |
| gmp, nettle/hogweed | LGPLv3+ (dual LGPLv3+/GPLv2+) | |
| gnutls (incl. libunistring) | LGPLv2.1+ / LGPLv3+ | `--disable-openssl-compatibility --disable-tools` |
| libbluray | LGPLv2.1+ | BD-J (Java) disabled |
| libplacebo, fribidi | LGPLv2.1+ | |
| uchardet | MPL-1.1 | |
| FreeType | FTL | |
| libass | ISC | |
| HarfBuzz | MIT | |
| lcms2 | MIT | |
| libunibreak | zlib | |
| libdovi | MIT | |
| dav1d | BSD-2-Clause | no assembly |
| uavs3d | BSD-3-Clause | |
| OpenSSL 3 | Apache-2.0 | |
| MoltenVK, shaderc | Apache-2.0 | |

LGPL obligations: ship these notices, offer the exact corresponding sources (including MPVKit's patches), and keep `MPVRuntime.framework` dynamic. See `docs/spikes/mpv-build.md`. `scripts/check-licenses.sh` enforces no GPL in CI.

## Build tooling (not shipped)

| Tool | License | Purpose |
|---|---|---|
| XcodeGen | MIT | Generates `App/iOS/Player.xcodeproj` from `project.yml` |
