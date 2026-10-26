#!/usr/bin/env bash
# M5b exit row Y8: the Debug app's idle CPU with the Drop Box and the notch tray, as a difference from a baseline
# (plan 16 E5), in the pattern of notch-idle.sh. Each state is one launch: wait for it to settle, sample with
# idle-cpu.sh, quit. Baseline: the island at the notch, no box shown and nothing at the notch. Then the panel shown
# and still (grid, made-up items), the tray at rest on its invisible sensor over a made-up box, and the real armed
# path: -ZivletBoxDemo over four small files in a scratch folder, so the tray's driver, its live-sample hook and the
# zone watch run as in use (the preview states skip them). Every launch uses a store in a temporary folder
# (D-M5b-20), never the person's boxes.json. WindowServer's CPU over the same
# window is printed beside each row, for information; it has no limit. These are Debug numbers taken on whatever
# else the Mac is doing; the record says so. G-M5a-1's fast-progress row is not part of this script.
# Usage: Scripts/box-idle.sh      ZIVLET_IDLE_SECONDS (default 120) and ZIVLET_IDLE_SETTLE (default 10) override;
#        ZIVLET_IDLE_DRY_RUN=1 prints the plan without launching anything. ZIVLET_IDLE_APP and ZIVLET_IDLE_SAMPLER
#        (replaces Scripts/idle-cpu.sh) are for the script test.
set -euo pipefail
source "$(dirname "$0")/env.sh"
SECONDS_PER_STATE=${ZIVLET_IDLE_SECONDS:-120}
SETTLE=${ZIVLET_IDLE_SETTLE:-10}
DRY_RUN=${ZIVLET_IDLE_DRY_RUN:-0}
APP=${ZIVLET_IDLE_APP:-$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app}
SAMPLER=${ZIVLET_IDLE_SAMPLER:-$REPO_ROOT/Scripts/idle-cpu.sh}

# name | launch arguments | limit over the baseline in percent (none for the baseline)
STATES=(
    "baseline|-ZivletHUDPlacement notch -ZivletBoxPreview hidden|"
    "panel-still|-ZivletHUDPlacement notch -ZivletBoxPreview grid|0.1"
    "tray-sensor|-ZivletHUDPlacement notch -ZivletTrayPreview sensor|0.1"
    "box-armed|-ZivletHUDPlacement notch -ZivletBoxDemo @DEMO@|0.1"
)
DEMO_FILES=4

if [[ "$DRY_RUN" == 1 ]]; then
    echo "debug app $APP"
    echo "debug $SECONDS_PER_STATE s each after $SETTLE s; also samples WindowServer (information, no limit)"
    for state in "${STATES[@]}"; do
        IFS='|' read -r name arguments limit <<<"$state"
        echo "debug state $name ${limit:-baseline} $arguments"
    done
    exit 0
fi
if [[ ! -d "$APP" ]]; then echo "error: $APP not found; run make app" >&2; exit 1; fi

# The armed state's box: a scratch folder of this script's own, removed at exit, and nothing else.
DEMO=$(mktemp -d "${TMPDIR:-/tmp}/zivlet-box-idle.XXXXXX")
for n in $(seq 1 "$DEMO_FILES"); do printf 'Zivlet idle %s\n' "$n" >"$DEMO/idle-$n.txt"; done
drop_demo_dir() {
    [[ "$(basename "$DEMO")" == zivlet-box-idle.* ]] || return 0
    rm -r -f "$DEMO"
}

quit_app() {
    osascript -e 'quit app "Zivlet"' >/dev/null 2>&1 || true
    sleep 2
    pkill -x Zivlet || true
}

# One launch: prints the app's CPU percentage of the state, then WindowServer's over the same window (or "n/a").
sample_state() {
    local pid server app server_file
    quit_app
    # shellcheck disable=SC2086 # the arguments are words on purpose
    open -n "$APP" --args -ZivletRevealResults NO $1
    sleep "$SETTLE"
    pid=$(pgrep -nx Zivlet) || { echo "error: Zivlet did not start" >&2; return 1; }
    server_file=$(mktemp)
    if server=$(pgrep -x WindowServer); then
        "$SAMPLER" "$server" "$SECONDS_PER_STATE" >"$server_file" 2>/dev/null &
    fi
    app=$("$SAMPLER" "$pid" "$SECONDS_PER_STATE") || { rm -f "$server_file"; return 1; }
    wait || true
    echo "$app $(cat "$server_file" 2>/dev/null || true)"
    rm -f "$server_file"
}

trap 'quit_app; drop_demo_dir' EXIT
echo "debug load average at start: $(sysctl -n vm.loadavg)"
status=0
baseline=""
for state in "${STATES[@]}"; do
    IFS='|' read -r name arguments limit <<<"$state"
    result=$(sample_state "${arguments//@DEMO@/$DEMO}") || result=""
    read -r value server <<<"$result"
    server="WindowServer ${server:-n/a} %"
    if [[ -z "$limit" ]]; then
        [[ -n "$value" ]] || { echo "error: no baseline sample; nothing to compare against" >&2; exit 1; }
        baseline=$value
        echo "debug $name $value % ($server)"
        continue
    fi
    if [[ -z "$value" ]]; then
        echo "debug $name no sample FAIL"
        status=1
        continue
    fi
    verdict=$(awk -v v="$value" -v b="$baseline" -v l="$limit" \
        'BEGIN { d = v - b; printf "%.3f %s", d, (d <= l + 1e-9 ? "pass" : "FAIL") }')
    echo "debug $name $value % (over baseline ${verdict% *} %, limit $limit %) ${verdict#* } ($server)"
    [[ "$verdict" == *pass ]] || status=1
done
echo "debug load average at end: $(sysctl -n vm.loadavg)"
exit "$status"
