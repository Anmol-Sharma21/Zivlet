#!/usr/bin/env bash
# check-release-paths.sh --scan-only (plan 16 D-M5b-20): a Release binary must not carry the Drop Box's debug flags,
# -ZivletBoxPreview (made-up boxes), -ZivletBoxDemo (a demo box) or -ZivletTrayPreview (a made-up tray), nor the
# drag-trace recorder's -ZivletRecordDragTraces (D-M5b-10), as it must not carry the island's preview flag.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT

cp /usr/bin/true "$T/clean"
"$ROOT/Scripts/check-release-paths.sh" --scan-only "$T/clean" >/dev/null || fail "a clean binary passes the scans"

for flag in -ZivletBoxPreview -ZivletBoxDemo -ZivletTrayPreview -ZivletRecordDragTraces -ZivletIslandPreview; do
    cp /usr/bin/true "$T/with$flag"
    printf '%s\0' "$flag" >>"$T/with$flag"
    status=0; out=$("$ROOT/Scripts/check-release-paths.sh" --scan-only "$T/with$flag" 2>&1) || status=$?
    assert_eq "$status" "1" "a binary with $flag is refused"
    assert_contains "$out" "$flag"
done
echo "PASS test-release-flags"
