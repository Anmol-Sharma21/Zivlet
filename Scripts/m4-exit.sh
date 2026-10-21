#!/usr/bin/env bash
# The automated M4 exit rows X1–X9 (10h F8), in order. Each row's output goes to build/m4-exit/<row>.log and one
# line per row says pass or fail; the script exits 1 when any row failed. X6 says "skipped (busy)" instead of FAIL
# when make bench skipped because another process kept the Mac busy (bench-guard.sh, G-M4-11); that is not a pass,
# so re-run X6 on a quiet Mac. The owner rows (O-1 … O-6) are not here: docs/plan/qa/trigger.md and
# docs/plan/qa/actions.md list them. ZIVLET_M4_EXIT_LOGS replaces build/m4-exit (script tests only).
# Usage: Scripts/m4-exit.sh [--only X1,X4,...] [--list]     --list prints the rows and commands without running.
set -euo pipefail
source "$(dirname "$0")/env.sh"
LOGS=${ZIVLET_M4_EXIT_LOGS:-$REPO_ROOT/build/m4-exit}
BUSY_SKIP='^Skipped: the Mac is busy' # bench-guard.sh's skip line
ROWS="X1 X2 X3 X4 X5 X6 X7 X8 X9"

command_of() {
    case "$1" in
        X1) echo "make vendor-test lint test coverage app release-check licence-gate" ;;
        X2) echo "ZIVLET_FFMPEG_DIR=Vendor/out/media-stage/Helpers make smoke" ;;
        X3) echo "ZIVLET_FFMPEG_DIR=/opt/homebrew/bin make smoke" ;;
        X4) echo "ZIVLET_MATRIX=full make matrix" ;;
        X5) echo "make fixtures-check && Vendor/repro-check.sh" ;;
        X6) echo "make bench" ;;
        X7) echo "make release-dry-run" ;;
        X8) echo "demo set through the Debug app: jpg→png png→webp heic→jpg mov→mp4 wav→mp3 mp4→webm (Scripts/demo-convert.sh)" ;;
        X9) echo "no TCC request other than folder access while X8 ran (log show, subsystem com.apple.TCC)" ;;
    esac
}

ONLY=""
LIST=0
while (($#)); do
    case "$1" in
        --only) ONLY=${2:?--only needs rows, e.g. X1,X4}; shift 2 ;;
        --list) LIST=1; shift ;;
        *) echo "error: unknown argument $1 (--only, --list)" >&2; exit 2 ;;
    esac
done
selected=$ROWS
if [[ -n "$ONLY" ]]; then
    for row in ${ONLY//,/ }; do
        [[ " $ROWS " == *" $row "* ]] || { echo "error: unknown row $row (X1–X9)" >&2; exit 2; }
    done
    selected=""
    for row in $ROWS; do [[ ",$ONLY," == *",$row,"* ]] && selected+="$row "; done
fi

if ((LIST)); then
    for row in $selected; do echo "$row $(command_of "$row")"; done
    exit 0
fi

# X8: one demo conversion per pair from the small fixtures, in a scratch folder, through the drop path.
demo_set() {
    local dir pair input
    dir=$(mktemp -d "${TMPDIR:-/tmp}/zivlet-demo-set.XXXXXX")
    make fixtures >/dev/null
    for pair in srgb.jpg:png srgb.png:webp srgb.heic:jpg sdr-h264.mov:mp4 pcm24.wav:mp3 sdr-h264.mp4:webm; do
        input=$dir/${pair%%:*}
        cp "$REPO_ROOT/build/fixtures/small/${pair%%:*}" "$input"
        "$REPO_ROOT/Scripts/demo-convert.sh" "$input" "${pair##*:}"
    done
    pkill -x Zivlet || true
    rm -rf "$dir" # our own scratch folder: the copied fixtures and their outputs
}

# X9: Accessibility, Input Monitoring or event posting asked for during X8 fails the row.
no_tcc_prompts() {
    local requests
    requests=$(/usr/bin/log show --start "$X8_START" --style compact \
        --predicate 'subsystem == "com.apple.TCC" AND eventMessage CONTAINS[c] "zivlet"' 2>/dev/null |
        grep -E 'kTCCService(Accessibility|ListenEvent|PostEvent)' || true)
    [[ -z "$requests" ]] || { echo "$requests"; return 1; }
    echo "no Accessibility, Input Monitoring or event-posting request since $X8_START"
}

run_row() {
    case "$1" in
        X1) make vendor-test lint test coverage app release-check licence-gate ;;
        X2) ZIVLET_FFMPEG_DIR=$REPO_ROOT/Vendor/out/media-stage/Helpers make smoke ;;
        X3) ZIVLET_FFMPEG_DIR=/opt/homebrew/bin make smoke ;;
        X4) ZIVLET_MATRIX=full make matrix ;;
        X5) make fixtures-check && "$REPO_ROOT/Vendor/repro-check.sh" ;;
        X6) make bench ;;
        X7) make release-dry-run ;;
        X8) demo_set ;;
        X9) no_tcc_prompts ;;
    esac
}

mkdir -p "$LOGS"
cd "$REPO_ROOT"
X8_START=$(date '+%Y-%m-%d %H:%M:%S')
failed=0
for row in $selected; do
    [[ "$row" == X8 ]] && X8_START=$(date '+%Y-%m-%d %H:%M:%S')
    started=$SECONDS
    if run_row "$row" >"$LOGS/$row.log" 2>&1; then
        echo "$row pass ($((SECONDS - started)) s)  $(command_of "$row")"
    elif [[ "$row" == X6 ]] && skip=$(grep -m1 "$BUSY_SKIP" "$LOGS/$row.log"); then
        echo "$row skipped (busy) ($((SECONDS - started)) s)  $(command_of "$row")  $skip"
    else
        echo "$row FAIL ($((SECONDS - started)) s)  $(command_of "$row")  see $LOGS/$row.log"
        failed=1
    fi
done
exit "$failed"
