#!/usr/bin/env bash
# Debug-build demo check: show the wheel without a drag, capture the main display, confirm the log line.
# Usage: Scripts/demo-wheel.sh convert|tools|actions [glass|solid] [highlight-slot]
# Needs `make app` first, and Screen Recording permission for the terminal (screencapture).
source "$(dirname "$0")/env.sh"
MODE="${1:?usage: demo-wheel.sh convert|tools|actions [glass|solid] [highlight-slot]}"
THEME="${2:-glass}"
SLOT="${3:-0}"
APP="$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app"
OUT="$REPO_ROOT/build/demo-$MODE-$THEME.png"
if [[ ! -d "$APP" ]]; then
    echo "error: $APP not found; run make app" >&2
    exit 1
fi
pkill -x Zivlet || true
open -n "$APP" --args -ZivletDemoWheel "$MODE" -ZivletDemoHighlight "$SLOT" -ZivletWheelTheme "$THEME"
sleep 2
screencapture -x -m "$OUT"
pkill -x Zivlet || true
if /usr/bin/log show --last 30s --style compact --predicate 'subsystem == "app.zivlet.Zivlet"' |
    grep -q "Wheel shown: $MODE, .* slices, $THEME"; then
    echo "OK: $OUT"
else
    echo "error: no 'Wheel shown: $MODE … $THEME' log line" >&2
    exit 1
fi
