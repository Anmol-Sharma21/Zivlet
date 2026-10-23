#!/usr/bin/env bash
# M5a exit row X6: the Debug app's idle CPU per island state, as a difference from a baseline (plan 12 §6). Each
# state is one launch: wait for it to settle, sample with idle-cpu.sh, quit. Baseline: "Near the drop" and no job
# (it includes the trigger host, Sparkle and the rest of the app). Then: the island hidden, collapsed and still,
# collapsed with progress input at 10 Hz (drawn at most 4 Hz, D-N7), and the stepped glyph. These are Debug-build
# numbers on whatever else the Mac is doing; the record says so.
# Usage: Scripts/notch-idle.sh      ZIVLET_IDLE_SECONDS (default 120) and ZIVLET_IDLE_SETTLE (default 10) override.
set -euo pipefail
source "$(dirname "$0")/env.sh"
APP="$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app"
SECONDS_PER_STATE=${ZIVLET_IDLE_SECONDS:-120}
SETTLE=${ZIVLET_IDLE_SETTLE:-10}
if [[ ! -d "$APP" ]]; then echo "error: $APP not found; run make app" >&2; exit 1; fi

# name | launch arguments | limit over the baseline in percent (none for the baseline)
STATES=(
    "baseline|-ZivletHUDPlacement nearDrop|"
    "hidden|-ZivletHUDPlacement notch|0.1"
    "collapsed|-ZivletHUDPlacement notch -ZivletIslandPreview collapsed|0.1"
    "progress|-ZivletHUDPlacement notch -ZivletIslandPreview progress|1"
    "indeterminate|-ZivletHUDPlacement notch -ZivletIslandPreview indeterminate|1"
)

quit_app() {
    osascript -e 'quit app "Zivlet"' >/dev/null 2>&1 || true
    sleep 2
    pkill -x Zivlet || true
}

# One launch: prints the CPU percentage of the state.
sample_state() {
    local pid
    quit_app
    # shellcheck disable=SC2086 # the arguments are words on purpose
    open -n "$APP" --args -ZivletRevealResults NO $1
    sleep "$SETTLE"
    pid=$(pgrep -nx Zivlet) || { echo "error: Zivlet did not start" >&2; return 1; }
    "$REPO_ROOT/Scripts/idle-cpu.sh" "$pid" "$SECONDS_PER_STATE"
}

trap quit_app EXIT
status=0
baseline=""
for state in "${STATES[@]}"; do
    IFS='|' read -r name arguments limit <<<"$state"
    value=$(sample_state "$arguments")
    if [[ -z "$limit" ]]; then
        baseline=$value
        echo "$name $value %"
        continue
    fi
    verdict=$(awk -v v="$value" -v b="$baseline" -v l="$limit" \
        'BEGIN { d = v - b; printf "%.3f %s", d, (d <= l ? "pass" : "FAIL") }')
    echo "$name $value % (over baseline ${verdict% *} %, limit $limit %) ${verdict#* }"
    [[ "$verdict" == *pass ]] || status=1
done
exit "$status"
