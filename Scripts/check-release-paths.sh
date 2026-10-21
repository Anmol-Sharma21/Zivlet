#!/usr/bin/env bash
# P1-21 acceptance: a Release build must not contain a Homebrew tool path, so it can never pick up an unbundled
# ffmpeg. Builds the Release app into build/ReleaseCheck, scans every Mach-O file in it, then checks the bundled
# helpers and their libraries (P1-50, Scripts/check-bundle.sh), every signature (P1-52, report-only while
# ad-hoc) and the installed size (P1-52).
source "$(dirname "$0")/env.sh"
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
        if strings -a "$file" | grep -E "/opt/homebrew|/usr/local/bin"; then
            echo "error: Homebrew path in ${file#"$APP/"}" >&2
            found=1
        fi
    fi
done < <(find "$APP" -type f -print0)
if (( found )); then exit 1; fi
echo "Release build contains no Homebrew path."
"$REPO_ROOT/Scripts/check-bundle.sh" "$APP"
"$REPO_ROOT/Scripts/verify-signatures.sh" "$APP"
"$REPO_ROOT/Scripts/size-gate.sh" "$APP"
