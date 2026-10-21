#!/usr/bin/env bash
# Debug-build demo check: open one Settings pane at launch and capture its window (D3).
# Usage: Scripts/demo-settings.sh general|updates|advanced
# Needs `make app` first, and Screen Recording permission for the terminal (screencapture).
source "$(dirname "$0")/env.sh"
PANE="${1:?usage: demo-settings.sh general|updates|advanced}"
APP="$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app"
OUT="$REPO_ROOT/build/settings-$PANE.png"
if [[ ! -d "$APP" ]]; then echo "error: $APP not found; run make app" >&2; exit 1; fi
pkill -x Zivlet || true
START="$(date '+%Y-%m-%d %H:%M:%S')"
open -n "$APP" --args -ZivletDemoSettings "$PANE"
WINDOW=""
for _ in $(seq 1 40); do
    WINDOW="$(/usr/bin/log show --start "$START" --style compact \
        --predicate 'subsystem == "app.zivlet.Zivlet" AND eventMessage BEGINSWITH "Settings shown"' |
        grep -o "Settings shown: $PANE window [0-9]*" | tail -1 | awk '{print $NF}' || true)"
    if [[ -n "$WINDOW" ]]; then break; fi
    sleep 0.5
done
if [[ -z "$WINDOW" || "$WINDOW" == "0" ]]; then
    pkill -x Zivlet || true
    echo "error: no 'Settings shown: $PANE' log line within 20 s" >&2
    exit 1
fi
sleep 1
screencapture -x -o -l "$WINDOW" "$OUT"
pkill -x Zivlet || true
echo "OK: $OUT"
