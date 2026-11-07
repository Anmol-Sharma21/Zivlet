#!/usr/bin/env bash
# Exit row V9 (plan 20g F3, P2-51): READ QR through the drop path of the Debug app. The test bundle draws two images
# (a QR web link, a Code 128 ticket) and a PDF page with a QR text, in our own words, and the payloads they hold; the
# app (-ZivletQRDemo <folder>/inputs) reads them in the worker, opens the results window and reports what it showed.
# The check: the payloads equal the drawn ones, and Open is offered for the web link only. The results window alone is
# captured into <folder>/qr-results.png by the number the app logs (`QR demo: window <n>`). With the screen locked it runs nothing
# and says "skipped: screen locked". It deletes only its default folder or one it made (marked by .zivlet-qr-demo),
# and quits only the app it launched.
# Usage: Scripts/demo-qr.sh [folder]        (default build/qr-demo; needs `make app`)
#        ZIVLET_DEMO_LOG replaces /usr/bin/log (script tests).
set -euo pipefail
source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/app-process.sh"
source "$(dirname "$0")/demo-lib.sh"
DEFAULT_OUT=$REPO_ROOT/build/qr-demo
OUT=${1:-$DEFAULT_OUT}
LOG_TOOL=${ZIVLET_DEMO_LOG:-/usr/bin/log}

# The rows the app showed, one "payload<TAB>yes|no" line each, sorted.
shown_rows() {
    local report=$1 count index
    count=$(json_value "$report" rows)
    for ((index = 0; index < ${count:-0}; index++)); do
        printf '%s\t%s\n' "$(json_value "$report" "rows.$index.payload")" \
            "$([[ "$(json_value "$report" "rows.$index.open")" == true ]] && echo yes || echo no)"
    done | sort
}

check() {
    local report=$OUT/inputs/qr.json shown expected
    [[ -f "$report" ]] || { echo "FAIL qr: no report"; return 1; }
    [[ "$(json_value "$report" kind)" == window ]] ||
        { echo "FAIL qr: no results window ($(json_value "$report" toast))"; return 1; }
    shown=$(shown_rows "$report")
    expected=$(sort "$OUT/expected-codes.txt")
    if [[ "$shown" == "$expected" ]]; then
        echo "PASS qr: $(grep -c . <<<"$shown") codes, payloads equal, Open for the web link only"
    else
        printf 'FAIL qr: shown\n%s\nexpected\n%s\n' "$shown" "$expected"
        return 1
    fi
}

# The results window only, by its number (never a region of the screen, which could hold another app's window).
capture_window() {
    local found window
    found=$("$LOG_TOOL" show --start "$1" --style compact \
        --predicate 'subsystem == "app.zivlet.Zivlet" AND eventMessage BEGINSWITH "QR demo: window"' |
        grep -oE 'QR demo: window [0-9]+ frame .*' | tail -1 | sed 's/^QR demo: window //' || true)
    [[ -n "$found" ]] || { echo "FAIL capture: no results window in the log"; return 1; }
    read -r window _ <<<"$found"
    screencapture -x -o -l "$window" "$OUT/qr-results.png" || true
    [[ -s "$OUT/qr-results.png" ]] || { echo "FAIL capture: qr-results.png was not written"; return 1; }
    echo "PASS capture: qr-results.png (window $found)"
}

if demo_screen_locked; then
    echo "skipped: screen locked (nothing run)"
    exit 0
fi
[[ -d "$DEMO_APP" ]] || { echo "error: $DEMO_APP not found; run make app" >&2; exit 1; }
demo_folder "$OUT" "$DEFAULT_OUT" .zivlet-qr-demo
echo "rendering the inputs into $OUT"
render_inputs ToolDemoInputTests ZIVLET_QR_DUMP "$OUT"
trap quit_launched EXIT
start=$(date '+%Y-%m-%d %H:%M:%S')
launch_app "$DEMO_APP" -ZivletRevealResults NO -ZivletQRDemo "$OUT/inputs"
wait_done "$OUT/inputs"
status=0
check || status=1
capture_window "$start" || status=1
exit "$status"
