#!/usr/bin/env bash
# Fails if a built mpv/FFmpeg binary contains GPL or nonfree components (CLAUDE.md: no GPL anywhere).
#   scripts/check-licenses.sh <path to MPVRuntime binary or an .app containing it>
set -euo pipefail

target="${1:?usage: check-licenses.sh <binary or .app>}"
if [[ -d "$target" ]]; then
    target="$(find "$target" -path "*MPVRuntime.framework/MPVRuntime" -type f | head -1)"
    [[ -n "$target" ]] || { echo "✘ No MPVRuntime.framework found"; exit 1; }
fi

strings_out="$(xcrun strings -a "$target")"
failures=0

forbid() {
    if grep -qE -- "$1" <<<"$strings_out"; then
        echo "✘ Found forbidden marker: $2"
        failures=$((failures + 1))
    fi
}

forbid 'license: (GPL|nonfree|unredistributable)' "FFmpeg library built as GPL/nonfree"
forbid '--enable-gpl' "FFmpeg configured with --enable-gpl"
forbid '--enable-nonfree' "FFmpeg configured with --enable-nonfree"
forbid '-Dgpl=true' "mpv configured with -Dgpl=true"
forbid 'smbc_' "libsmbclient (GPLv3) linked"

ffmpeg_libs="$(grep -cE '^lib(avcodec|avformat|avutil|swscale|swresample|avfilter|avdevice) license: LGPL' <<<"$strings_out" || true)"
if [[ "$ffmpeg_libs" -lt 5 ]]; then
    echo "✘ Expected FFmpeg libraries to report an LGPL license, found $ffmpeg_libs"
    failures=$((failures + 1))
fi
grep -q -- '-Dgpl=false' <<<"$strings_out" || { echo "✘ mpv build options not found (expected -Dgpl=false)"; failures=$((failures + 1)); }

if (( failures > 0 )); then exit 1; fi
echo "✔ mpv/FFmpeg are LGPL-only ($ffmpeg_libs FFmpeg libraries report LGPL; mpv -Dgpl=false)."
