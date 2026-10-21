#!/usr/bin/env bash
# trim-sparkle.sh removes Sparkle's XPC services (Zivlet is not sandboxed) and thins every Mach-O to arm64; the
# trimmed framework signs and verifies (D-M4-11). Uses the framework from the pinned, hash-checked tarball.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
read -r _ version url hash < <(awk '$1 == "sparkle"' "$ROOT/Vendor/versions.lock")
TARBALL=$ROOT/Vendor/downloads/sparkle-$version/$(basename "$url")
[[ -f "$TARBALL" ]] || fail "missing $TARBALL; run make vendor-fetch"
[[ "sha256:$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)" == "$hash" ]] || fail "$TARBALL does not match the lock"
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/src" "$T/Zivlet.app/Contents/Frameworks" "$T/Zivlet.app/Contents/MacOS"
tar -xf "$TARBALL" -C "$T/src" ./Sparkle.framework
FW=$T/Zivlet.app/Contents/Frameworks/Sparkle.framework
ditto "$T/src/Sparkle.framework" "$FW"
[[ -d "$FW/Versions/B/XPCServices" ]] || fail "the pinned framework has no XPCServices to strip"

out=$("$ROOT/Scripts/trim-sparkle.sh" "$FW") || fail "trim failed: $out"
assert_contains "$out" "Trimmed Sparkle.framework"
assert_no_file "$FW/Versions/B/XPCServices"
assert_no_file "$FW/XPCServices"
for bin in Versions/B/Sparkle Versions/B/Autoupdate Versions/B/Updater.app/Contents/MacOS/Updater; do
    assert_eq "$(lipo -archs "$FW/$bin")" "arm64" "$bin"
done
# Twice is harmless (every Debug build runs the embed phase).
"$ROOT/Scripts/trim-sparkle.sh" "$FW" >/dev/null || fail "a second trim failed"

"$ROOT/Scripts/sign-app.sh" --nested-only - "$T/Zivlet.app" >/dev/null
codesign --verify --strict "$FW" || fail "the trimmed framework does not verify after signing"
codesign --verify --strict "$FW/Versions/B/Updater.app" || fail "Updater.app does not verify"
assert_contains "$(codesign -dv "$FW/Versions/B/Autoupdate" 2>&1)" "runtime"

assert_fails "$ROOT/Scripts/trim-sparkle.sh" "$T/missing.framework"
echo "PASS test-trim-sparkle"
