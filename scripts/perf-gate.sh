#!/usr/bin/env bash
# Checks the performance gates (CLAUDE.md) against an xcodebuild test log.
#   scripts/perf-gate.sh build/ci/perf.log            report only (simulators: trend, not the gate)
#   RELEASE_GATE=1 scripts/perf-gate.sh <device log>  fail when a gate is missed (release builds,
#                                                      measured on a ProMotion device)
set -euo pipefail

log="${1:?usage: perf-gate.sh <xcodebuild test log>}"
enforce="${RELEASE_GATE:-0}"
failures=0

# metric name as XCTest prints it | gate | unit multiplier to compare in the gate's unit
gates=(
    "Duration (launch.firstFeedFrame), s|0.400|1|s|Cold launch to first rendered feed"
    "Duration (playback.tapToFirstFrame), s|0.300|1|s|Tap to first video frame (warm)"
    "Hitch Time Ratio (Scroll_Deceleration), ms per s|5.0|1|ms/s|Scroll hitch ratio"
)

for gate in "${gates[@]}"; do
    IFS='|' read -r metric limit _ unit label <<<"$gate"
    value="$( (grep -F "measured [$metric]" "$log" || true) | sed -E 's/.*average: ([0-9.]+).*/\1/' | tail -1)"
    if [[ -z "$value" ]]; then
        echo "· $label: not measured here"
        continue
    fi
    if awk -v v="$value" -v l="$limit" 'BEGIN { exit !(v <= l) }'; then
        echo "✔ $label: $value $unit (gate $limit)"
    else
        echo "✘ $label: $value $unit (gate $limit)"
        failures=$((failures + 1))
    fi
done

if (( failures > 0 )); then
    if [[ "$enforce" == 1 ]]; then
        echo "Performance gate failed ($failures)."
        exit 1
    fi
    echo "($failures over the gate; not enforced here — simulator numbers are a trend only.)"
fi
