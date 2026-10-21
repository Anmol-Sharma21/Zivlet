#!/usr/bin/env bash
# Vendor outputs for a CI job (P0-37): restore the packed tarball for the current cache key from the runner's cache
# directory when it is there, otherwise build what is missing (make vendor) and store the packed result for the next
# job. The cache directory is ZIVLET_VENDOR_CACHE, else $RUNNER_TOOL_CACHE/zivlet-vendor on a runner; on a developer
# Mac without either, this is just `make vendor` (which skips up-to-date outputs).
# Usage: Scripts/ci-vendor.sh
set -euo pipefail
source "$(dirname "$0")/env.sh"
CACHE=${ZIVLET_VENDOR_CACHE:-${RUNNER_TOOL_CACHE:+$RUNNER_TOOL_CACHE/zivlet-vendor}}
OUT=${ZIVLET_VENDOR_WORK:-$REPO_ROOT/Vendor}/out
KEEP=3 # tarballs kept in the cache directory (about 0.1 GB each)

key=$("$REPO_ROOT/Vendor/cache-key.sh")
name=zivlet-vendor-$key.tar.xz
if [[ -n "$CACHE" && -f "$CACHE/$name" ]]; then
    "$REPO_ROOT/Vendor/unpack.sh" "$CACHE/$name"
    exit 0
fi
"$REPO_ROOT/Vendor/vendor.sh"
[[ -n "$CACHE" ]] || exit 0
"$REPO_ROOT/Vendor/pack.sh"
mkdir -p "$CACHE"
cp "$OUT/$name" "$CACHE/$name.part" && mv "$CACHE/$name.part" "$CACHE/$name"
# Oldest first; only our own tarball names are ever removed.
ls -1t "$CACHE"/zivlet-vendor-*.tar.xz 2>/dev/null | tail -n +$((KEEP + 1)) | while IFS= read -r old; do
    rm -f "$old"
done
echo "cached $name in $CACHE"
