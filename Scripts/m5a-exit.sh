#!/usr/bin/env bash
# The automated M5a exit rows X1–X7 (plan 12 §6), in order. Each row's output goes to build/m5a-exit/<row>.log and
# one line per row says pass or fail; the script exits 1 when any row failed. The owner rows Q1–Q22 are not here:
# docs/plan/qa/notch.md lists them. ZIVLET_M5A_EXIT_LOGS replaces build/m5a-exit and ZIVLET_M5A_LOG replaces
# /usr/bin/log (script tests only); ZIVLET_M5A_BASE is the commit before M5a (default: the plan's baseline).
# Usage: Scripts/m5a-exit.sh [--only X1,X4,...] [--list]     --list prints the rows and commands without running.
set -euo pipefail
source "$(dirname "$0")/env.sh"
LOGS=${ZIVLET_M5A_EXIT_LOGS:-$REPO_ROOT/build/m5a-exit}
LOG_TOOL=${ZIVLET_M5A_LOG:-/usr/bin/log}
BASE=${ZIVLET_M5A_BASE:-1716912}
MAX_LINES=800
ROWS="X1 X2 X3 X4 X5 X6 X7"

command_of() {
    case "$1" in
        X1) echo "make test lint coverage app release-check licence-gate" ;;
        X2) echo "make notch-timing, then a notch demo whose log has the drop→island signpost" ;;
        X3) echo "make notch-demo (heic→jpg at the notch, island lines and a screenshot in build/m5a-exit)" ;;
        X4) echo "make convert-demo PLACEMENT=nearDrop (today's card, no island)" ;;
        X5) echo "no tccd request with preflight=no for Zivlet while X2–X4 ran (D-M5a-5)" ;;
        X6) echo "make notch-idle (Debug app idle CPU per island state minus a baseline, 120 s each)" ;;
        X7) echo "hygiene since $BASE: signed off, no Co-Authored-By, no file ≥ $MAX_LINES lines, no personal path" ;;
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
        [[ " $ROWS " == *" $row "* ]] || { echo "error: unknown row $row (X1–X7)" >&2; exit 2; }
    done
    selected=""
    for row in $ROWS; do [[ ",$ONLY," == *",$row,"* ]] && selected+="$row "; done
fi

if ((LIST)); then
    for row in $selected; do echo "$row $(command_of "$row")"; done
    exit 0
fi

# A copy of the small HEIC fixture in a scratch folder of our own; prints its path.
demo_file() {
    local dir
    dir=$(mktemp -d "${TMPDIR:-/tmp}/zivlet-m5a-demo.XXXXXX")
    make fixtures >/dev/null
    cp "$REPO_ROOT/build/fixtures/small/srgb.heic" "$dir/srgb.heic" 2>/dev/null || touch "$dir/srgb.heic"
    echo "$dir/srgb.heic"
}

# Removes a scratch folder that demo_file made, and nothing else.
drop_demo_dir() {
    local dir=$1
    [[ "$(basename "$dir")" == zivlet-m5a-demo.* ]] || return 0
    rm -r -f "$dir"
}

# X2: the 50 ms test, then one notch demo; its signpost interval must be in the log.
drop_to_island() {
    local file start
    make notch-timing
    file=$(demo_file)
    start=$(date '+%Y-%m-%d %H:%M:%S')
    make convert-demo FILE="$file" TO=jpg PLACEMENT=notch
    drop_demo_dir "$(dirname "$file")"
    "$LOG_TOOL" show --start "$start" --signpost --style compact \
        --predicate 'subsystem == "app.zivlet.Zivlet" AND category == "hud"' | grep -F 'drop→island'
}

# X4: today's card, and no island line.
near_the_drop() {
    local file out
    file=$(demo_file)
    out=$(make convert-demo FILE="$file" TO=jpg PLACEMENT=nearDrop)
    drop_demo_dir "$(dirname "$file")"
    echo "$out"
    grep -q 'Result card' <<<"$out" || { echo "no Result card line"; return 1; }
    if grep -q 'Island:' <<<"$out"; then
        echo "the island showed with nearDrop"
        return 1
    fi
}

# X5: a request that could prompt fails the row; preflight checks are listed (D-M5a-5).
no_tcc_prompts() {
    local lines asked
    lines=$("$LOG_TOOL" show --start "$DEMO_START" --style compact --predicate 'subsystem == "com.apple.TCC"' \
        2>/dev/null | grep -i 'zivlet' || true)
    echo "preflight checks (listed, not failing):"
    grep 'preflight=yes' <<<"$lines" || echo "(none)"
    asked=$(grep 'preflight=no' <<<"$lines" || true)
    if [[ -n "$asked" ]]; then
        echo "requests that could prompt:"
        echo "$asked"
        return 1
    fi
    echo "no tccd request with preflight=no for Zivlet since $DEMO_START"
}

# X7: every commit since BASE signed off and without Co-Authored-By; no changed source file at or over the limit;
# no personal path added.
hygiene() {
    local commit status=0 file lines
    for commit in $(git rev-list "$BASE..HEAD"); do
        git log -1 --format=%B "$commit" | grep -q '^Signed-off-by: ' || { echo "not signed off: $commit"; status=1; }
        if git log -1 --format=%B "$commit" | grep -qi '^Co-Authored-By:'; then
            echo "Co-Authored-By: $commit"
            status=1
        fi
    done
    while IFS= read -r file; do
        [[ -f "$file" && "$file" =~ \.(swift|sh)$ ]] || continue
        lines=$(wc -l <"$file")
        ((lines < MAX_LINES)) || { echo "$file has $lines lines"; status=1; }
    done < <(git diff --name-only "$BASE..HEAD")
    if git diff "$BASE..HEAD" | grep -E '^\+' | grep -E "/Users/$(whoami)([^a-z]|$)|/private/tmp/claude"; then
        echo "a personal path was added"
        status=1
    fi
    ((status == 0)) && echo "hygiene clean since $BASE"
    return "$status"
}

run_row() {
    case "$1" in
        X1) make test lint coverage app release-check licence-gate ;;
        X2) drop_to_island ;;
        X3) make notch-demo ;;
        X4) near_the_drop ;;
        X5) no_tcc_prompts ;;
        X6) make notch-idle ;;
        X7) hygiene ;;
    esac
}

mkdir -p "$LOGS"
cd "$REPO_ROOT"
DEMO_START=$(date '+%Y-%m-%d %H:%M:%S')
failed=0
for row in $selected; do
    [[ "$row" == X2 ]] && DEMO_START=$(date '+%Y-%m-%d %H:%M:%S')
    started=$SECONDS
    if run_row "$row" >"$LOGS/$row.log" 2>&1; then
        echo "$row pass ($((SECONDS - started)) s)  $(command_of "$row")"
    else
        echo "$row FAIL ($((SECONDS - started)) s)  $(command_of "$row")  see $LOGS/$row.log"
        failed=1
    fi
done
exit "$failed"
