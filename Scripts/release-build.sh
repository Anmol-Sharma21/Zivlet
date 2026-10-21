#!/usr/bin/env bash
# Release build for the release workflow and make release-dry-run (P1-53): XcodeGen, `xcodebuild archive` (Release,
# ad-hoc; the vendored helpers are embedded and signed by the embed phase), then
#   build/release/work/Zivlet.app             the app, ready for Scripts/sign-app.sh
#   build/release/Zivlet-<version>-dSYMs.zip  the app's and the media helpers' dSYMs
# CFBundleShortVersionString is <version>; CFBundleVersion is the commit count, which only grows on main.
# Usage: Scripts/release-build.sh <version>
set -euo pipefail
source "$(dirname "$0")/env.sh"
VERSION=${1:?usage: release-build.sh <version>}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] ||
    { echo "error: version must look like 1.2.3 or 1.2.3-alpha, got [$VERSION]" >&2; exit 2; }
RELEASE=${ZIVLET_RELEASE_DIR:-$REPO_ROOT/build/release}
WORK=$RELEASE/work
ARCHIVE=$WORK/Zivlet.xcarchive
BUILD_NUMBER=${ZIVLET_BUILD_NUMBER:-$(git -C "$REPO_ROOT" rev-list --count HEAD)}
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "error: build number must be digits, got [$BUILD_NUMBER]" >&2; exit 2; }
LOG=$WORK/xcodebuild-archive.log

cd "$REPO_ROOT"
mkdir -p "$WORK"
rm -rf "$ARCHIVE" "$WORK/Zivlet.app"
/opt/homebrew/bin/xcodegen generate --spec project.yml >/dev/null
if ! xcodebuild -project Zivlet.xcodeproj -scheme Zivlet -configuration Release -archivePath "$ARCHIVE" \
    -derivedDataPath "$WORK/DerivedData" CODE_SIGN_IDENTITY=- MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive >"$LOG" 2>&1; then
    grep -E "error:" "$LOG" | grep -v -e DVTPlugIn -e CoreSimulator >&2 || true
    echo "error: archive failed (full log: $LOG)" >&2
    exit 1
fi
ditto "$ARCHIVE/Products/Applications/Zivlet.app" "$WORK/Zivlet.app"

DSYMS=$WORK/dSYMs
rm -rf "$DSYMS"; mkdir -p "$DSYMS"
ditto "$ARCHIVE/dSYMs" "$DSYMS"
if [[ -d "$REPO_ROOT/Vendor/out/media-dsym" ]]; then ditto "$REPO_ROOT/Vendor/out/media-dsym" "$DSYMS"; fi
rm -f "$RELEASE/Zivlet-$VERSION-dSYMs.zip"
(cd "$WORK" && ditto -c -k --keepParent dSYMs "$RELEASE/Zivlet-$VERSION-dSYMs.zip")
echo "Release build: $WORK/Zivlet.app ($VERSION, build $BUILD_NUMBER), dSYMs in Zivlet-$VERSION-dSYMs.zip"
