#!/usr/bin/env bash
# The Drop Box across a relaunch (plan 16 E4, exit row Y4): copies four small fixtures into a scratch folder of its
# own, launches the Debug app with -ZivletBoxDemo <folder> (D-M5b-20: the demo box lives in a store inside that
# folder, never in the person's boxes.json), waits for `Box: shown` and `Box: items 4`, captures the panel from the
# last `Box: frame x y w h` line into build/m5b-exit/box-demo.png, quits, relaunches with the same folder and waits
# for `Box: restored 4 items`, quits, and removes its folder. With the screen locked the picture is skipped ("skipped:
# screen locked") and the restore is still checked.
# Usage: Scripts/demo-box.sh   (needs `make app`; makes the small fixtures when missing)
#        ZIVLET_BOX_DEMO_APP, _LOG (replaces /usr/bin/log), _FIXTURES, _OUT and _POLLS are for the script test.
set -euo pipefail
source "$(dirname "$0")/env.sh"
APP=${ZIVLET_BOX_DEMO_APP:-$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app}
LOG_TOOL=${ZIVLET_BOX_DEMO_LOG:-/usr/bin/log}
FIXTURES=${ZIVLET_BOX_DEMO_FIXTURES:-}
OUT=${ZIVLET_BOX_DEMO_OUT:-$REPO_ROOT/build/m5b-exit}
POLLS=${ZIVLET_BOX_DEMO_POLLS:-60}  # 0.25 s each
SETTLE=1.2                          # the panel settles before the capture
FILES="alpha.heic alpha.png pages.tiff pcm24.wav"
COUNT=4

if [[ -z "$FIXTURES" ]]; then
    FIXTURES=$REPO_ROOT/build/fixtures/small
    [[ -f "$FIXTURES/pcm24.wav" ]] || make -C "$REPO_ROOT" fixtures >/dev/null
fi
if [[ ! -d "$APP" ]]; then echo "error: $APP not found; run make app" >&2; exit 1; fi

quit_app() {
    osascript -e 'quit app "Zivlet"' >/dev/null 2>&1 || true
    sleep 2
    pkill -x Zivlet || true
}

# Removes the scratch folder this script made, and nothing else.
drop_demo_dir() {
    local dir=$1
    [[ "$(basename "$dir")" == zivlet-m5b-demo.* ]] || return 0
    rm -r -f "$dir"
}

DEMO=$(mktemp -d "${TMPDIR:-/tmp}/zivlet-m5b-demo.XXXXXX")
cleanup() {
    quit_app
    drop_demo_dir "$DEMO"
}
trap cleanup EXIT
for file in $FILES; do
    cp "$FIXTURES/$file" "$DEMO/$file" || { echo "error: fixture $file is missing" >&2; exit 1; }
done

box_lines() {
    "$LOG_TOOL" show --start "$1" --style compact --predicate 'subsystem == "app.zivlet.Zivlet"' |
        grep -oE 'Box: .*|Box demo refused.*' || true
}

# Launches the demo and waits until every line in "$@" is in the log; prints the lines seen, or fails.
launch_until() {
    local start lines line missing
    quit_app
    start=$(date '+%Y-%m-%d %H:%M:%S')
    open -n "$APP" --args -ZivletRevealResults NO -ZivletBoxDemo "$DEMO"
    for _ in $(seq 1 "$POLLS"); do
        lines=$(box_lines "$start")
        missing=""
        for line in "$@"; do grep -qxF "$line" <<<"$lines" || missing=$line; done
        [[ -n "$missing" ]] || break
        sleep 0.25
    done
    [[ -z "$missing" ]] || { echo "error: no '$missing' line; seen: $(tr '\n' ';' <<<"$lines")" >&2; return 1; }
    sleep "$SETTLE"
    box_lines "$start"
}

capture_panel() {
    local lines=$1 frame x y w h
    if ioreg -n Root -d1 -a | grep -A1 -i 'CGSSessionScreenIsLocked' | grep -q '<true/>'; then
        echo "skipped: screen locked (no picture of the panel)"
        return 0
    fi
    frame=$(grep '^Box: frame ' <<<"$lines" | tail -1 | sed 's/^Box: frame //')
    [[ -n "$frame" ]] || { echo "error: no 'Box: frame' line" >&2; return 1; }
    read -r x y w h <<<"$frame"
    mkdir -p "$OUT"
    screencapture -x -R"$x,$y,$w,$h" "$OUT/box-demo.png"
    echo "box-demo.png ($frame)"
}

lines=$(launch_until "Box: shown" "Box: items $COUNT")
echo "Box: shown"
echo "Box: items $COUNT"
capture_panel "$lines"
launch_until "Box: restored $COUNT items" >/dev/null
echo "Box: restored $COUNT items"
