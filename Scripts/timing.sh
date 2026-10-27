#!/usr/bin/env bash
# Judges the real-time budgets in ZivletTimingTests only on a quiet Mac (D-M7-3). Unit tests never judge wall time;
# these tests do, so this script first waits (poll every 15 s, at most 10 min) for the 1-minute load average to fall
# to the limit, builds, waits again, then runs the suites with ZIVLET_TIMING=1. It prints the load before and after
# and every `timing:` line the tests wrote. The limit is half the performance cores (3.0 on a 6-P-core Mac);
# ZIVLET_TIMING_MAX_LOAD may lower it, and a value above the P-core count is refused.
# Exit: 0 judged and passed, 1 judged and failed, 2 bad arguments, 3 not judged (too busy; a failure while the load
# rose above the limit during the run is not judged either). Exit rows report 3 as skip, which is not a pass.
# ZIVLET_LOADAVG, ZIVLET_SWIFT, ZIVLET_PCORES, ZIVLET_TIMING_WAIT, ZIVLET_TIMING_POLL and ZIVLET_TIMING_DIR replace
# the load source, swift, the core count, the wait, the poll and the log folder (script tests only).
# Usage: Scripts/timing.sh [Suite]      e.g. Scripts/timing.sh NotchHUDTiming
set -euo pipefail
source "$(dirname "$0")/env.sh"
SUITE=${1:-}
LOADAVG=${ZIVLET_LOADAVG:-sysctl -n vm.loadavg}
SWIFT=${ZIVLET_SWIFT:-swift}
PCORES=${ZIVLET_PCORES:-$(sysctl -n hw.perflevel0.physicalcpu)}
WAIT=${ZIVLET_TIMING_WAIT:-600}
POLL=${ZIVLET_TIMING_POLL:-15}
LOG_DIR=${ZIVLET_TIMING_DIR:-$REPO_ROOT/build/timing}
NOT_JUDGED=3

die() { echo "error: $*" >&2; exit 2; }
is_number() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; }
above() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }
load_1m() { $LOADAVG | awk '{ print $2 }'; }

[[ -z "$SUITE" || "$SUITE" =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || die "suite must be a Swift name, got [$SUITE]"
[[ "$PCORES" =~ ^[1-9][0-9]*$ ]] || die "P-core count must be a positive integer, got [$PCORES]"
for value in "$WAIT" "$POLL"; do [[ "$value" =~ ^[0-9]+$ ]] || die "wait and poll are whole seconds, got [$value]"; done
LIMIT=$(awk -v p="$PCORES" 'BEGIN { printf "%.1f", p / 2 }')
if [[ -n "${ZIVLET_TIMING_MAX_LOAD:-}" ]]; then
    is_number "$ZIVLET_TIMING_MAX_LOAD" || die "ZIVLET_TIMING_MAX_LOAD must be a number, got [$ZIVLET_TIMING_MAX_LOAD]"
    if above "$ZIVLET_TIMING_MAX_LOAD" "$PCORES"; then
        die "ZIVLET_TIMING_MAX_LOAD $ZIVLET_TIMING_MAX_LOAD is above the $PCORES performance cores; it may only lower the limit"
    fi
    LIMIT=$(awk -v l="$ZIVLET_TIMING_MAX_LOAD" 'BEGIN { printf "%.1f", l }')
fi

# Waits until the 1-minute load is at or under the limit and prints it; after WAIT seconds prints why it is not
# judged and returns NOT_JUDGED.
wait_for_quiet() {
    local load waited=0
    load=$(load_1m)
    while above "$load" "$LIMIT"; do
        if ((waited >= WAIT)); then
            echo "timing: not judged (load 1m $load > $LIMIT)"
            return "$NOT_JUDGED"
        fi
        echo "timing: waiting, load 1m $load > $LIMIT" >&2
        sleep "$POLL"
        waited=$((waited + (POLL > 0 ? POLL : 1)))
        load=$(load_1m)
    done
    echo "$load"
}

mkdir -p "$LOG_DIR"
LOG=$LOG_DIR/timing.log
FILTER="ZivletTimingTests${SUITE:+.$SUITE}"
if ! BEFORE=$(wait_for_quiet); then echo "$BEFORE"; exit "$NOT_JUDGED"; fi
(cd "$KIT" && "$SWIFT" build --build-tests >"$LOG_DIR/build.log" 2>&1) ||
    { tail -n 40 "$LOG_DIR/build.log" >&2; die "the timing tests did not build"; }
# The build loads the Mac too: wait again before anything is measured.
if ! BEFORE=$(wait_for_quiet); then echo "$BEFORE"; exit "$NOT_JUDGED"; fi
status=0
(cd "$KIT" && ZIVLET_TIMING=1 "$SWIFT" test --skip-build --filter "$FILTER" >"$LOG" 2>&1) || status=$?
AFTER=$(load_1m)
grep -E '^timing: |✘' "$LOG" || true
echo "timing: load before $BEFORE, after $AFTER, limit $LIMIT (log: $LOG)"
if ((status != 0)) && above "$AFTER" "$LIMIT"; then
    echo "timing: not judged (load rose to $AFTER > $LIMIT during the run)"
    exit "$NOT_JUDGED"
fi
((status == 0)) || { echo "timing: judged at load $BEFORE: a budget was missed" >&2; exit 1; }
echo "timing: judged at load $BEFORE: every budget met"
