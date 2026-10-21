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

# What a job does with the cache: pull requests only read it; only main writes it; --from-source ignores it.
plan() { env -i PATH="$PATH" HOME="$HOME" ZIVLET_VENDOR_CACHE=$T/cache ZIVLET_VENDOR_WORK=$T/work "$@" \
    "$ROOT/Scripts/ci-vendor.sh" --plan ${PLAN_ARGS[@]+"${PLAN_ARGS[@]}"}; }
PLAN_ARGS=()
assert_eq "$(plan GITHUB_ACTIONS=true GITHUB_EVENT_NAME=pull_request GITHUB_REF=refs/pull/7/merge)" "restore"
rm -f "$T/cache/"*.tar.xz
assert_eq "$(plan GITHUB_ACTIONS=true GITHUB_EVENT_NAME=pull_request GITHUB_REF=refs/pull/7/merge)" "build"
assert_eq "$(plan GITHUB_ACTIONS=true GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/feature)" "build"
assert_eq "$(plan GITHUB_ACTIONS=true GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main)" "build and store"
assert_eq "$(plan GITHUB_ACTIONS=true GITHUB_EVENT_NAME=schedule GITHUB_REF=refs/heads/main)" "build and store"
assert_eq "$(plan)" "build and store" # a developer Mac with its own cache directory
COPYFILE_DISABLE=1 tar -C "$T/pack" -cJf "$T/cache/zivlet-vendor-$key.tar.xz" out
PLAN_ARGS=(--from-source)
assert_eq "$(plan GITHUB_ACTIONS=true GITHUB_EVENT_NAME=push GITHUB_REF=refs/tags/v1.0.0)" "build from source"
echo "PASS test-ci-vendor"
