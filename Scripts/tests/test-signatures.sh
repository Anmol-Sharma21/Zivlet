#!/usr/bin/env bash
# sign-app.sh signs inside-out with the hardened runtime; verify-signatures.sh checks every Mach-O, reports ad-hoc
# signatures without failing, refuses a modified library, and demands a Developer ID when asked to.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
APP=$ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app
[[ -x "$APP/Contents/Helpers/ffmpeg" ]] || fail "no Debug app with helpers; run make vendor app first"
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
ditto "$APP" "$T/Zivlet.app"

"$ROOT/Scripts/sign-app.sh" - "$T/Zivlet.app" >/dev/null
out=$("$ROOT/Scripts/verify-signatures.sh" "$T/Zivlet.app") || fail "verify failed on a freshly signed app: $out"
assert_contains "$out" "report-only: ad-hoc signature"
info=$(codesign -dv "$T/Zivlet.app/Contents/Helpers/ffmpeg" 2>&1)
assert_contains "$info" "flags=0x10002(adhoc,runtime)"
assert_contains "$info" "Identifier=app.zivlet.helper.ffmpeg"
"$T/Zivlet.app/Contents/Helpers/ffmpeg" -hide_banner -version | grep -q "ffmpeg version" ||
    fail "the re-signed helper does not run"
app_info=$(codesign -dv "$T/Zivlet.app" 2>&1)
assert_contains "$app_info" "runtime"

out=$("$ROOT/Scripts/verify-signatures.sh" "$T/Zivlet.app" --require-developer-id 2>&1 || true)
assert_contains "$out" "Developer ID signature required (owner step O-1)"
assert_fails "$ROOT/Scripts/verify-signatures.sh" "$T/Zivlet.app" --require-developer-id

# --helpers-only leaves the app's own signature alone.
before=$(codesign -dvvv "$T/Zivlet.app" 2>&1 | grep '^CDHash=')
"$ROOT/Scripts/sign-app.sh" --helpers-only - "$T/Zivlet.app" >/dev/null
assert_eq "$(codesign -dvvv "$T/Zivlet.app" 2>&1 | grep '^CDHash=')" "$before" "app CDHash after --helpers-only"

printf 'x' >> "$T/Zivlet.app/Contents/Frameworks/libavutil.61.dylib"
out=$("$ROOT/Scripts/verify-signatures.sh" "$T/Zivlet.app" 2>&1 || true)
assert_contains "$out" "libavutil.61.dylib"
assert_fails "$ROOT/Scripts/verify-signatures.sh" "$T/Zivlet.app"
assert_fails "$ROOT/Scripts/sign-app.sh" - "$T/missing.app"
echo "PASS test-signatures"
