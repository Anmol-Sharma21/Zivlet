#!/usr/bin/env bash
# The automated M7 exit rows V1–V13 (plan 20 §7, D-M7-26), in order. Each row's output goes to build/m7-exit/<row>.log
# and one line per row says pass, fail or skip; the script exits 1 when any row failed or was skipped. A screenshot
# row is skipped, not passed, when its script found the screen locked, and so is a row whose real-time budget was not
# judged above the load limit (Scripts/timing.sh, D-M7-3). The owner rows are not here: docs/plan/qa/tool-window.md,
# password.md, pdf-lock.md and read-qr.md list them.
# Script tests only: ZIVLET_M7_EXIT_LOGS replaces build/m7-exit, ZIVLET_M7_LOG replaces /usr/bin/log,
# ZIVLET_M7_RELEASE_APP the Release app of make release-check and ZIVLET_M7_VENDOR the Vendor folder (its verify
# scripts, versions.lock and downloads). ZIVLET_M7_BASE is the commit before M7 (default: the plan's baseline).
# Each row runs in its own bash process with errexit on: inside `if` bash ignores `set -e` for everything a row
# calls, so a failing step could otherwise leave the row passing on its last check.
# Usage: Scripts/m7-exit.sh [--only V1,V5,...] [--list]     --list prints the rows and commands without running.
set -euo pipefail
source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/exit-lib.sh"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
LOGS=${ZIVLET_M7_EXIT_LOGS:-$REPO_ROOT/build/m7-exit}
LOG_TOOL=${ZIVLET_M7_LOG:-/usr/bin/log}
RELEASE_APP=${ZIVLET_M7_RELEASE_APP:-$REPO_ROOT/build/ReleaseCheck/Build/Products/Release/Zivlet.app}
VENDOR=${ZIVLET_M7_VENDOR:-$REPO_ROOT/Vendor}
WORKER=$RELEASE_APP/Contents/XPCServices/ZivletWorker.xpc
BASE=${ZIVLET_M7_BASE:-5107be7}
MAX_LINES=800
ROWS="V1 V2 V3 V4 V5 V6 V7 V8 V9 V10 V11 V12 V13"
DEMOS="V6 V7 V8 V9 V10 V11"
NEW_MODULES="EnginePDF CZivletPDF"
SOURCE_DIRS="Packages/ZivletKit/Sources App Worker"
VISION_HOME=Packages/ZivletKit/Sources/EngineVision/
QPDF_HOME=Packages/ZivletKit/Sources/CZivletPDF/
# The Release worker before qpdf was linked (plan 20d C6, at 8460320): the difference to today's worker is an upper
# bound of what qpdf and libjpeg-turbo add, since it also holds every line of worker code written since.
WORKER_BYTES_WITHOUT_QPDF=6150560
QPDF_BUDGET_BYTES=4500000
# A message of qpdf's document reader (as Scripts/check-bundle.sh), so stripped Release binaries are still told apart.
QPDF_MARKER="unsupported encryption filter"
KEYCHAIN_API='SecItemAdd|SecItemCopyMatching|SecItemUpdate|SecItemDelete|kSecClass'
PRIOR_ART_NAME='[Tt]angerine'

command_of() {
    case "$1" in
        V1) echo "make test lint coverage app release-check licence-gate (EnginePDF and CZivletPDF measured)" ;;
        V2) echo "make script-test" ;;
        V3) echo "Scripts/m5a-exit.sh --only X2,X3,X4,X5, Scripts/m5b-exit.sh --only Y4,Y5,Y7 and" \
            "Scripts/m6-exit.sh --only Z4,Z5,Z7,Z8 (earlier rows still pass)" ;;
        V4) echo "make timing (the real-time budgets, judged only below the load limit)" ;;
        V5) echo "qpdf provenance: Vendor/verify-sources.sh, Vendor/verify-native.sh CQPDF, the Release worker's" \
            "otool -L, qpdf in the worker only, licence texts, both tarballs, the size against 4.5 MB" ;;
        V6) echo "make pdf-smoke (lock, unlock, change, a wrong password, legacy inputs and a form in the real worker)" ;;
        V7) echo "make password-policy and Scripts/check-secrets.sh" ;;
        V8) echo "make lock-demo (lock, unlock and change through the drop path)" ;;
        V9) echo "make qr-demo (Read QR through the drop path)" ;;
        V10) echo "make locked-input-demo (a locked PDF's password asked for by Copy Text)" ;;
        V11) echo "make tool-states (every new state on screen, contrast)" ;;
        V12) echo "no tccd request with preflight=no for Zivlet or its worker while V6–V11 ran (D-M5a-5)" ;;
        V13) echo "hygiene since $BASE: signed off, no Co-Authored-By, no file ≥ $MAX_LINES lines, no personal path," \
            "no binary or PDF added, no print(, no new NSAlert, Vision only in EngineVision, qpdf headers only in" \
            "CZivletPDF, no Keychain item API, no --password, no worker entitlements, cap counts" ;;
    esac
}

ONLY=""
LIST=0
ROW=""
while (($#)); do
    case "$1" in
        --only) ONLY=${2:?--only needs rows, e.g. V1,V5}; shift 2 ;;
        --list) LIST=1; shift ;;
        --row) ROW=${2:?--row needs a row}; shift 2 ;;  # internal: one row, in its own process
        *) echo "error: unknown argument $1 (--only, --list)" >&2; exit 2 ;;
    esac
done
selected=$ROWS
if [[ -n "$ONLY" ]]; then
    for row in ${ONLY//,/ }; do
        [[ " $ROWS " == *" $row "* ]] || { echo "error: unknown row $row (V1–V13)" >&2; exit 2; }
    done
    selected=""
    for row in $ROWS; do [[ ",$ONLY," == *",$row,"* ]] && selected+="$row "; done
fi

if ((LIST)); then
    for row in $selected; do echo "$row $(command_of "$row")"; done
    exit 0
fi

source "$(dirname "$0")/m7-exit-rows.sh"

cd "$REPO_ROOT"
if [[ -n "$ROW" ]]; then
    run_row "$ROW"
    exit 0
fi

mkdir -p "$LOGS"
export DEMO_START DEMO_ROWS="" V1_PASSED=""
DEMO_START=$(date '+%Y-%m-%d %H:%M:%S')
failed=0
for row in $selected; do
    [[ "$row" == V6 ]] && DEMO_START=$(date '+%Y-%m-%d %H:%M:%S')
    [[ " $DEMOS " == *" $row "* ]] && DEMO_ROWS+=" $row"
    started=$SECONDS
    if ! bash "$SELF" --row "$row" >"$LOGS/$row.log" 2>&1; then
        echo "$row FAIL ($((SECONDS - started)) s)  $(command_of "$row")  see $LOGS/$row.log"
        failed=1
    elif grep -qF "$SKIPPED_LINE" "$LOGS/$row.log"; then
        echo "$row SKIP ($((SECONDS - started)) s, $SKIPPED_LINE)  $(command_of "$row")"
        failed=1
    elif grep -qF "$NOT_JUDGED_LINE" "$LOGS/$row.log"; then
        echo "$row SKIP ($((SECONDS - started)) s, $(grep -m1 -F "$NOT_JUDGED_LINE" "$LOGS/$row.log"))" \
            " $(command_of "$row")"
        failed=1
    else
        echo "$row pass ($((SECONDS - started)) s)  $(command_of "$row")"
        [[ "$row" == V1 ]] && V1_PASSED=1
    fi
done
exit "$failed"
