#!/usr/bin/env bash
# Disk image for a release (P1-53): build/release/Zivlet-<version>.dmg, an APFS ULMO image named "Zivlet <version>"
# holding Zivlet.app and a link to /Applications. No third-party DMG tool and no background artwork. With
# --identity the image itself is signed (the release workflow passes the Developer ID; notarize.sh follows). Always
# verified with `hdiutil verify`.
# Usage: Scripts/make-dmg.sh <Zivlet.app> <version> [--identity <identity|->]
set -euo pipefail
source "$(dirname "$0")/env.sh"
USAGE="usage: make-dmg.sh <Zivlet.app> <version> [--identity <identity|->]"
APP=${1:?$USAGE}
VERSION=${2:?$USAGE}
IDENTITY=""
if (($# > 2)); then
    [[ "$3" == "--identity" && $# -eq 4 && -n "$4" ]] || { echo "error: $USAGE" >&2; exit 2; }
    IDENTITY=$4
fi
[[ -d "$APP/Contents" && "$APP" == *.app ]] || { echo "error: $APP is not an app bundle" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ ]] || { echo "error: bad version [$VERSION]" >&2; exit 2; }
RELEASE=${ZIVLET_RELEASE_DIR:-$REPO_ROOT/build/release}
DMG=$RELEASE/Zivlet-$VERSION.dmg

mkdir -p "$RELEASE"
STAGING=$(mktemp -d "$RELEASE/.dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Zivlet.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -quiet -fs APFS -format ULMO -volname "Zivlet $VERSION" -srcfolder "$STAGING" "$DMG" ||
    { echo "error: hdiutil could not create $DMG" >&2; exit 1; }
if [[ -n "$IDENTITY" ]]; then
    TIMESTAMP="--timestamp"
    [[ "$IDENTITY" == "-" ]] && TIMESTAMP="--timestamp=none"
    codesign --force "$TIMESTAMP" --sign "$IDENTITY" "$DMG" || { echo "error: codesign failed for $DMG" >&2; exit 1; }
fi
hdiutil verify -quiet "$DMG" || { echo "error: $DMG does not verify" >&2; exit 1; }
echo "DMG: $DMG ($(du -k "$DMG" | cut -f1) KB)"
