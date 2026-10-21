#!/usr/bin/env bash
# Debug-build end-to-end check without a drag (M3): run one file through the drop path, then check the result.
# Usage: Scripts/demo-convert.sh /abs/input.ext <format> [cancel-after-ms]
# Needs `make app` first. Without a cancel delay: exactly one output beside the input and no staging left.
# With one: the batch reports a cancel, and neither an output nor a staging file is left.
source "$(dirname "$0")/env.sh"
INPUT="${1:?usage: demo-convert.sh /abs/input.ext <format> [cancel-after-ms]}"
TO="${2:?usage: demo-convert.sh /abs/input.ext <format> [cancel-after-ms]}"
CANCEL="${3:-}"
APP="$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app"
DIR="$(dirname "$INPUT")"
NAME="$(basename "$INPUT")"
OUT="$DIR/${NAME%.*}.$TO"
if [[ ! -d "$APP" ]]; then echo "error: $APP not found; run make app" >&2; exit 1; fi
if [[ ! -f "$INPUT" ]]; then echo "error: $INPUT is not a file" >&2; exit 1; fi
if [[ -e "$OUT" ]]; then echo "error: $OUT exists already; move it away first" >&2; exit 1; fi
pkill -x Zivlet || true
START="$(date '+%Y-%m-%d %H:%M:%S')"
ARGS=(-ZivletDemoConvert "$INPUT" "$TO" -ZivletRevealResults NO)
if [[ -n "$CANCEL" ]]; then ARGS+=(-ZivletDemoCancelAfter "$CANCEL"); fi
open -n "$APP" --args "${ARGS[@]}"
LINE=""
for _ in $(seq 1 120); do
    LINE="$(/usr/bin/log show --start "$START" --style compact \
        --predicate 'subsystem == "app.zivlet.Zivlet" AND eventMessage BEGINSWITH "Conversion finished"' |
        grep -o 'Conversion finished: .*' | tail -1 || true)"
    if [[ -n "$LINE" ]]; then break; fi
    sleep 0.5
done
# A cancel is reported at once; the helper teardown and staging removal follow within about 1 s (03a §4.6).
STAGING=1
for _ in $(seq 1 30); do
    STAGING="$(find "$DIR" -maxdepth 1 -name '.zivlet-*' | wc -l | tr -d ' ')"
    if [[ "$STAGING" == "0" ]]; then break; fi
    sleep 0.1
done
pkill -x Zivlet || true
if [[ -z "$LINE" ]]; then echo "error: no 'Conversion finished' log line within 60 s" >&2; exit 1; fi
echo "$LINE"
if [[ "$STAGING" != "0" ]]; then echo "error: $STAGING staging files left in $DIR after 3 s" >&2; exit 1; fi
if [[ -n "$CANCEL" ]]; then
    if [[ "$LINE" != *"0 saved, 0 failed, 1 cancelled"* || -e "$OUT" ]]; then echo "error: cancel left a result" >&2; exit 1; fi
    echo "OK: cancelled, nothing left in $DIR"
else
    if [[ "$LINE" != *"1 saved"* || ! -s "$OUT" ]]; then echo "error: $OUT was not produced" >&2; exit 1; fi
    echo "OK: $OUT ($(stat -f %z "$OUT") bytes)"
fi
