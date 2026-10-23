#!/usr/bin/env bash
# Debug-app demo of the Notch HUD (M5a exit row X3): converts the small HEIC fixture to JPEG with
# -ZivletHUDPlacement notch, crops the island's toast from the screen with `screencapture -x -R` using the
# `Island: frame x y w h` line the app logs, then checks the log for the island and result lines.
# Usage: Scripts/demo-notch.sh [out-dir]      (default build/m5a-exit; needs `make app` and `make fixtures`)
set -euo pipefail
source "$(dirname "$0")/env.sh"
OUT=${1:-$REPO_ROOT/build/m5a-exit}
APP="$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app"
FIXTURE="$REPO_ROOT/build/fixtures/small/srgb.heic"
POLLS=120 # 0.5 s each
if [[ ! -d "$APP" ]]; then echo "error: $APP not found; run make app" >&2; exit 1; fi
if [[ ! -f "$FIXTURE" ]]; then echo "error: $FIXTURE not found; run make fixtures" >&2; exit 1; fi
mkdir -p "$OUT"
DIR=$(mktemp -d "${TMPDIR:-/tmp}/zivlet-notch-demo.XXXXXX")
cleanup() {
    osascript -e 'quit app "Zivlet"' >/dev/null 2>&1 || true
    [[ "$(basename "$DIR")" == zivlet-notch-demo.* ]] && rm -r -f "$DIR"
}
trap cleanup EXIT
cp "$FIXTURE" "$DIR/srgb.heic"

island_lines() {
    /usr/bin/log show --start "$START" --style compact \
        --predicate 'subsystem == "app.zivlet.Zivlet" AND eventMessage BEGINSWITH "Island:"' | grep -o 'Island: .*' || true
}

pkill -x Zivlet || true
START=$(date '+%Y-%m-%d %H:%M:%S')
open -n "$APP" --args -ZivletDemoConvert "$DIR/srgb.heic" jpg -ZivletRevealResults NO -ZivletHUDPlacement notch
FRAME=""
for _ in $(seq 1 "$POLLS"); do
    LINES=$(island_lines)
    if grep -q '^Island: toast' <<<"$LINES"; then
        FRAME=$(sed -n '/^Island: toast/,$p' <<<"$LINES" | grep -m1 '^Island: frame' | sed 's/^Island: frame //' || true)
        [[ -n "$FRAME" ]] && break
    fi
    sleep 0.5
done
SHOT="$OUT/notch-toast.png"
if [[ -n "$FRAME" ]]; then
    read -r X Y W H <<<"$FRAME"
    screencapture -x -R"$X,$Y,$W,$H" "$SHOT" || echo "warning: screencapture failed (Screen Recording permission?)" >&2
fi
CARD=$(/usr/bin/log show --start "$START" --style compact \
    --predicate 'subsystem == "app.zivlet.Zivlet" AND eventMessage BEGINSWITH "Result card"' | grep -o 'Result card: .*' | tail -1 || true)
LINES=$(island_lines)
echo "$LINES"
[[ -n "$CARD" ]] && echo "$CARD"
status=0
for want in 'Island: collapsed' 'Island: toast' 'Island: frame'; do
    grep -q "^$want" <<<"$LINES" || { echo "error: no '$want' log line" >&2; status=1; }
done
[[ -n "$CARD" ]] || { echo "error: no 'Result card' log line" >&2; status=1; }
if [[ -s "$SHOT" ]]; then echo "screenshot: $SHOT"; else echo "error: no screenshot of the island" >&2; status=1; fi
exit "$status"
