#!/usr/bin/env bash
# release-local.sh and release-build.sh refuse malformed versions and arguments before building anything (the full
# run is make release-dry-run).
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
for script in release-local.sh release-build.sh; do
    for bad in "" "v0.1.0" "0.1" "0.1.0;rm" "../0.1.0" "0.1.0-"; do
        set +e; out=$("$ROOT/Scripts/$script" "$bad" 2>&1); code=$?; set -e
        [[ $code -ne 0 ]] || fail "$script accepted [$bad]"
    done
done
set +e; out=$("$ROOT/Scripts/release-local.sh" 0.1.0 --identity 2>&1); code=$?; set -e
assert_eq "$code" "2" "--identity without a value"
assert_contains "$out" "usage: release-local.sh"
set +e; "$ROOT/Scripts/release-local.sh" 0.1.0 --identity - >/dev/null 2>&1; code=$?; set -e
assert_eq "$code" "2" "--identity - (ad-hoc is the default, not an identity)"
set +e; out=$(ZIVLET_BUILD_NUMBER=12a "$ROOT/Scripts/release-build.sh" 0.1.0 2>&1); code=$?; set -e
assert_eq "$code" "2" "a non-numeric build number"
grep -q '^release-dry-run:' "$ROOT/Makefile" || fail "Makefile has no release-dry-run target"
echo "PASS test-release-local"
