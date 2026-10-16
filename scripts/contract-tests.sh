#!/usr/bin/env bash
# Runs the adapter contract tests against the instances in .env.local (gitignored):
#   PIPED_URL, INVIDIOUS_URL, YTZERO_URL, and for YT Zero's account tests
#   INSTANCE_USERNAME / INSTANCE_PASSWORD (a test account).
# The YT Zero token is obtained through the normal device pairing flow, approved with that
# account, and cached in .ytzero-test-token (gitignored) so reruns don't create new sessions.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "$root/.env.local" ]] || { echo "No .env.local; nothing to test against."; exit 0; }
set -a; . "$root/.env.local"; set +a

token_file="$root/.ytzero-test-token"
ytzero_token() {
    local base="$YTZERO_URL" jar
    if [[ -s "$token_file" ]]; then
        local status
        status="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $(cat "$token_file")" "$base/api/auth/status")"
        if [[ "$status" == 200 ]] && curl -s -H "Authorization: Bearer $(cat "$token_file")" "$base/api/auth/status" \
            | jq -e '.authenticated == true' >/dev/null; then
            cat "$token_file"; return
        fi
    fi
    [[ -n "${INSTANCE_USERNAME:-}" && -n "${INSTANCE_PASSWORD:-}" ]] || return 0
    jar="$(mktemp)"; trap 'rm -f "$jar"' RETURN
    # Sign in to the web UI (cookie), then approve a fresh device code with it.
    jq -n --arg u "$INSTANCE_USERNAME" --arg p "$INSTANCE_PASSWORD" '{username: $u, password: $p}' \
        | curl -s -c "$jar" -H 'Content-Type: application/json' --data @- "$base/api/auth/password/login" >/dev/null
    local code device user
    code="$(curl -s -H 'Content-Type: application/json' -d '{"device_name":"Contract tests"}' "$base/api/auth/device/code")"
    device="$(jq -r .device_code <<<"$code")"; user="$(jq -r .user_code <<<"$code")"
    jq -n --arg c "$user" '{user_code: $c}' \
        | curl -s -b "$jar" -H 'Content-Type: application/json' --data @- "$base/api/auth/device/authorize" >/dev/null
    jq -n --arg d "$device" '{device_code: $d}' \
        | curl -s -H 'Content-Type: application/json' --data @- "$base/api/auth/device/token" \
        | jq -r '.access_token // empty' | tee "$token_file"
    chmod 600 "$token_file"
}

export TEST_RUNNER_PIPED_URL="${PIPED_URL:-}"
export TEST_RUNNER_INVIDIOUS_URL="${INVIDIOUS_URL:-}"
export TEST_RUNNER_YTZERO_URL="${YTZERO_URL:-}"
export TEST_RUNNER_COMMUNITY=1
if [[ -n "${YTZERO_URL:-}" ]]; then
    export TEST_RUNNER_YTZERO_TOKEN="$(ytzero_token)"
    [[ -n "$TEST_RUNNER_YTZERO_TOKEN" ]] || echo "⚠︎ No YT Zero token; account tests will be skipped."
fi

simulator="$(xcrun simctl list devices available -j | jq -r '
    [.devices | to_entries[] | select(.key | test("iOS")) | .value[] | select(.name | test("^iPhone [0-9]+ Pro$"))] | last | .udid')"
cd "$root/Packages/Core"
xcodebuild test -scheme Core -destination "platform=iOS Simulator,id=$simulator" \
    -derivedDataPath "$root/build/dd-contract" -only-testing:CoreTests/PipedContractTests \
    -only-testing:CoreTests/InvidiousContractTests -only-testing:CoreTests/YTZeroContractTests -only-testing:CoreTests/CommunityContractTests \
    > "$root/build/contract.log" 2>&1 || status=$?
grep -E "✔ Test|✘|Test run with|skipped" "$root/build/contract.log" | sort -u
exit "${status:-0}"
