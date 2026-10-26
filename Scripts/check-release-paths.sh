#!/usr/bin/env bash
# P1-21 acceptance: a Release build must not contain a Homebrew tool path, so it can never pick up an unbundled
# ffmpeg. Builds the Release app into build/ReleaseCheck, scans every Mach-O file in it, then checks the bundled
# helpers and their libraries (P1-50, Scripts/check-bundle.sh), every signature (P1-52, report-only while
# ad-hoc) and the installed size (P1-52).
# Plan 14 D-ND3: the same scan refuses the island preview's launch flag, so a shipped build can never show made-up
# jobs (only the CPU measurement build of notch-idle.sh CONFIG=release compiles it in). Plan 16 D-M5b-20: the Drop
# Box's debug flags (-ZivletBoxPreview, -ZivletBoxDemo, -ZivletTrayPreview) and the drag-trace recorder's flag (-ZivletRecordDragTraces,
# D-M5b-10) are refused the same way; no build compiles them in Release. Plan 18c: so are the worker's DEBUG smoke
# requests (selfKillForTesting, setIdleForTesting) and the smoke run's flags (-ZivletWorkerSmoke, -ZivletWorkerIdleSeconds).
# Usage: Scripts/check-release-paths.sh              build and check the Release app
#        Scripts/check-release-paths.sh --scan-only FILE   only the scans, on one file (script tests)
source "$(dirname "$0")/env.sh"
PREVIEW_FLAG="-ZivletIslandPreview"
BOX_FLAGS=("-ZivletBoxPreview" "-ZivletBoxDemo" "-ZivletTrayPreview")
TRACE_FLAG="-ZivletRecordDragTraces"
# Plan 18c (D-M6-18): the worker's DEBUG smoke requests; their Codable case names are the markers.
WORKER_MARKERS=("selfKillForTesting" "setIdleForTesting" "-ZivletWorkerSmoke" "-ZivletWorkerIdleSeconds")

# Prints what is wrong with one Mach-O file; exits 1 when anything is. Every byte is searched (grep -a), also data
# after the last segment, which strings skips in a universal file.
scan_file() {
    local file=$1 label=$2 found=0
    if LC_ALL=C grep -aoE "(/opt/homebrew|/usr/local/bin)[[:graph:]]*" "$file"; then
        echo "error: Homebrew path in $label" >&2
        found=1
    fi
    if LC_ALL=C grep -qaF -- "$PREVIEW_FLAG" "$file"; then
        echo "error: the island preview flag $PREVIEW_FLAG is in $label (Release must not show made-up jobs)" >&2
        found=1
    fi
    local flag
    for flag in "${BOX_FLAGS[@]}"; do
        if LC_ALL=C grep -qaF -- "$flag" "$file"; then
            echo "error: the Drop Box debug flag $flag is in $label (Release must not show made-up boxes)" >&2
            found=1
        fi
    done
    if LC_ALL=C grep -qaF -- "$TRACE_FLAG" "$file"; then
        echo "error: the drag-trace recorder flag $TRACE_FLAG is in $label (Release must not record drags)" >&2
        found=1
    fi
    for flag in "${WORKER_MARKERS[@]}"; do
        if LC_ALL=C grep -qaF -- "$flag" "$file"; then
            echo "error: the worker's debug request $flag is in $label (Release must not kill or retime its worker)" >&2
            found=1
        fi
    done
    return "$found"
}

if [[ "${1:-}" == --scan-only ]]; then
    file=${2:?--scan-only needs a file}
    [[ -f "$file" ]] || { echo "error: no file $file" >&2; exit 2; }
    scan_file "$file" "$file"
    exit $?
fi

cd "$REPO_ROOT"
DERIVED="$REPO_ROOT/build/ReleaseCheck"
LOG="$DERIVED/xcodebuild.log"
APP="$DERIVED/Build/Products/Release/Zivlet.app"
/opt/homebrew/bin/xcodegen generate --spec project.yml >/dev/null
# A stale app from an earlier run must never be scanned in place of this build's.
rm -rf "$DERIVED/Build/Products"
mkdir -p "$DERIVED"
if ! xcodebuild -project Zivlet.xcodeproj -scheme Zivlet -configuration Release -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY=- build >"$LOG" 2>&1; then
    grep -E "error:" "$LOG" | grep -v -e DVTPlugIn -e CoreSimulator >&2 || true
    echo "error: Release build failed (full log: $LOG)" >&2
    exit 1
fi
if [[ ! -d "$APP" ]]; then echo "error: Release build reported success but $APP is missing" >&2; exit 1; fi
found=0
while IFS= read -r -d '' file; do
    if file -b "$file" | grep -q "Mach-O"; then
        scan_file "$file" "${file#"$APP/"}" || found=1
    fi
done < <(find "$APP" -type f -print0)
if (( found )); then exit 1; fi
echo "Release build contains no Homebrew path, no island preview, no Drop Box debug flag, no drag recorder and no worker debug request."
"$REPO_ROOT/Scripts/check-bundle.sh" "$APP"
"$REPO_ROOT/Scripts/verify-signatures.sh" "$APP"
"$REPO_ROOT/Scripts/size-gate.sh" "$APP"
