#!/usr/bin/env bash
# The average CPU use of one process over a window, from `ps -o time=` at its start and end (M5a exit row X6).
# ps counts CPU time in 10 ms steps, so windows under 120 s are refused: 10 ms over 120 s is 0.008 %, well under
# the 0.1 % gates. Prints the percentage with three decimals.
# Usage: Scripts/idle-cpu.sh PID SECONDS      exits 2 on bad arguments, a missing process or one that ended.
set -euo pipefail
MIN_SECONDS=120
PID=${1:-}
WINDOW=${2:-}
[[ "$PID" =~ ^[0-9]+$ && "$WINDOW" =~ ^[0-9]+$ ]] || { echo "usage: idle-cpu.sh PID SECONDS" >&2; exit 2; }
((WINDOW >= MIN_SECONDS)) || { echo "error: sample at least $MIN_SECONDS s (ps resolves 10 ms)" >&2; exit 2; }

# CPU seconds of PID as ps reports them ([[hh:]mm:]ss.cc), or nothing when the process is gone.
cpu_seconds() {
    local raw
    raw=$(ps -o time= -p "$PID" 2>/dev/null | tr -d ' ') || return 1
    [[ -n "$raw" ]] || return 1
    awk -F: '{ s = 0; for (i = 1; i <= NF; i++) s = s * 60 + $i; printf "%.2f\n", s }' <<<"$raw"
}

start=$(cpu_seconds) || { echo "error: no process $PID" >&2; exit 2; }
sleep "$WINDOW"
end=$(cpu_seconds) || { echo "error: process $PID ended during the sample" >&2; exit 2; }
awk -v a="$start" -v b="$end" -v w="$WINDOW" 'BEGIN { printf "%.3f\n", (b - a) / w * 100 }'
