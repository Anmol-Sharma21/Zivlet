#!/usr/bin/env bash
# Restores vendor outputs packed by pack.sh. Refuses an archive whose KEY differs from the current inputs
# (Vendor/cache-key.sh) unless --force, and any archive with a member outside out/.
# Usage: Vendor/unpack.sh <zivlet-vendor-KEY.tar.xz> [--force]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ZIVLET_VENDOR_WORK:-$ROOT/Vendor}
OUT=$WORK/out
TARBALL=${1:?usage: unpack.sh <tarball> [--force]}
FORCE=${2:-}

[[ -f "$TARBALL" ]] || { echo "error: $TARBALL not found" >&2; exit 1; }
# Members must be relative paths under out/ without `..` (bsdtar also refuses those, this says why).
while IFS= read -r member; do
    if [[ "$member" != out/* || "$member" == *..* ]]; then
        echo "error: $TARBALL has a member outside out/: $member" >&2
        exit 1
    fi
done < <(tar -tf "$TARBALL")

mkdir -p "$WORK"
tmp=$(mktemp -d "$WORK/.unpack.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
tar -xf "$TARBALL" -C "$tmp"
packed=$(tr -d '[:space:]' <"$tmp/out/KEY" 2>/dev/null || true)
current=$("$ROOT/Vendor/cache-key.sh")
if [[ "$packed" != "$current" && "$FORCE" != "--force" ]]; then
    echo "error: archive key ${packed:-missing} differs from the current inputs ($current); rebuild or pass --force" >&2
    exit 1
fi
mkdir -p "$OUT"
for part in "$tmp"/out/*; do
    name=$(basename "$part")
    rm -rf "${OUT:?}/$name"
    mv "$part" "$OUT/$name"
done
echo "unpacked $(basename "$TARBALL") into $OUT"
