#!/usr/bin/env bash
# The whole CI pipeline; GitHub Actions runs exactly this, and so can you locally.
#   scripts/ci.sh            dependency rules, package tests, app build, performance tests
#   SKIP_PERF=1 scripts/ci.sh   everything except the (slow) performance tests
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="${CI_OUTPUT:-$root/build/ci}"
mkdir -p "$out"

# Newest available iPhone Pro simulator, unless one is given.
if [[ -z "${SIMULATOR_ID:-}" ]]; then
    SIMULATOR_ID="$(xcrun simctl list devices available -j | jq -r '
        [.devices | to_entries[] | select(.key | test("iOS")) | .value[]
         | select(.name | test("^iPhone [0-9]+ Pro$"))] | last | .udid')"
fi
[[ -n "$SIMULATOR_ID" && "$SIMULATOR_ID" != "null" ]] || { echo "No iPhone Pro simulator found"; exit 1; }
destination="platform=iOS Simulator,id=$SIMULATOR_ID"
echo "Simulator: $SIMULATOR_ID"

step() { echo; echo "▶ $1"; }

step "Dependency rules"
"$root/scripts/check-dependencies.sh"

# Runs xcodebuild with its full log in $out/<name>.log; shows test results and errors only.
run() {
    local name="$1"; shift
    local status=0
    "$@" > "$out/$name.log" 2>&1 || status=$?
    grep -E "error:|✘|Test run with|Executed [0-9]+ tests|measured \[|Frame rate reading" "$out/$name.log" | sort -u || true
    if [[ $status != 0 ]]; then echo "✘ $name failed (exit $status, log: $out/$name.log)"; exit 1; fi
}

for package in Core Library Playback; do
    step "Unit tests: $package"
    (cd "$root/Packages/$package" && run "test-$package" xcodebuild test -scheme "$package" \
        -destination "$destination" -derivedDataPath "$out/dd-$package")
done

step "Generate and build the app"
xcodegen generate --spec "$root/App/iOS/project.yml" --quiet
run build-app xcodebuild build -project "$root/App/iOS/Player.xcodeproj" -scheme Player \
    -destination "$destination" -derivedDataPath "$out/dd-app"

step "License gate (no GPL in the shipped mpv/FFmpeg)"
"$root/scripts/check-licenses.sh" "$out/dd-app/Build/Products/Debug-iphonesimulator/Player.app"

if [[ -n "${SKIP_PERF:-}" ]]; then
    echo; echo "✔ CI passed (performance tests skipped)"
    exit 0
fi

step "Performance tests (Release)"
run perf xcodebuild test -project "$root/App/iOS/Player.xcodeproj" -scheme Player -configuration Release \
    -destination "$destination" -derivedDataPath "$out/dd-perf"

echo; echo "✔ CI passed"
