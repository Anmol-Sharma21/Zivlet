#!/usr/bin/env bash
# Watch for the unreproduced wheel-test failure (G-12, E7): runs ZivletWheelTests N times, appends the pass/fail
# counts to the GitHub job summary when there is one, keeps the log of every failing run in build/reports/wheel-watch
# and exits 1 if any run failed. ZIVLET_WATCH_COMMAND replaces the test command (script tests only).
# Usage: Scripts/flaky-watch.sh [runs]      (default 20)
set -euo pipefail
source "$(dirname "$0")/env.sh"
RUNS=${1:-20}
[[ "$RUNS" =~ ^[1-9][0-9]{0,2}$ ]] || { echo "error: runs must be 1-999, got [$RUNS]" >&2; exit 2; }
COMMAND=${ZIVLET_WATCH_COMMAND:-cd "$KIT" && swift test --filter ZivletWheelTests}
LOGS=${ZIVLET_WATCH_LOGS:-$REPO_ROOT/build/reports/wheel-watch}
mkdir -p "$LOGS"
passed=0; failed=0
for ((run = 1; run <= RUNS; run++)); do
    log=$LOGS/run-$run.log
    if bash -c "$COMMAND" >"$log" 2>&1; then
        passed=$((passed + 1)); rm -f "$log"
    else
        failed=$((failed + 1)); echo "run $run failed (log: $log)" >&2
    fi
done
summary="Wheel tests: $passed passed, $failed failed of $RUNS runs"
echo "$summary"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then echo "$summary" >>"$GITHUB_STEP_SUMMARY"; fi
((failed == 0))
