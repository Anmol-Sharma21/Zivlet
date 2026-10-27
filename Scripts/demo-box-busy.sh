#!/usr/bin/env bash
# Exit row Z8 (plan 18e E2): a cancelled bulk Move from the Drop Box, with Undo, in the Debug app. The script makes
# a scratch folder of its own and launches the app with -ZivletBoxBusyDemo <folder>. The app makes 50 small files in
# <folder>/source, adds them to a demo box kept in a store inside the folder (never the person's boxes.json), and
# moves them to <folder>/moved with a fixed destination (no folder panel), a little slower than usual so the bar can
# be seen. After the 20th file it holds and writes hold.json (the panel's frame); the script captures the busy
# overlay into build/box-busy-demo/box-busy.png and answers with `captured`; the app presses Cancel, runs Undo on the
# result, writes result.json and `done`, and quits. The check: the run stopped with 20 moved and 30 left, and after
# Undo all 50 files are back in source (the script counts them itself), with no hidden copy left. With the screen
# locked the picture is skipped ("skipped: screen locked") and the checks still run. The folder is removed at exit.
# Usage: Scripts/demo-box-busy.sh   (needs `make app`)
#        ZIVLET_BOX_BUSY_APP, _OUT, _TIMEOUT and ZIVLET_SCREEN_LOCKED are for the script test.
set -euo pipefail
source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/app-process.sh"
APP=${ZIVLET_BOX_BUSY_APP:-$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app}
OUT=${ZIVLET_BOX_BUSY_OUT:-$REPO_ROOT/build/box-busy-demo}
TIMEOUT=${ZIVLET_BOX_BUSY_TIMEOUT:-120}  # seconds for each wait
SETTLE=0.6                                # the overlay draws its latest fraction before the capture
FILES=50
STOP_AFTER=20
STOPPED_TOAST="Moved $STOP_AFTER items"
STOPPED_CARD="Stopped. $((FILES - STOP_AFTER)) items weren't moved."

value() { plutil -extract "$2" raw -o - "$1" 2>/dev/null || true; }
count_files() { find "$1" -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l | tr -d ' '; }

# Removes the scratch folder this script made, and nothing else.
drop_demo_dir() {
    local dir=$1
    [[ "$(basename "$dir")" == zivlet-m6-busy.* ]] || return 0
    rm -r -f "$dir"
}

screen_locked() {
    [[ "${ZIVLET_SCREEN_LOCKED:-}" == 1 ]] && return 0
    [[ "${ZIVLET_SCREEN_LOCKED:-}" == 0 ]] && return 1
    ioreg -n Root -d1 -a | grep -A1 -i 'CGSSessionScreenIsLocked' | grep -q '<true/>'
}

# Waits until the file exists; fails after TIMEOUT.
wait_for() {
    local file=$1 started=$SECONDS
    until [[ -e "$file" ]]; do
        ((SECONDS - started <= TIMEOUT)) || { echo "error: no $(basename "$file") within $TIMEOUT s" >&2; return 1; }
        sleep 0.2
    done
}

# The held overlay: its count, then the picture from the frame in hold.json (x y w h, points from the top left). The
# hold comes inside the 20th rename, before the executor reports it, so the bar the picture shows is at 19 ("shown").
capture_overlay() {
    local hold=$1/hold.json done shown total frame x y w h
    done=$(value "$hold" done)
    shown=$(value "$hold" shown)
    total=$(value "$hold" total)
    if [[ "$done" == "$STOP_AFTER" && "$shown" == "$((STOP_AFTER - 1))" && "$total" == "$FILES" ]]; then
        echo "PASS overlay: held at $done of $total, the bar drawn at $shown of $total"
    else
        echo "FAIL overlay: held at '$done' (bar '$shown') of '$total' (expected $STOP_AFTER, bar $((STOP_AFTER - 1)), of $FILES)"
        return 1
    fi
    if screen_locked; then
        echo "skipped: screen locked (no picture of the busy overlay)"
        return 0
    fi
    frame=$(value "$hold" frame)
    read -r x y w h <<<"$frame"
    [[ -n "${h:-}" ]] || { echo "FAIL overlay: no frame in hold.json"; return 1; }
    sleep "$SETTLE"
    mkdir -p "$OUT"
    screencapture -x -R"$x,$y,$w,$h" "$OUT/box-busy.png"
    echo "box-busy.png ($frame)"
}

check_stopped() {
    local result=$1/result.json toast card moved left
    toast=$(value "$result" toast)
    card=$(value "$result" card)
    moved=$(value "$result" movedBeforeUndo)
    left=$(value "$result" leftBeforeUndo)
    if [[ "$(value "$result" kind)" == partial && "$toast" == "$STOPPED_TOAST" && "$card" == "$STOPPED_CARD" &&
        "$moved" == "$STOP_AFTER" && "$left" == "$((FILES - STOP_AFTER))" ]]; then
        echo "PASS stopped: $toast; $card"
    else
        echo "FAIL stopped: toast '$toast', card '$card', $moved moved and $left left before Undo"
        return 1
    fi
}

check_undo() {
    local dir=$1 back left hidden
    back=$(count_files "$dir/source")
    left=$(count_files "$dir/moved")
    hidden=$(find "$dir/moved" -maxdepth 1 -name '.zivlet-move-*' 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$back" == "$FILES" && "$left" == 0 && "$hidden" == 0 &&
        "$(value "$dir/result.json" sourceAfterUndo)" == "$FILES" ]]; then
        echo "PASS undo: $back back in source, $left left in moved ($(value "$dir/result.json" undo))"
    else
        echo "FAIL undo: $back in source, $left in moved, $hidden hidden copies (expected $FILES, 0, 0)"
        return 1
    fi
}

[[ -d "$APP" ]] || { echo "error: $APP not found; run make app" >&2; exit 1; }
DEMO=$(mktemp -d "${TMPDIR:-/tmp}/zivlet-m6-busy.XXXXXX")
cleanup() {
    quit_launched
    drop_demo_dir "$DEMO"
}
trap cleanup EXIT
launch_app "$APP" -ZivletRevealResults NO -ZivletBoxBusyDemo "$DEMO"
wait_for "$DEMO/hold.json"
status=0
capture_overlay "$DEMO" || status=1
touch "$DEMO/captured"
wait_for "$DEMO/done"
check_stopped "$DEMO" || status=1
check_undo "$DEMO" || status=1
exit "$status"
