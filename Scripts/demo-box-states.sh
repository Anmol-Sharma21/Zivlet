#!/usr/bin/env bash
# Every Drop Box and notch tray state on screen (19c §4, OWN-UI-1, plan 16 E3): launches the Debug app once per state
# with -ZivletBoxPreview or -ZivletTrayPreview and the island's screenshot-only flags (D-M5b-20), waits for the
# state's `Box: <state>` or `Island: <surface>` line, crops the frame from the `Box: frame x y w h` or
# `Island: frame x y w h` line after it into build/box-states/, and quits the app. The hidden panel and the resting
# tray (an invisible sensor) are checked in the log only. Over a white backdrop it reads the glass in a text-free box
# of the panel, the docked tab and the tray drop target (Scripts/png-luminance.swift) and fails when white text at
# 0.8 would fall under 4.5:1 there. With the screen locked it captures nothing and says "skipped: screen locked".
# Nothing is written outside the output folder.
# Usage: Scripts/demo-box-states.sh [out-dir]   (default build/box-states; needs `make app` and Screen Recording)
#        ZIVLET_STATES_DRY_RUN=1 prints one line per capture and launches nothing; ZIVLET_STATES_ONLY=a,b runs only
#        the named captures (a rerun). ZIVLET_STATES_APP, ZIVLET_STATES_LOG (replaces /usr/bin/log),
#        ZIVLET_STATES_POLLS and ZIVLET_STATES_SETTLE are for the script test.
set -euo pipefail
source "$(dirname "$0")/env.sh"
OUT=${1:-$REPO_ROOT/build/box-states}
APP=${ZIVLET_STATES_APP:-$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app}
LOG_TOOL=${ZIVLET_STATES_LOG:-/usr/bin/log}
DRY_RUN=${ZIVLET_STATES_DRY_RUN:-0}
ONLY=${ZIVLET_STATES_ONLY:-}
POLLS=${ZIVLET_STATES_POLLS:-40}     # 0.25 s each: how long to wait for the state's line
SETTLE=${ZIVLET_STATES_SETTLE:-1.2}  # after the line: the panel or the spring settles and the content fades in
MIN_CONTRAST=4.5
LOG_ONLY=-

# file (or - for a log line only) | Box or Island | state or surface to wait for | launch arguments | contrast box
# (x y w h in points from the frame's top left; a negative y counts from the bottom edge) or empty
CAPTURES=()
add() { CAPTURES+=("$1|$2|$3|$4|${5:-}"); }
finish_flag() { [[ "$1" == glass ]] && echo "" || echo " -ZivletIslandFinish $1"; }
add "$LOG_ONLY" Box hidden "-ZivletBoxPreview hidden"
for state in docked collapsed grid list selection dropTarget busy attention confirmTrash confirmClear empty \
    confirmEmpty storageWarning; do
    for finish in glass solid contrast; do
        add "box-$state-$finish" Box "$state" "-ZivletBoxPreview $state$(finish_flag "$finish")"
    done
done
# The tray's states and the island surface each one shows: the compact view is the tray's expanded content.
tray_surface() { case "$1" in compact) echo expanded ;; *) echo "$1" ;; esac; }
for state in dropTarget toast compact; do
    for finish in glass solid contrast; do
        add "tray-$state-$finish" Island "$(tray_surface "$state")" "-ZivletTrayPreview $state$(finish_flag "$finish")"
        add "pill-tray-$state-$finish" Island "$(tray_surface "$state")" \
            "-ZivletTrayPreview $state -ZivletIslandPill YES$(finish_flag "$finish")"
    done
done
add "$LOG_ONLY" Island sensor "-ZivletTrayPreview sensor"
add "box-grid-reduce-motion" Box grid "-ZivletBoxPreview grid -ZivletIslandReduceMotion YES"
add "tray-dropTarget-reduce-motion" Island dropTarget "-ZivletTrayPreview dropTarget -ZivletIslandReduceMotion YES"
# Over a plain white panel: the glass at its lightest. The boxes avoid text, symbols, cells and the glass's rim.
add "box-grid-white" Box grid "-ZivletBoxPreview grid -ZivletIslandBackdrop white" "250 -36 80 10"
add "box-docked-white" Box docked "-ZivletBoxPreview docked -ZivletIslandBackdrop white" "10 6 12 8"
add "tray-dropTarget-white" Island dropTarget "-ZivletTrayPreview dropTarget -ZivletIslandBackdrop white" \
    "150 -14 60 6"
add "pill-tray-dropTarget-white" Island dropTarget \
    "-ZivletTrayPreview dropTarget -ZivletIslandPill YES -ZivletIslandBackdrop white" "150 -14 60 6"

if [[ -n "$ONLY" ]]; then
    for name in ${ONLY//,/ }; do
        printf '%s\n' "${CAPTURES[@]}" | grep -q "^$name|" || { echo "error: no capture named $name" >&2; exit 2; }
    done
fi
selected() { [[ -z "$ONLY" || ",$ONLY," == *",$1,"* ]]; }

if [[ "$DRY_RUN" == 1 ]]; then
    for capture in "${CAPTURES[@]}"; do
        IFS='|' read -r file source state arguments box <<<"$capture"
        if [[ "$file" == "$LOG_ONLY" ]]; then
            echo "log only after $source: $state: $arguments"
        else
            echo "capture $file.png after $source: $state: $arguments${box:+ (contrast box $box)}"
        fi
    done
    exit 0
fi
if ioreg -n Root -d1 -a | grep -A1 -i 'CGSSessionScreenIsLocked' | grep -q '<true/>'; then
    echo "skipped: screen locked (nothing captured)"
    exit 0
fi
if [[ ! -d "$APP" ]]; then echo "error: $APP not found; run make app" >&2; exit 1; fi
mkdir -p "$OUT"
quit_app() {
    osascript -e 'quit app "Zivlet"' >/dev/null 2>&1 || true
    sleep 1
    pkill -x Zivlet || true
}
trap quit_app EXIT

# The app's `Box:` and `Island:` lines and its public refusals of a flag (App/BoxShots.swift, App/IslandShots.swift)
# since $1.
app_lines() {
    "$LOG_TOOL" show --start "$1" --style compact --predicate 'subsystem == "app.zivlet.Zivlet"' |
        grep -oE '(Box|Island): .*|(Box|Island) screenshot flags refused.*' || true
}

# White at 0.8 over a surface of linear luminance $1, composited in sRGB as the island's ink does.
contrast() {
    awk -v l="$1" 'function enc(v) { return v <= 0.0031308 ? v * 12.92 : 1.055 * v ^ (1 / 2.4) - 0.055 }
        function dec(v) { return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
        BEGIN { t = dec(0.8 + enc(l) * 0.2); printf "%.2f", (t + 0.05) / (l + 0.05) }'
}

# Launches one state and waits for its line; prints the log lines, or fails when the line never shows or a flag was
# refused (a refusal resets every flag, so the picture would show the wrong state or finish).
launch() {
    local source=$1 state=$2 arguments=$3 start lines refused
    quit_app
    start=$(date '+%Y-%m-%d %H:%M:%S')
    # shellcheck disable=SC2086 # the arguments are words on purpose
    open -n "$APP" --args -ZivletRevealResults NO -ZivletHUDPlacement notch $arguments
    for _ in $(seq 1 "$POLLS"); do
        lines=$(app_lines "$start")
        grep -q "^$source: $state\$" <<<"$lines" && break
        sleep 0.25
    done
    refused=$(grep 'screenshot flags refused' <<<"$lines" || true)
    [[ -z "$refused" ]] || { echo "error: $refused" >&2; return 1; }
    grep -q "^$source: $state\$" <<<"$lines" || { echo "error: no '$source: $state' line" >&2; return 1; }
    sleep "$SETTLE"
    app_lines "$start"
}

# Captures one state; prints its frame.
capture() {
    local file=$1 source=$2 state=$3 arguments=$4 lines frame x y w h
    lines=$(launch "$source" "$state" "$arguments") || { echo "error: $file failed" >&2; return 1; }
    frame=$(sed -n "/^$source: $state\$/,\$p" <<<"$lines" | grep -m1 "^$source: frame" | sed "s/^$source: frame //")
    [[ -n "$frame" ]] || { echo "error: $file: no frame line" >&2; return 1; }
    read -r x y w h <<<"$frame"
    screencapture -x -R"$x,$y,$w,$h" "$OUT/$file.png" || { echo "error: $file: screencapture failed" >&2; return 1; }
    echo "$frame"
}

# Reads the contrast box of a saved capture; fails under the minimum.
measure() {
    local file=$1 frame=$2 box=$3 w h bx by bw bh luminance ratio verdict
    read -r _ _ w h <<<"$frame"
    read -r bx by bw bh <<<"$box"
    ((by < 0)) && by=$((h + by))
    luminance=$(xcrun swift "$REPO_ROOT/Scripts/png-luminance.swift" "$OUT/$file.png" "$bx" "$by" "$bw" "$bh" "$w")
    ratio=$(contrast "$luminance")
    verdict=$(awk -v r="$ratio" -v m="$MIN_CONTRAST" 'BEGIN { print (r >= m ? "pass" : "FAIL") }')
    echo "contrast $file: glass luminance $luminance, white 0.8 text $ratio:1 (need $MIN_CONTRAST) $verdict"
    [[ "$verdict" == pass ]]
}

status=0
for entry in "${CAPTURES[@]}"; do
    IFS='|' read -r file source state arguments box <<<"$entry"
    selected "$file" || continue
    if [[ "$file" == "$LOG_ONLY" ]]; then
        if launch "$source" "$state" "$arguments" >/dev/null; then echo "log: $source: $state"; else status=1; fi
        continue
    fi
    if ! frame=$(capture "$file" "$source" "$state" "$arguments"); then status=1; continue; fi
    echo "$file.png ($frame)"
    [[ -z "$box" ]] || measure "$file" "$frame" "$box" || status=1
done
exit "$status"
