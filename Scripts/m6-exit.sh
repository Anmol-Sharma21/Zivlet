#!/usr/bin/env bash
# The automated M6 exit rows Z1–Z11 (plan 18 §7), in order. Each row's output goes to build/m6-exit/<row>.log and
# one line per row says pass, fail or skip; the script exits 1 when any row failed or was skipped. A screenshot row
# is skipped, not passed, when its script found the screen locked. The owner rows are not here:
# docs/plan/qa/copy-text.md, docs/plan/qa/worker.md and docs/plan/qa/drop-box.md list them.
# Script tests only: ZIVLET_M6_EXIT_LOGS replaces build/m6-exit, ZIVLET_M6_LOG replaces /usr/bin/log and
# ZIVLET_M6_RELEASE_APP the Release app of make release-check. ZIVLET_M6_BASE is the commit before M6 (default:
# the plan's baseline).
# Each row runs in its own bash process with errexit on: inside `if` bash ignores `set -e` for everything a row
# calls, so a failing step could otherwise leave the row passing on its last check.
# Usage: Scripts/m6-exit.sh [--only Z1,Z5,...] [--list]     --list prints the rows and commands without running.
set -euo pipefail
source "$(dirname "$0")/env.sh"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
LOGS=${ZIVLET_M6_EXIT_LOGS:-$REPO_ROOT/build/m6-exit}
LOG_TOOL=${ZIVLET_M6_LOG:-/usr/bin/log}
RELEASE_APP=${ZIVLET_M6_RELEASE_APP:-$REPO_ROOT/build/ReleaseCheck/Build/Products/Release/Zivlet.app}
WORKER=$RELEASE_APP/Contents/XPCServices/ZivletWorker.xpc
WORKER_ID=app.zivlet.Zivlet.Worker
BASE=${ZIVLET_M6_BASE:-9cc6c69}
MAX_LINES=800
ROWS="Z1 Z2 Z3 Z4 Z5 Z6 Z7 Z8 Z9 Z10 Z11"
DEMOS="Z5 Z6 Z7 Z8 Z9"
NEW_MODULES="ZivletIPC ZivletWorkerCore EngineVision"
SOURCE_DIRS="Packages/ZivletKit/Sources App Worker"
VISION_HOME=Packages/ZivletKit/Sources/EngineVision/
SKIPPED_LINE="skipped: screen locked"

command_of() {
    case "$1" in
        Z1) echo "make test lint coverage app release-check licence-gate (ZivletIPC, ZivletWorkerCore and EngineVision measured)" ;;
        Z2) echo "make script-test" ;;
        Z3) echo "Scripts/m5a-exit.sh --only X2,X3,X4,X5 and Scripts/m5b-exit.sh --only Y4,Y5,Y7 (earlier rows still pass)" ;;
        Z4) echo "the Release worker: in the bundle, hardened runtime, identifier $WORKER_ID, no entitlements" ;;
        Z5) echo "make worker-smoke (convert, cancel, crash retry, crash twice, idle exit, no crash report)" ;;
        Z6) echo "make ocr-check (12 fixtures within 1 % CER with the production configuration)" ;;
        Z7) echo "make copy-text-demo (Copy Text through the drop path)" ;;
        Z8) echo "make box-busy-demo (a cancelled Move of 50 files, the busy overlay, Undo)" ;;
        Z9) echo "make text-states and make box-states (every new state, contrast over white)" ;;
        Z10) echo "no tccd request with preflight=no for Zivlet or its worker while Z5–Z9 ran (D-M5a-5)" ;;
        Z11) echo "hygiene since $BASE: signed off, no Co-Authored-By, no file ≥ $MAX_LINES lines, no personal path," \
            "no print(, no new NSAlert, import Vision only in EngineVision, no worker entitlements, cap counts" ;;
    esac
}

ONLY=""
LIST=0
ROW=""
while (($#)); do
    case "$1" in
        --only) ONLY=${2:?--only needs rows, e.g. Z1,Z5}; shift 2 ;;
        --list) LIST=1; shift ;;
        --row) ROW=${2:?--row needs a row}; shift 2 ;;  # internal: one row, in its own process
        *) echo "error: unknown argument $1 (--only, --list)" >&2; exit 2 ;;
    esac
done
selected=$ROWS
if [[ -n "$ONLY" ]]; then
    for row in ${ONLY//,/ }; do
        [[ " $ROWS " == *" $row "* ]] || { echo "error: unknown row $row (Z1–Z11)" >&2; exit 2; }
    done
    selected=""
    for row in $ROWS; do [[ ",$ONLY," == *",$row,"* ]] && selected+="$row "; done
fi

if ((LIST)); then
    for row in $selected; do echo "$row $(command_of "$row")"; done
    exit 0
fi

# Z1: the gates, and a measured coverage line for each new module (coverage.sh passes a module without lines).
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

# The worker's entitlements as codesign prints them; any key is one too many (02 §2.1: the worker has no entitlements).
worker_entitlements_empty() {
    local entitlements
    [[ -d "$WORKER" ]] || { echo "no Release worker at $WORKER (make release-check builds it)"; return 1; }
    entitlements=$(codesign -d --entitlements - --xml "$WORKER" 2>/dev/null)
    if grep -q '<key>' <<<"$entitlements"; then
        echo "the worker has entitlements: $entitlements"
        return 1
    fi
    echo "the worker has no entitlements"
}

# Z4: the worker in the Release bundle, signed with the hardened runtime under its own identifier. release-check
# already ran when Z1 passed in this run; otherwise this row runs it.
release_worker() {
    local details
    if [[ "${Z1_PASSED:-}" == 1 ]]; then echo "release-check ran in Z1"; else make release-check; fi
    [[ -d "$WORKER" ]] || { echo "no Release worker at $WORKER"; return 1; }
    details=$(codesign -dv --verbose=2 "$WORKER" 2>&1)
    echo "$details"
    grep -qx "Identifier=$WORKER_ID" <<<"$details" || { echo "the worker's identifier is not $WORKER_ID"; return 1; }
    grep -Eq '^CodeDirectory .*flags=[^ ]*runtime' <<<"$details" ||
        { echo "the worker is not signed with the hardened runtime"; return 1; }
    worker_entitlements_empty
}

# Z10: a request that could prompt fails the row; preflight checks are listed (D-M5a-5). It watches the demos of
# Z5–Z9, so it refuses to run without them, and a log reader that fails is a failure, not "no request".
no_tcc_prompts() {
    local stream lines asked row
    for row in $DEMOS; do
        [[ " $DEMO_ROWS " == *" $row "* ]] ||
            { echo "Z10 needs Z5, Z6, Z7, Z8 and Z9 in the same run (it checks what their demos asked for)"; return 1; }
    done
    stream=$("$LOG_TOOL" show --start "$DEMO_START" --style compact --predicate 'subsystem == "com.apple.TCC"') ||
        { echo "log show failed (status $?)"; return 1; }
    echo "TCC lines examined: $(grep -c . <<<"$stream" || true)"
    # An empty stream proves nothing (a window the log no longer holds, no privilege to read it): not a pass.
    [[ -n "$stream" ]] || { echo "the TCC stream was empty since $DEMO_START: nothing to check"; return 1; }
    lines=$(grep -i 'zivlet' <<<"$stream" || true)
    echo "preflight checks (listed, not failing):"
    grep 'preflight=yes' <<<"$lines" || echo "(none)"
    asked=$(grep 'preflight=no' <<<"$lines" || true)
    if [[ -n "$asked" ]]; then
        echo "requests that could prompt:"
        echo "$asked"
        return 1
    fi
    echo "no tccd request with preflight=no for Zivlet or its worker since $DEMO_START"
}

# Z11, part 1: every commit since BASE signed off and without Co-Authored-By.
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

# Z11, part 2: no changed source file at or over the limit, no personal or scratch path and no new NSAlert added.
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
    if git diff "$BASE..HEAD" -- '*.swift' | grep -E '^\+' | grep 'NSAlert'; then
        echo "new code uses NSAlert (results go to toasts and cards, never modal alerts)"
        status=1
    fi
    return "$status"
}

# The source folders this checkout has.
source_dirs() {
    local dir
    for dir in $SOURCE_DIRS; do [[ -d "$dir" ]] && echo "$dir"; done
    return 0
}

# Z11, part 3: no print( in shipped code (logs go to os.Logger), and Vision only in EngineVision (P2-103).
sources_clean() {
    local dirs found status=0
    dirs=$(source_dirs)
    [[ -n "$dirs" ]] || return 0
    # shellcheck disable=SC2086  # one folder per word
    if grep -rnE '(^|[^[:alnum:]_.])print\(' $dirs; then
        echo "print( in shipped sources"
        status=1
    fi
    # shellcheck disable=SC2086
    found=$(grep -rlE '^[[:space:]]*(@[a-zA-Z]+ )*import Vision[[:space:]]*$' $dirs | grep -v "^$VISION_HOME" || true)
    if [[ -n "$found" ]]; then
        echo "import Vision outside EngineVision:"
        echo "$found"
        status=1
    fi
    return "$status"
}

# Z11, part 4: the cap lint's count line per wheel list, kept in the log (P2-100).
cap_counts() {
    local counts=$LOGS/cap-counts.txt
    rm -f "$counts"
    make cap-lint COUNTS="$counts"
    [[ -s "$counts" ]] || { echo "the cap lint wrote no count lines"; return 1; }
    echo "cap lint counts:"
    cat "$counts"
    echo  # the report has no final newline
}

hygiene() {
    local status=0
    commits_clean || status=1
    changes_clean || status=1
    sources_clean || status=1
    worker_entitlements_empty || status=1
    cap_counts || status=1
    ((status == 0)) && echo "hygiene clean since $BASE"
    return "$status"
}

run_row() {
    case "$1" in
        Z1) gates ;;
        Z2) make script-test ;;
        Z3)
            "$REPO_ROOT/Scripts/m5a-exit.sh" --only X2,X3,X4,X5
            "$REPO_ROOT/Scripts/m5b-exit.sh" --only Y4,Y5,Y7
            ;;
        Z4) release_worker ;;
        Z5) make worker-smoke ;;
        Z6) make ocr-check ;;
        Z7) make copy-text-demo ;;
        Z8) make box-busy-demo ;;
        Z9)
            make text-states
            make box-states
            ;;
        Z10) no_tcc_prompts ;;
        Z11) hygiene ;;
    esac
}

cd "$REPO_ROOT"
if [[ -n "$ROW" ]]; then
    run_row "$ROW"
    exit 0
fi

mkdir -p "$LOGS"
export DEMO_START DEMO_ROWS="" Z1_PASSED=""
DEMO_START=$(date '+%Y-%m-%d %H:%M:%S')
failed=0
for row in $selected; do
    [[ "$row" == Z5 ]] && DEMO_START=$(date '+%Y-%m-%d %H:%M:%S')
    [[ " $DEMOS " == *" $row "* ]] && DEMO_ROWS+=" $row"
    started=$SECONDS
    if ! bash "$SELF" --row "$row" >"$LOGS/$row.log" 2>&1; then
        echo "$row FAIL ($((SECONDS - started)) s)  $(command_of "$row")  see $LOGS/$row.log"
        failed=1
    elif grep -qF "$SKIPPED_LINE" "$LOGS/$row.log"; then
        echo "$row SKIP ($((SECONDS - started)) s, $SKIPPED_LINE)  $(command_of "$row")"
        failed=1
    else
        echo "$row pass ($((SECONDS - started)) s)  $(command_of "$row")"
        [[ "$row" == Z1 ]] && Z1_PASSED=1
    fi
done
exit "$failed"
