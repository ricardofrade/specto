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

for package in Core Library Playback DesignSystem Features Cast; do
    step "Unit tests: $package"
    # Multi-product packages get an extra "<name>-Package" scheme that holds the tests.
    scheme="$package"
    if (cd "$root/Packages/$package" && xcodebuild -list 2>/dev/null | grep -q -- "$package-Package"); then
        scheme="$package-Package"
    fi
    (cd "$root/Packages/$package" && run "test-$package" xcodebuild test -scheme "$scheme" \
        -destination "$destination" -derivedDataPath "$out/dd-$package")
done

step "Generate and build the app"
xcodegen generate --spec "$root/App/iOS/project.yml" --quiet
run build-app xcodebuild build -project "$root/App/iOS/Specto.xcodeproj" -scheme Specto \
    -destination "$destination" -derivedDataPath "$out/dd-app"

step "License gate (no GPL in the shipped mpv/FFmpeg)"
"$root/scripts/check-licenses.sh" "$out/dd-app/Build/Products/Debug-iphonesimulator/Specto.app"

step "Generate and build the tvOS app (build only: no tvOS simulator runtime on CI)"
xcodegen generate --spec "$root/App/tvOS/project.yml" --quiet
run build-tv xcodebuild build -project "$root/App/tvOS/SpectoTV.xcodeproj" -scheme SpectoTV \
    -destination "generic/platform=tvOS Simulator" -derivedDataPath "$out/dd-tv"
"$root/scripts/check-licenses.sh" "$out/dd-tv/Build/Products/Debug-appletvsimulator/SpectoTV.app"

step "Build the iPhone/iPad app for Mac (Designed for iPad; unsigned, so build only)"
run build-mac xcodebuild build -project "$root/App/iOS/Specto.xcodeproj" -scheme Specto \
    -destination "platform=macOS,arch=arm64,variant=Designed for iPad" -derivedDataPath "$out/dd-mac" \
    CODE_SIGNING_ALLOWED=NO

step "App unit tests"
run test-app xcodebuild test -project "$root/App/iOS/Specto.xcodeproj" -scheme Specto \
    -only-testing:SpectoTests -destination "$destination" -derivedDataPath "$out/dd-app"

if [[ -n "${SKIP_PERF:-}" ]]; then
    echo; echo "✔ CI passed (performance tests skipped)"
    exit 0
fi

step "Performance tests (Release)"
run perf xcodebuild test -project "$root/App/iOS/Specto.xcodeproj" -scheme SpectoPerf -configuration Release \
    -destination "$destination" -derivedDataPath "$out/dd-perf"

step "Performance gates (enforced only with RELEASE_GATE=1 on a device)"
"$root/scripts/perf-gate.sh" "$out/perf.log"

echo; echo "✔ CI passed"
