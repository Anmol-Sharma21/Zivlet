#!/usr/bin/env bash
# ci-vendor.sh restores the tarball for the current cache key from the runner's cache directory instead of building.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
key=$("$ROOT/Vendor/cache-key.sh")
mkdir -p "$T/pack/out/media-stage" "$T/cache" "$T/work"
echo "$key" >"$T/pack/out/KEY"
echo marker >"$T/pack/out/media-stage/marker"
COPYFILE_DISABLE=1 tar -C "$T/pack" -cJf "$T/cache/zivlet-vendor-$key.tar.xz" out

out=$(ZIVLET_VENDOR_CACHE=$T/cache ZIVLET_VENDOR_WORK=$T/work "$ROOT/Scripts/ci-vendor.sh" 2>&1) ||
    fail "restore from the cache failed: $out"
assert_contains "$out" "unpacked zivlet-vendor-$key.tar.xz"
assert_eq "$(cat "$T/work/out/media-stage/marker")" "marker"
echo "PASS test-ci-vendor"
