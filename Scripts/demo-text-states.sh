#!/usr/bin/env bash
# Exit row Z9 (plan 18d D15, OWN-UI-1): every Copy Text state on screen from the Debug app, one launch per state, into
# build/text-states/. The island's toast and card are cropped from the `Island: frame` line (as demo-notch-states.sh
# does); the card near the drop and Show All from the app's `Text shot: frame` line; the Settings row from the General
# pane's window. Over the island's card it reads the glass in a text-free box (Scripts/png-luminance.swift) and fails
# when white text at 0.8 would fall under 4.5:1 there. With the screen locked it captures nothing and says
# "skipped: screen locked". Nothing is written outside the output folder.
# Usage: Scripts/demo-text-states.sh [out-dir]   (default build/text-states; needs `make app` and Screen Recording)
#        ZIVLET_STATES_DRY_RUN=1 prints one line per capture and launches nothing.
set -euo pipefail
source "$(dirname "$0")/env.sh"
OUT=${1:-$REPO_ROOT/build/text-states}
APP="$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app"
DRY_RUN=${ZIVLET_STATES_DRY_RUN:-0}
POLLS=40     # 0.25 s each
SETTLE=1.2   # after the surface appears
MIN_CONTRAST=4.5

# file | log source | state line to wait for | launch arguments | contrast box (x y w h) or empty
CAPTURES=(
    "text-notchToast|Island|toast|-ZivletHUDPlacement notch -ZivletTextStates notchToast|"
    "text-notchCard|Island|expanded|-ZivletHUDPlacement notch -ZivletTextStates notchCard|20 -14 30 6"
    "text-hudCard|Text shot|hudCard|-ZivletHUDPlacement nearDrop -ZivletTextStates hudCard|"
    "text-showAll|Text shot|showAll|-ZivletTextStates showAll|"
)

if [[ "$DRY_RUN" == 1 ]]; then
    for capture in "${CAPTURES[@]}"; do
        IFS='|' read -r file _ state arguments box <<<"$capture"
        echo "capture $file.png: -ZivletTextStates ${arguments##*-ZivletTextStates } after $state${box:+ (contrast box $box)}"
    done
    echo "capture text-setting.png: -ZivletDemoSettings general (window)"
    exit 0
fi
locked=${ZIVLET_SCREEN_LOCKED:-}
if [[ -z "$locked" ]] && ioreg -n Root -d1 -a | grep -A1 -i 'CGSSessionScreenIsLocked' | grep -q '<true/>'; then
    locked=1
fi
if [[ "$locked" == 1 ]]; then
    echo "skipped: screen locked (nothing captured)"
    exit 0
fi
[[ -d "$APP" ]] || { echo "error: $APP not found; run make app" >&2; exit 1; }
mkdir -p "$OUT"
quit_app() {
    osascript -e 'quit app "Zivlet"' >/dev/null 2>&1 || true
    sleep 1
}
trap quit_app EXIT

lines() {
    /usr/bin/log show --start "$1" --style compact \
        --predicate "subsystem == \"app.zivlet.Zivlet\" AND eventMessage BEGINSWITH \"$2:\"" | grep -o "$2: .*" || true
}

contrast() {
    awk -v l="$1" 'function enc(v) { return v <= 0.0031308 ? v * 12.92 : 1.055 * v ^ (1 / 2.4) - 0.055 }
        function dec(v) { return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
        BEGIN { t = dec(0.8 + enc(l) * 0.2); printf "%.2f", (t + 0.05) / (l + 0.05) }'
}

# Captures one state; prints its frame, or fails when the state or its frame never shows.
capture() {
    local file=$1 source=$2 state=$3 arguments=$4 start found frame
    quit_app
    start=$(date '+%Y-%m-%d %H:%M:%S')
    # shellcheck disable=SC2086 # the arguments are words on purpose
    open -n "$APP" --args -ZivletRevealResults NO $arguments
    for _ in $(seq 1 "$POLLS"); do
        found=$(lines "$start" "$source")
        grep -q "^$source: $state\$" <<<"$found" && break
        sleep 0.25
    done
    grep -q "^$source: $state\$" <<<"$found" || { echo "error: $file: no '$source: $state' line" >&2; return 1; }
    sleep "$SETTLE"
    frame=$(sed -n "/^$source: $state\$/,\$p" <<<"$(lines "$start" "$source")" | grep -m1 "^$source: frame" |
        sed "s/^$source: frame //")
    [[ -n "$frame" ]] || { echo "error: $file: no frame line" >&2; return 1; }
    read -r x y w h <<<"$frame"
    screencapture -x -R"$x,$y,$w,$h" "$OUT/$file.png" || { echo "error: $file: screencapture failed" >&2; return 1; }
    echo "$frame"
}

check_contrast() {
    local file=$1 frame=$2 box=$3 w h bx by bw bh luminance ratio
    read -r _ _ w h <<<"$frame"
    read -r bx by bw bh <<<"$box"
    ((by < 0)) && by=$((h + by))
    luminance=$(xcrun swift "$REPO_ROOT/Scripts/png-luminance.swift" "$OUT/$file.png" "$bx" "$by" "$bw" "$bh" "$w")
    ratio=$(contrast "$luminance")
    echo "contrast $file: glass luminance $luminance, white 0.8 text $ratio:1 (need $MIN_CONTRAST)"
    awk -v r="$ratio" -v m="$MIN_CONTRAST" 'BEGIN { exit !(r >= m) }'
}

capture_setting() {
    local start window
    quit_app
    start=$(date '+%Y-%m-%d %H:%M:%S')
    open -n "$APP" --args -ZivletDemoSettings general
    for _ in $(seq 1 "$POLLS"); do
        window=$(lines "$start" "Settings shown" | grep -o 'general window [0-9]*' | tail -1 | awk '{print $NF}')
        [[ -n "$window" && "$window" != 0 ]] && break
        sleep 0.25
    done
    [[ -n "$window" && "$window" != 0 ]] || { echo "error: text-setting: no Settings window" >&2; return 1; }
    sleep "$SETTLE"
    screencapture -x -o -l "$window" "$OUT/text-setting.png"
}

status=0
for entry in "${CAPTURES[@]}"; do
    IFS='|' read -r file source state arguments box <<<"$entry"
    if ! frame=$(capture "$file" "$source" "$state" "$arguments"); then
        status=1
        continue
    fi
    echo "$file.png ($frame)"
    if [[ -n "$box" ]] && ! check_contrast "$file" "$frame" "$box"; then status=1; fi
done
if capture_setting; then echo "text-setting.png"; else status=1; fi
exit "$status"
