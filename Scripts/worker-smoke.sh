#!/usr/bin/env bash
# Worker smoke run (plan 18c C12, exit row Z5; Debug builds only): starts the app's -ZivletWorkerSmoke mode on a
# temporary folder this script creates. The app, without UI, converts a PNG in the worker, cancels a slow job,
# retries a job whose worker it SIGKILLs once, fails a job whose worker it kills twice ("This file made the engine
# crash") while the next job of the batch succeeds, waits for the idle exit, writes one JSON line per step to
# <folder>/worker-smoke.jsonl and quits. This script prints PASS or FAIL per step, fails on a missing step, and
# fails when a ZivletWorker crash report appeared during the run (SIGKILL writes none, D-M6-18). It removes only
# its own folder.
# Usage: Scripts/worker-smoke.sh [Zivlet.app]     (default: the Debug app of make app)
#   ZIVLET_REPORTS_DIR   where crash reports are looked for (default ~/Library/Logs/DiagnosticReports)
#   ZIVLET_SMOKE_TIMEOUT seconds to wait for the run (default 300)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP=${1:-$ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app}
REPORTS=${ZIVLET_REPORTS_DIR:-$HOME/Library/Logs/DiagnosticReports}
TIMEOUT=${ZIVLET_SMOKE_TIMEOUT:-300}
IDLE_SECONDS=5
STEPS="worker convert cancel crash-retry crash-twice idle-exit"
BINARY=$APP/Contents/MacOS/Zivlet
[[ -x "$BINARY" ]] || { echo "error: $BINARY not found; run make app" >&2; exit 1; }

RUN=$(mktemp -d "${TMPDIR:-/tmp}/zivlet-worker-smoke.XXXXXX")
trap 'rm -rf "$RUN"' EXIT
OUT=$RUN/worker-smoke.jsonl
touch "$RUN/.started"

"$BINARY" -ZivletWorkerSmoke "$RUN" -ZivletWorkerIdleSeconds "$IDLE_SECONDS" >"$RUN/app.log" 2>&1 &
APP_PID=$!
for ((i = 0; i < TIMEOUT * 2; i++)); do
    if [[ -f "$OUT" ]] && grep -q '"step":"done"' "$OUT"; then break; fi
    kill -0 "$APP_PID" 2>/dev/null || break
    sleep 0.5
done
# The app quits by itself after its last line; one that has not after 30 s more is stopped (only this child).
for ((i = 0; i < 60; i++)); do kill -0 "$APP_PID" 2>/dev/null || break; sleep 0.5; done
if kill -0 "$APP_PID" 2>/dev/null; then
    echo "FAIL: the app did not quit after the run; stopping it"
    kill "$APP_PID" 2>/dev/null || true
    STUCK=1
fi
wait "$APP_PID" 2>/dev/null || true

field() { plutil -extract "$2" raw -o - - <<<"$1" 2>/dev/null || true; }
status=${STUCK:-0}
for step in $STEPS; do
    line=$(grep "\"step\":\"$step\"" "$OUT" 2>/dev/null | tail -1 || true)
    if [[ -z "$line" ]]; then
        echo "MISSING $step"
        status=1
        continue
    fi
    ok=$(field "$line" ok)
    detail="$(field "$line" detail) ($(field "$line" ms) ms)"
    if [[ "$ok" == "true" ]]; then echo "PASS $step: $detail"; else echo "FAIL $step: $detail"; status=1; fi
done
grep -q '"step":"done"' "$OUT" 2>/dev/null || { echo "FAIL: the run did not finish within $TIMEOUT s"; status=1; }

crashes=$(find "$REPORTS" -maxdepth 1 -name 'ZivletWorker*' -newer "$RUN/.started" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$crashes" != "0" ]]; then
    echo "FAIL: $crashes ZivletWorker crash report(s) appeared during the run"
    status=1
else
    echo "OK: no worker crash report"
fi
exit "$status"
