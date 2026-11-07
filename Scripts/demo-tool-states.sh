#!/usr/bin/env bash
# Exit row V11 (plan 20g F3, OWN-UI-1): every new M7 state on screen from the Debug app, one launch per state, into
# build/tool-states/: the ten password sheet states (-ZivletPasswordStates; the wrong password, the restrictions, the
# owner password shown once, the disabled reason among them) and Read QR's results window (-ZivletToolStates
# qrResults), each in glass and in both fallbacks (-ZivletIslandFinish solid|contrast); the lock, unlock, change and
# wrong-password cards near the drop (glass) and on the island (all three finishes). Each surface is captured by its
# window number (`screencapture -l`, from the window line the app logs after the state's line), so a capture never
# holds another app's window; the glass is therefore drawn without what lies behind it. Over each tool window and
# island card it reads a text-free box (Scripts/png-luminance.swift) and fails when white text at 0.8 would fall
# under 4.5:1 there (the sheet's words, the wrong password's line included, are white or white at 0.8; red is only
# the field's outline). With the screen locked it captures nothing and says "skipped: screen locked".
# Nothing is written outside the output folder; only the app this script launched is quit.
# Usage: Scripts/demo-tool-states.sh [out-dir]   (default build/tool-states; needs `make app`)
#        ZIVLET_STATES_DRY_RUN=1 lists the captures; ZIVLET_STATES_ONLY=a,b runs only those (a rerun).
#        ZIVLET_DEMO_APP, ZIVLET_DEMO_LOG (replaces /usr/bin/log), ZIVLET_LUMINANCE, ZIVLET_STATES_POLLS and
#        ZIVLET_STATES_SETTLE are for the script test.
set -euo pipefail
source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/app-process.sh"
source "$(dirname "$0")/demo-lib.sh"
OUT=${1:-$REPO_ROOT/build/tool-states}
LOG_TOOL=${ZIVLET_DEMO_LOG:-/usr/bin/log}
LUMINANCE=${ZIVLET_LUMINANCE:-xcrun swift $REPO_ROOT/Scripts/png-luminance.swift}
DRY_RUN=${ZIVLET_STATES_DRY_RUN:-0}
ONLY=${ZIVLET_STATES_ONLY:-}
POLLS=${ZIVLET_STATES_POLLS:-40}     # 0.25 s each
SETTLE=${ZIVLET_STATES_SETTLE:-1.2}  # after the frame line
MIN_CONTRAST=4.5
# Text-free boxes (x y w h in points from the frame's top left; a negative y counts from the bottom edge): the tool
# window's lower left corner inside its padding, and the island card's lower edge (as demo-text-states.sh).
WINDOW_BOX="14 -16 60 6"
ISLAND_BOX="20 -14 30 6"

# file | log source | state line prefix | launch arguments | contrast box (window, island or empty)
CAPTURES=()
add() { CAPTURES+=("$1|$2|$3|$4|${5:-}"); }
finish_flag() { [[ "$1" == glass ]] && echo "" || echo " -ZivletIslandFinish $1"; }
for finish in glass solid contrast; do
    for state in lockEmpty lockMismatch lockSuggested lockNonASCII lockRestricted unlockWrong unlockBatch retry change \
        ownerNeeded; do
        add "password-$state-$finish" "Password shot" "$state window" \
            "-ZivletPasswordStates $state$(finish_flag "$finish")" window
    done
    add "qr-results-$finish" "Tool shot" qrResults "-ZivletToolStates qrResults$(finish_flag "$finish")" window
    for card in lockCard unlockCard changeCard wrongCard; do
        add "island-$card-$finish" "Tool shot" "$card" \
            "-ZivletHUDPlacement notch -ZivletToolStates $card$(finish_flag "$finish")" island
    done
done
for card in lockCard unlockCard changeCard wrongCard; do
    add "near-$card-glass" "Tool shot" "$card" "-ZivletHUDPlacement nearDrop -ZivletToolStates $card"
done

if [[ -n "$ONLY" ]]; then
    for name in ${ONLY//,/ }; do
        printf '%s\n' "${CAPTURES[@]}" | grep -q "^$name|" || { echo "error: no capture named $name" >&2; exit 2; }
    done
fi
selected() { [[ -z "$ONLY" || ",$ONLY," == *",$1,"* ]]; }

if [[ "$DRY_RUN" == 1 ]]; then
    for entry in "${CAPTURES[@]}"; do
        IFS='|' read -r file source state arguments kind <<<"$entry"
        echo "capture $file.png after $source: $state: $arguments${kind:+ (contrast $kind)}"
    done
    exit 0
fi
if demo_screen_locked; then
    echo "skipped: screen locked (nothing captured)"
    exit 0
fi
[[ -d "$DEMO_APP" ]] || { echo "error: $DEMO_APP not found; run make app" >&2; exit 1; }
mkdir -p "$OUT"
quit_app() {
    quit_launched
    sleep 1
}
trap quit_app EXIT

app_lines() {
    "$LOG_TOOL" show --start "$1" --style compact --predicate 'subsystem == "app.zivlet.Zivlet"' |
        grep -oE '(Password shot|Tool shot): .*|Island screenshot flags refused.*' || true
}

# White at 0.8 over a surface of linear luminance $1, composited in sRGB.
contrast() {
    awk -v l="$1" 'function enc(v) { return v <= 0.0031308 ? v * 12.92 : 1.055 * v ^ (1 / 2.4) - 0.055 }
        function dec(v) { return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
        BEGIN { t = dec(0.8 + enc(l) * 0.2); printf "%.2f", (t + 0.05) / (l + 0.05) }'
}

# Launches one state, waits for its line and then a window line after it; captures that window only and prints
# "<window> <x> <y> <w> <h>".
capture() {
    local file=$1 source=$2 state=$3 arguments=$4 start lines found="" refused
    quit_app
    start=$(date '+%Y-%m-%d %H:%M:%S')
    # shellcheck disable=SC2086 # the arguments are words on purpose
    launch_app "$DEMO_APP" -ZivletRevealResults NO $arguments
    for _ in $(seq 1 "$POLLS"); do
        lines=$(app_lines "$start")
        found=$(sed -n "/^$source: $state/,\$p" <<<"$lines" | grep -m1 -E "^$source: window [0-9]+ frame " |
            sed -E "s/^$source: window ([0-9]+) frame /\1 /" || true)
        [[ -n "$found" ]] && break
        sleep 0.25
    done
    refused=$(grep 'screenshot flags refused' <<<"$lines" || true)
    [[ -z "$refused" ]] || { echo "error: $file: $refused" >&2; return 1; }
    [[ -n "$found" ]] || { echo "error: $file: no '$source: $state' line with a window after it" >&2; return 1; }
    sleep "$SETTLE"
    read -r window _ <<<"$found"
    screencapture -x -o -l "$window" "$OUT/$file.png" || true
    [[ -s "$OUT/$file.png" ]] || { echo "error: $file: no PNG was written" >&2; return 1; }
    echo "$found"
}

# Reads the surface in a text-free box of a capture and judges white text at 0.8 over it.
measure() {
    local file=$1 found=$2 kind=$3 box w h bx by bw bh luminance ratio verdict
    box=$WINDOW_BOX
    [[ "$kind" == island ]] && box=$ISLAND_BOX
    read -r _ _ _ w h <<<"$found"
    read -r bx by bw bh <<<"$box"
    ((by < 0)) && by=$((h + by))
    luminance=$($LUMINANCE "$OUT/$file.png" "$bx" "$by" "$bw" "$bh" "$w") || { echo "error: $file: no luminance" >&2; return 1; }
    ratio=$(contrast "$luminance")
    verdict=$(awk -v r="$ratio" -v m="$MIN_CONTRAST" 'BEGIN { print (r >= m ? "pass" : "FAIL") }')
    echo "contrast $file: surface luminance $luminance, white 0.8 text $ratio:1 (need $MIN_CONTRAST) $verdict"
    [[ "$verdict" == pass ]]
}

status=0
for entry in "${CAPTURES[@]}"; do
    IFS='|' read -r file source state arguments kind <<<"$entry"
    selected "$file" || continue
    if ! frame=$(capture "$file" "$source" "$state" "$arguments"); then status=1; continue; fi
    echo "$file.png ($frame)"
    [[ -z "$kind" ]] || measure "$file" "$frame" "$kind" || status=1
done
exit "$status"
