#!/usr/bin/env bash
# size-gate.sh fails above the hard limits, warns above the warning limits and reports the parts of the app.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
fake_app() { # <name> <MB in Contents/Helpers>
    mkdir -p "$T/$1.app/Contents/MacOS" "$T/$1.app/Contents/Helpers" "$T/$1.app/Contents/Resources"
    mkfile -n "${2}m" "$T/$1.app/Contents/Helpers/ffmpeg"
    mkfile -n 1m "$T/$1.app/Contents/MacOS/Zivlet"
}

fake_app big 90
out=$("$ROOT/Scripts/size-gate.sh" "$T/big.app" 2>&1 || true)
assert_contains "$out" "over the 85 MB limit"
assert_fails "$ROOT/Scripts/size-gate.sh" "$T/big.app"

fake_app middling 75
out=$("$ROOT/Scripts/size-gate.sh" "$T/middling.app" 2>&1) || fail "a 76 MB app must only warn: $out"
assert_contains "$out" "warning: installed size"
assert_contains "$out" "Helpers"

fake_app small 10
out=$("$ROOT/Scripts/size-gate.sh" "$T/small.app" 2>&1) || fail "a small app must pass: $out"
assert_contains "$out" "Size OK"

# The DMG has its own limits, and the variables override the defaults.
mkfile -n 41m "$T/big.dmg"
assert_fails "$ROOT/Scripts/size-gate.sh" "$T/small.app" "$T/big.dmg"
mkfile -n 33m "$T/warn.dmg"
out=$("$ROOT/Scripts/size-gate.sh" "$T/small.app" "$T/warn.dmg" 2>&1) || fail "a 33 MB DMG must only warn"
assert_contains "$out" "warning: DMG size"
assert_fails env SIZE_HARD_MB=5 "$ROOT/Scripts/size-gate.sh" "$T/small.app"
echo "PASS test-size-gate"
