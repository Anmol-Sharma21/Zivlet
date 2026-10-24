#!/usr/bin/env bash
# Every island state on screen (plan 14 D18, OWN-UI-1): launches the Debug app once per state with the island preview
# and the screenshot-only flags (D-ND4), waits for the state's surface in the log, crops the island's frame from the
# `Island: frame x y w h` line (D-M5a-14) into build/notch-states/, and quits the app. Over a white backdrop it also
# reads the glass in a text-free box of the saved toast, the pill and the result card (Scripts/png-luminance.swift)
# and fails when white text at 0.8 would fall under 4.5:1 there. Nothing is written outside build/.
# Usage: Scripts/demo-notch-states.sh [out-dir]   (default build/notch-states; needs `make app` and Screen Recording)
#        ZIVLET_STATES_DRY_RUN=1 prints one line per capture and launches nothing.
set -euo pipefail
source "$(dirname "$0")/env.sh"
OUT=${1:-$REPO_ROOT/build/notch-states}
APP="$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app"
DRY_RUN=${ZIVLET_STATES_DRY_RUN:-0}
POLLS=40      # 0.25 s each: how long to wait for the state's surface
SETTLE=1.2    # after the surface appears: the spring settles and the content fades in
MIN_CONTRAST=4.5

# file | surface to wait for | launch arguments | contrast box (x y w h in points, from the frame's top left) or empty
CAPTURES=()
add() { CAPTURES+=("$1|$2|$3|${4:-}"); }
for state in collapsed progress indeterminate; do add "notch-$state-glass" collapsed "-ZivletIslandPreview $state"; done
for state in expanded result failure list; do add "notch-$state-glass" expanded "-ZivletIslandPreview $state"; done
for state in savedToast failureToast actionToast; do add "notch-$state-glass" toast "-ZivletIslandPreview $state"; done
for finish in solid contrast; do
    add "notch-collapsed-$finish" collapsed "-ZivletIslandPreview collapsed -ZivletIslandFinish $finish"
    add "notch-savedToast-$finish" toast "-ZivletIslandPreview savedToast -ZivletIslandFinish $finish"
    add "notch-expanded-$finish" expanded "-ZivletIslandPreview expanded -ZivletIslandFinish $finish"
    add "notch-result-$finish" expanded "-ZivletIslandPreview result -ZivletIslandFinish $finish"
done
add "pill-collapsed-glass" collapsed "-ZivletIslandPreview collapsed -ZivletIslandPill YES"
add "pill-savedToast-glass" toast "-ZivletIslandPreview savedToast -ZivletIslandPill YES"
add "pill-result-glass" expanded "-ZivletIslandPreview result -ZivletIslandPill YES"
add "pill-result-solid" expanded "-ZivletIslandPreview result -ZivletIslandPill YES -ZivletIslandFinish solid"
add "notch-result-reduce-motion" expanded "-ZivletIslandPreview result -ZivletIslandReduceMotion YES"
# Over a plain white panel: the glass at its lightest. The boxes avoid text, buttons and the glass's rim.
add "notch-savedToast-white" toast "-ZivletIslandPreview savedToast -ZivletIslandBackdrop white" "300 52 40 10"
add "pill-collapsed-white" collapsed "-ZivletIslandPreview collapsed -ZivletIslandPill YES -ZivletIslandBackdrop white" \
    "70 10 60 8"
add "pill-savedToast-white" toast "-ZivletIslandPreview savedToast -ZivletIslandPill YES -ZivletIslandBackdrop white" \
    "300 14 30 12"
add "notch-result-white" expanded "-ZivletIslandPreview result -ZivletIslandBackdrop white" "170 -11 40 4"
add "notch-result-black" expanded "-ZivletIslandPreview result -ZivletIslandBackdrop black"

if [[ "$DRY_RUN" == 1 ]]; then
    for capture in "${CAPTURES[@]}"; do
        IFS='|' read -r file surface arguments box <<<"$capture"
        echo "capture $file.png after $surface: $arguments${box:+ (contrast box $box)}"
    done
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

# The app's public refusal of a screenshot flag since $1 (App/IslandShots.swift), or nothing.
refusals() {
    /usr/bin/log show --start "$1" --style compact \
        --predicate 'subsystem == "app.zivlet.Zivlet" AND eventMessage BEGINSWITH "Island screenshot flags refused"' |
        grep -o 'refused: .*' || true
}

island_lines() {
    /usr/bin/log show --start "$1" --style compact \
        --predicate 'subsystem == "app.zivlet.Zivlet" AND eventMessage BEGINSWITH "Island:"' | grep -o 'Island: .*' || true
}

# White at 0.8 over a surface of linear luminance $1, composited in sRGB as NotchInk does.
contrast() {
    awk -v l="$1" 'function enc(v) { return v <= 0.0031308 ? v * 12.92 : 1.055 * v ^ (1 / 2.4) - 0.055 }
        function dec(v) { return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
        BEGIN { t = dec(0.8 + enc(l) * 0.2); printf "%.2f", (t + 0.05) / (l + 0.05) }'
}

# Captures one state; prints its frame, or fails when the surface or the frame never shows.
capture() {
    local file=$1 surface=$2 arguments=$3 start lines frame refused
    quit_app
    start=$(date '+%Y-%m-%d %H:%M:%S')
    # shellcheck disable=SC2086 # the arguments are words on purpose
    open -n "$APP" --args -ZivletRevealResults NO -ZivletHUDPlacement notch $arguments
    for _ in $(seq 1 "$POLLS"); do
        lines=$(island_lines "$start")
        grep -q "^Island: $surface\$" <<<"$lines" && break
        sleep 0.25
    done
    grep -q "^Island: $surface\$" <<<"$lines" || { echo "error: $file: no '$surface' surface" >&2; return 1; }
    # A refused flag resets every flag: the picture would show the wrong finish or display kind.
    refused=$(refusals "$start")
    [[ -z "$refused" ]] || { echo "error: $file: screenshot flags $refused" >&2; return 1; }
    sleep "$SETTLE"
    frame=$(sed -n "/^Island: $surface\$/,\$p" <<<"$(island_lines "$start")" | grep -m1 '^Island: frame' |
        sed 's/^Island: frame //')
    [[ -n "$frame" ]] || { echo "error: $file: no frame line" >&2; return 1; }
    read -r x y w h <<<"$frame"
    screencapture -x -R"$x,$y,$w,$h" "$OUT/$file.png" || { echo "error: $file: screencapture failed" >&2; return 1; }
    echo "$frame"
}

status=0
for entry in "${CAPTURES[@]}"; do
    IFS='|' read -r file surface arguments box <<<"$entry"
    if ! frame=$(capture "$file" "$surface" "$arguments"); then status=1; continue; fi
    echo "$file.png ($frame)"
    [[ -n "$box" ]] || continue
    read -r _ _ w h <<<"$frame"
    read -r bx by bw bh <<<"$box"
    ((by < 0)) && by=$((h + by))  # a negative y counts from the bottom edge
    luminance=$(xcrun swift "$REPO_ROOT/Scripts/png-luminance.swift" "$OUT/$file.png" "$bx" "$by" "$bw" "$bh" "$w")
    ratio=$(contrast "$luminance")
    verdict=$(awk -v r="$ratio" -v m="$MIN_CONTRAST" 'BEGIN { print (r >= m ? "pass" : "FAIL") }')
    echo "contrast $file: glass luminance $luminance, white 0.8 text $ratio:1 (need $MIN_CONTRAST) $verdict"
    [[ "$verdict" == pass ]] || status=1
done
exit "$status"
