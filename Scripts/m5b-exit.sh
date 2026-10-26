#!/usr/bin/env bash
# The automated M5b exit rows Y1–Y9 (plan 16 §7), in order. Each row's output goes to build/m5b-exit/<row>.log and
# one line per row says pass, fail or skip; the script exits 1 when any row failed or was skipped. A screenshot row
# is skipped, not passed, when its script found the screen locked. The owner rows are not here:
# docs/plan/qa/drop-box.md lists them. ZIVLET_M5B_EXIT_LOGS replaces build/m5b-exit and ZIVLET_M5B_LOG replaces
# /usr/bin/log (script tests only); ZIVLET_M5B_BASE is the commit before M5b (default: the plan's baseline).
# Each row runs in its own bash process with errexit on: inside `if` bash ignores `set -e` for everything a row
# calls, so a failing step could otherwise leave the row passing on its last check.
# Usage: Scripts/m5b-exit.sh [--only Y1,Y4,...] [--list]     --list prints the rows and commands without running.
set -euo pipefail
source "$(dirname "$0")/env.sh"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
LOGS=${ZIVLET_M5B_EXIT_LOGS:-$REPO_ROOT/build/m5b-exit}
LOG_TOOL=${ZIVLET_M5B_LOG:-/usr/bin/log}
BASE=${ZIVLET_M5B_BASE:-0ef22d6}
MAX_LINES=800
ROWS="Y1 Y2 Y3 Y4 Y5 Y6 Y7 Y8 Y9"
NEW_MODULES="ZivletShelfCore ZivletBox"
SHELF_SOURCES=Packages/ZivletKit/Sources/ZivletShelfCore
BOX_SOURCES=Packages/ZivletKit/Sources/ZivletBox
# The shelf core is Foundation only (D-M5b-1): Foundation, os and its one dependency, ZivletCore (itself Foundation only).
SHELF_IMPORTS="Foundation os ZivletCore"
SKIPPED_LINE="skipped: screen locked"

command_of() {
    case "$1" in
        Y1) echo "make test lint coverage app release-check licence-gate (ZivletShelfCore and ZivletBox measured)" ;;
        Y2) echo "make script-test" ;;
        Y3) echo "Scripts/m5a-exit.sh --only X2,X3,X4,X5 (the M5a rows still pass)" ;;
        Y4) echo "make box-demo (add four files, show the panel, relaunch, restored)" ;;
        Y5) echo "make box-states (every box and tray state, contrast over white)" ;;
        Y6) echo "no tccd request with preflight=no for Zivlet while Y3–Y5 ran (D-M5a-5)" ;;
        Y7) echo "make drag-replay (synthetic drags: proximity and shake)" ;;
        Y8) echo "make box-idle (Debug idle CPU of the panel and the resting tray minus a baseline)" ;;
        Y9) echo "hygiene since $BASE: signed off, no Co-Authored-By, no file ≥ $MAX_LINES lines, no personal path," \
            "shelf core imports, no NSAlert in ZivletBox" ;;
    esac
}

ONLY=""
LIST=0
ROW=""
while (($#)); do
    case "$1" in
        --only) ONLY=${2:?--only needs rows, e.g. Y1,Y4}; shift 2 ;;
        --list) LIST=1; shift ;;
        --row) ROW=${2:?--row needs a row}; shift 2 ;;  # internal: one row, in its own process
        *) echo "error: unknown argument $1 (--only, --list)" >&2; exit 2 ;;
    esac
done
selected=$ROWS
if [[ -n "$ONLY" ]]; then
    for row in ${ONLY//,/ }; do
        [[ " $ROWS " == *" $row "* ]] || { echo "error: unknown row $row (Y1–Y9)" >&2; exit 2; }
    done
    selected=""
    for row in $ROWS; do [[ ",$ONLY," == *",$row,"* ]] && selected+="$row "; done
fi

if ((LIST)); then
    for row in $selected; do echo "$row $(command_of "$row")"; done
    exit 0
fi

# Y1: the gates, and a measured coverage line for each new module (coverage.sh passes a module without lines).
gates() {
    local out module
    make test lint
    out=$(make coverage)
    echo "$out"
    for module in $NEW_MODULES; do
        grep -Eq "^$module +[0-9]+/[0-9]+ +lines +[0-9]+%" <<<"$out" ||
            { echo "no coverage line with a percentage for $module"; return 1; }
    done
    make app release-check licence-gate
}

# Y6: a request that could prompt fails the row; preflight checks are listed (D-M5a-5). It watches the demos of
# Y3–Y5, so it refuses to run without them, and a log reader that fails is a failure, not "no request".
no_tcc_prompts() {
    local stream lines asked
    if [[ " $DEMO_ROWS " != *" Y3 "* || " $DEMO_ROWS " != *" Y4 "* || " $DEMO_ROWS " != *" Y5 "* ]]; then
        echo "Y6 needs Y3, Y4 and Y5 in the same run (it checks what their demos asked for)"
        return 1
    fi
    stream=$("$LOG_TOOL" show --start "$DEMO_START" --style compact --predicate 'subsystem == "com.apple.TCC"') ||
        { echo "log show failed (status $?)"; return 1; }
    echo "TCC lines examined: $(grep -c . <<<"$stream" || true)"
    [[ -n "$stream" ]] || echo "warning: the TCC stream was empty since $DEMO_START"
    lines=$(grep -i 'zivlet' <<<"$stream" || true)
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

# Y9, part 1: every commit since BASE signed off and without Co-Authored-By.
commits_clean() {
    local commit status=0
    for commit in $(git rev-list "$BASE..HEAD"); do
        git log -1 --format=%B "$commit" | grep -q '^Signed-off-by: ' || { echo "not signed off: $commit"; status=1; }
        if git log -1 --format=%B "$commit" | grep -qi '^Co-Authored-By:'; then
            echo "Co-Authored-By: $commit"
            status=1
        fi
    done
    return "$status"
}

# Y9, part 2: no changed source file at or over the limit, and no personal or scratch path added.
changes_clean() {
    local file lines scratch status=0
    while IFS= read -r file; do
        [[ -f "$file" && "$file" =~ \.(swift|sh)$ ]] || continue
        lines=$(wc -l <"$file")
        ((lines < MAX_LINES)) || { echo "$file has $((lines)) lines"; status=1; }
    done < <(git diff --name-only "$BASE..HEAD")
    # Split so this line does not match itself.
    scratch="/private/tmp/""claude"
    if git diff "$BASE..HEAD" | grep -E '^\+' | grep -E "/Users/$(whoami)([^a-z]|$)|$scratch"; then
        echo "a personal path was added"
        status=1
    fi
    return "$status"
}

# Y9, part 3: the shelf core imports only what D-M5b-1 allows; the box never raises a modal alert (D-M5b-12).
modules_clean() {
    local line module status=0
    while IFS= read -r line; do
        module=$(awk '{ print $NF }' <<<"${line#*:}")
        [[ " $SHELF_IMPORTS " == *" $module "* ]] || { echo "shelf core: $line"; status=1; }
    done < <(grep -rE '^[[:space:]]*(@[a-zA-Z]+ )*import ' "$SHELF_SOURCES" || true)
    if grep -rn 'NSAlert' "$BOX_SOURCES"; then
        echo "ZivletBox uses NSAlert"
        status=1
    fi
    return "$status"
}

hygiene() {
    local status=0
    commits_clean || status=1
    changes_clean || status=1
    modules_clean || status=1
    ((status == 0)) && echo "hygiene clean since $BASE"
    return "$status"
}

run_row() {
    case "$1" in
        Y1) gates ;;
        Y2) make script-test ;;
        Y3) "$REPO_ROOT/Scripts/m5a-exit.sh" --only X2,X3,X4,X5 ;;
        Y4) make box-demo ;;
        Y5) make box-states ;;
        Y6) no_tcc_prompts ;;
        Y7) make drag-replay ;;
        Y8) make box-idle ;;
        Y9) hygiene ;;
    esac
}

cd "$REPO_ROOT"
if [[ -n "$ROW" ]]; then
    run_row "$ROW"
    exit 0
fi

mkdir -p "$LOGS"
export DEMO_START DEMO_ROWS=""
DEMO_START=$(date '+%Y-%m-%d %H:%M:%S')
failed=0
for row in $selected; do
    [[ "$row" == Y3 ]] && DEMO_START=$(date '+%Y-%m-%d %H:%M:%S')
    [[ "$row" == Y[345] ]] && DEMO_ROWS+=" $row"
    started=$SECONDS
    if ! bash "$SELF" --row "$row" >"$LOGS/$row.log" 2>&1; then
        echo "$row FAIL ($((SECONDS - started)) s)  $(command_of "$row")  see $LOGS/$row.log"
        failed=1
    elif grep -qF "$SKIPPED_LINE" "$LOGS/$row.log"; then
        echo "$row SKIP ($((SECONDS - started)) s, screen locked)  $(command_of "$row")"
        failed=1
    else
        echo "$row pass ($((SECONDS - started)) s)  $(command_of "$row")"
    fi
done
exit "$failed"
