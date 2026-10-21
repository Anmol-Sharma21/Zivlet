#!/usr/bin/env bash
# ensure-native.sh builds CWebP and CZivletSVG from a clean tree, then only what is missing or stale.
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo"
(cd "$ROOT" && git ls-files Vendor | tar -cf - -T -) | tar -xf - -C "$T/repo"
export ZIVLET_VENDOR_WORK=$T/repo/Vendor   # tracked files only: no src, prefix, out or crate target

out=$("$ROOT/Vendor/ensure-native.sh" 2>&1) || { echo "$out" >&2; fail "first run failed"; }
assert_file "$T/repo/Vendor/out/CWebP.xcframework/Info.plist"
assert_file "$T/repo/Vendor/out/CZivletSVG.xcframework/Info.plist"

t0=$(date +%s)
out=$("$ROOT/Vendor/ensure-native.sh" 2>&1)
assert_contains "$out" "CWebP up to date"
assert_contains "$out" "CZivletSVG up to date"
(( $(date +%s) - t0 < 3 )) || fail "an up-to-date run took 3 s or more"

rm "$T/repo/Vendor/out/CWebP.xcframework/Info.plist"
out=$("$ROOT/Vendor/ensure-native.sh" 2>&1)
assert_contains "$out" "CWebP.xcframework "
assert_contains "$out" "CZivletSVG up to date"
assert_file "$T/repo/Vendor/out/CWebP.xcframework/Info.plist"
echo "PASS test-ensure-native"
