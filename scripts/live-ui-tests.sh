#!/usr/bin/env bash
# The UI tests that need a real Piped instance (playback, playlists, search, Shorts), on the
# newest iPhone Pro simulator. PIPED_URL comes from .env.local or the environment (the nightly
# workflow's secrets). Without it the tests skip themselves.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$root/.env.local" ]]; then set -a; . "$root/.env.local"; set +a; fi
[[ -n "${PIPED_URL:-}" ]] || { echo "No PIPED_URL; nothing to test against."; exit 0; }
export TEST_RUNNER_PIPED_URL="$PIPED_URL"
# The four-instance test also needs Invidious and a paired YT Zero (token in .ytzero-test-token).
[[ -n "${INVIDIOUS_URL:-}" ]] && export TEST_RUNNER_INVIDIOUS_URL="$INVIDIOUS_URL"
[[ -n "${YTZERO_URL:-}" ]] && export TEST_RUNNER_YTZERO_URL="$YTZERO_URL"
[[ -f "$root/.ytzero-test-token" ]] && export TEST_RUNNER_YTZERO_TOKEN="$(cat "$root/.ytzero-test-token")"
out="${CI_OUTPUT:-$root/build}"
mkdir -p "$out"

simulator="$(xcrun simctl list devices available -j | jq -r '
    [.devices | to_entries[] | select(.key | test("iOS")) | .value[] | select(.name | test("^iPhone [0-9]+ Pro$"))] | last | .udid')"
xcodegen generate --spec "$root/App/iOS/project.yml" --quiet
xcodebuild test -project "$root/App/iOS/Specto.xcodeproj" -scheme Specto -only-testing:SpectoUITests \
    -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "$out/dd-live-ui" \
    -resultBundlePath "$out/live-ui.xcresult" > "$out/live-ui.log" 2>&1 || status=$?
grep -a -E "Test Case .*(passed|failed)|error:" "$out/live-ui.log" | sort -u
exit "${status:-0}"
