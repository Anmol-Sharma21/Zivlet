#!/usr/bin/env bash
# Vendor outputs for a CI job (P0-37): restore the packed tarball for the current cache key from the runner's cache
# directory when it is there, otherwise build what is missing (make vendor). Only a push or scheduled run on main
# stores its packed result for the next job: pull requests read the cache but never write it, so their code cannot
# put outputs under main's key. Every restore goes through unpack.sh, which re-verifies what it restores.
# --from-source (the release job) ignores the cache and the existing outputs and builds every component from the
# pinned sources; nothing is stored. The cache directory is ZIVLET_VENDOR_CACHE, else $RUNNER_TOOL_CACHE/zivlet-vendor
# on a runner; on a developer Mac without either, this is just `make vendor` (which skips up-to-date outputs).
# Usage: Scripts/ci-vendor.sh [--from-source] [--plan]     --plan prints what it would do and exits.
set -euo pipefail
source "$(dirname "$0")/env.sh"
CACHE=${ZIVLET_VENDOR_CACHE:-${RUNNER_TOOL_CACHE:+$RUNNER_TOOL_CACHE/zivlet-vendor}}
OUT=${ZIVLET_VENDOR_WORK:-$REPO_ROOT/Vendor}/out
KEEP=3 # tarballs kept in the cache directory (about 0.1 GB each)
FROM_SOURCE=0
PLAN=0
for arg in "$@"; do
    case "$arg" in
        --from-source) FROM_SOURCE=1 ;;
        --plan) PLAN=1 ;;
        *) echo "error: unknown argument $arg (--from-source, --plan)" >&2; exit 2 ;;
    esac
done

# On GitHub, only main's own pushes and scheduled runs may write the cache; off GitHub, the developer's own may.
may_store() {
    [[ -n "$CACHE" ]] || return 1
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] || return 0
    [[ "${GITHUB_REF:-}" == "refs/heads/main" ]] || return 1
    case "${GITHUB_EVENT_NAME:-}" in push | schedule | workflow_dispatch) return 0 ;; *) return 1 ;; esac
}

key=$("$REPO_ROOT/Vendor/cache-key.sh")
name=zivlet-vendor-$key.tar.xz
if ((FROM_SOURCE)); then
    action="build from source"
elif [[ -n "$CACHE" && -f "$CACHE/$name" ]]; then
    action="restore"
elif may_store; then
    action="build and store"
else
    action="build"
fi
if ((PLAN)); then echo "$action"; exit 0; fi

case "$action" in
    "build from source")
        # Stamps gone, so vendor.sh rebuilds every component instead of trusting what is already in out/.
        rm -f "$OUT/media-stage/KEY" "$OUT/CWebP.key" "$OUT/CZivletSVG.key" "$OUT/KEY"
        "$REPO_ROOT/Vendor/vendor.sh"
        ;;
    restore) "$REPO_ROOT/Vendor/unpack.sh" "$CACHE/$name" ;;
    build) "$REPO_ROOT/Vendor/vendor.sh" ;;
    "build and store")
        "$REPO_ROOT/Vendor/vendor.sh"
        "$REPO_ROOT/Vendor/pack.sh"
        mkdir -p "$CACHE"
        cp "$OUT/$name" "$CACHE/$name.part" && mv "$CACHE/$name.part" "$CACHE/$name"
        # Oldest first; only our own tarball names are ever removed.
        ls -1t "$CACHE"/zivlet-vendor-*.tar.xz 2>/dev/null | tail -n +$((KEEP + 1)) | while IFS= read -r old; do
            rm -f "$old"
        done
        echo "cached $name in $CACHE"
        ;;
esac
