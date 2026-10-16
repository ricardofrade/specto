#!/usr/bin/env bash
# Enforces the dependency rules in CLAUDE.md. Exits non-zero on any violation.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
failures=0

fail() {
    echo "✘ $1"
    failures=$((failures + 1))
}

# Local packages each package may depend on. Arrows point downward only.
allowed_for() {
    case "$1" in
        Core)         echo "" ;;
        DesignSystem) echo "" ;;
        MPVRuntime)   echo "" ;;
        Cast)         echo "" ;;
        Library)      echo "core" ;;
        Playback)     echo "core mpvruntime" ;;
        Features)     echo "core library playback designsystem" ;;
        *)            echo "UNKNOWN" ;;
    esac
}

for dir in "$root"/Packages/*/; do
    package="$(basename "$dir")"
    allowed="$(allowed_for "$package")"
    if [[ "$allowed" == "UNKNOWN" ]]; then
        fail "$package: not in the allow-list in scripts/check-dependencies.sh; add it deliberately"
        continue
    fi

    manifest="$(xcrun swift package dump-package --package-path "$dir")"

    for dependency in $(jq -r '.dependencies[] | .fileSystem[0]?.identity // empty' <<<"$manifest"); do
        [[ " $allowed " == *" $dependency "* ]] || fail "$package depends on local package '$dependency'"
    done

    # Within one package, a feature target must not depend on another feature target.
    if [[ "$package" == "Features" ]]; then
        jq -r '
            ([.targets[] | select(.type == "regular") | .name]) as $features
            | .targets[] | select(.type == "regular") | .name as $target
            | .dependencies[] | (.byName[0]? // .target[0]? // empty)
            | select(. as $dep | $features | index($dep)) | "\($target) -> \(.)"
        ' <<<"$manifest" | while read -r edge; do
            echo "✘ Features: feature targets must not depend on each other ($edge)"
            exit 1
        done || failures=$((failures + 1))
    fi
done

# Domain packages stay UI-free.
# (`*UI` targets, such as PlaybackUI, exist precisely to hold the views.)
for package in Core Library Playback; do
    if grep -rEn --exclude-dir='*UI' '^\s*import\s+SwiftUI' "$root/Packages/$package/Sources" >/dev/null 2>&1; then
        fail "$package imports SwiftUI"
    fi
done
if grep -rEn '^\s*import\s+UIKit' "$root/Packages/Core/Sources" >/dev/null 2>&1; then
    fail "Core imports UIKit"
fi

if (( failures > 0 )); then
    echo "$failures dependency rule violation(s)."
    exit 1
fi
echo "✔ Dependency rules hold."
