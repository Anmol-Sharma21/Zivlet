#!/usr/bin/env bash
# make-dmg.sh builds Zivlet-<version>.dmg with the app and an Applications link, verifies it, signs it when given an
# identity, and refuses a missing app or a malformed version.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir)
MNT=$T/mnt
cleanup() { hdiutil detach -quiet "$MNT" 2>/dev/null || true; rm -rf "$T"; }
trap cleanup EXIT
mkdir -p "$T/in/Zivlet.app/Contents/MacOS" "$MNT"
printf '#!/bin/sh\nexit 0\n' >"$T/in/Zivlet.app/Contents/MacOS/Zivlet"
chmod +x "$T/in/Zivlet.app/Contents/MacOS/Zivlet"
plutil -create xml1 "$T/in/Zivlet.app/Contents/Info.plist"

out=$(ZIVLET_RELEASE_DIR=$T/release "$ROOT/Scripts/make-dmg.sh" "$T/in/Zivlet.app" 0.1.0-test 2>&1) ||
    fail "make-dmg failed: $out"
DMG=$T/release/Zivlet-0.1.0-test.dmg
assert_file "$DMG"
assert_contains "$out" "Zivlet-0.1.0-test.dmg"
assert_contains "$(diskutil image info "$DMG")" "Image Format: ULMO"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MNT" "$DMG" || fail "cannot mount $DMG"
[[ -x "$MNT/Zivlet.app/Contents/MacOS/Zivlet" ]] || fail "the DMG has no Zivlet.app"
assert_eq "$(readlink "$MNT/Applications")" "/Applications" "Applications link"
assert_eq "$(diskutil info "$MNT" | awk -F': *' '/Volume Name/ { print $2 }')" "Zivlet 0.1.0-test" "volume name"
hdiutil detach -quiet "$MNT"

# With an identity the DMG itself is signed (ad-hoc here; the release workflow passes the Developer ID).
ZIVLET_RELEASE_DIR=$T/release "$ROOT/Scripts/make-dmg.sh" "$T/in/Zivlet.app" 0.1.0-signed --identity - >/dev/null ||
    fail "make-dmg --identity - failed"
codesign --verify "$T/release/Zivlet-0.1.0-signed.dmg" || fail "the signed DMG does not verify"

out=$(ZIVLET_RELEASE_DIR=$T/release "$ROOT/Scripts/make-dmg.sh" "$T/in/Missing.app" 0.1.0 2>&1 || true)
assert_contains "$out" "is not an app bundle"
assert_fails env ZIVLET_RELEASE_DIR="$T/release" "$ROOT/Scripts/make-dmg.sh" "$T/in/Missing.app" 0.1.0
assert_fails env ZIVLET_RELEASE_DIR="$T/release" "$ROOT/Scripts/make-dmg.sh" "$T/in/Zivlet.app" "../x"
assert_fails env ZIVLET_RELEASE_DIR="$T/release" "$ROOT/Scripts/make-dmg.sh" "$T/in/Zivlet.app" 0.1.0 --identity
echo "PASS test-make-dmg"
