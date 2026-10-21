#!/usr/bin/env bash
# Restores vendor outputs packed by pack.sh. Refuses an archive whose KEY or component stamps differ from the
# current inputs (Vendor/cache-key.sh) unless --force, and any archive with a member outside out/. Never skipped,
# whatever the archive says about itself: each xcframework must match its tree hash, and a media stage must pass
# Vendor/verify-media.sh (ZIVLET_VERIFY_MEDIA names another verifier, for tests). The checks run on the extracted
# copy; a refused archive leaves out/ as it was.
# Usage: Vendor/unpack.sh <zivlet-vendor-KEY.tar.xz> [--force]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERIFY_MEDIA=${ZIVLET_VERIFY_MEDIA:-$ROOT/Vendor/verify-media.sh}
source "$ROOT/Vendor/xcframework.sh" # tree_hash
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
refuse() { echo "error: $(basename "$TARBALL"): $*" >&2; exit 1; }
for component in media CWebP CZivletSVG; do
    case "$component" in media) stamp=$tmp/out/media-stage/KEY ;; *) stamp=$tmp/out/$component.key ;; esac
    [[ -f "$stamp" ]] || continue
    want=$("$ROOT/Vendor/cache-key.sh" "$component")
    if [[ "$(tr -d '[:space:]' <"$stamp")" != "$want" && "$FORCE" != "--force" ]]; then
        refuse "$component was built from other inputs (stamp differs from $want)"
    fi
done
for framework in "$tmp"/out/*.xcframework; do
    [[ -d "$framework" ]] || continue
    name=$(basename "$framework" .xcframework)
    [[ -f "$tmp/out/$name.sha256" ]] || refuse "$name.xcframework has no $name.sha256"
    [[ "$(tree_hash "$framework")" == "$(tr -d '[:space:]' <"$tmp/out/$name.sha256")" ]] ||
        refuse "$name.xcframework does not match $name.sha256"
done
if [[ -d "$tmp/out/media-stage/Helpers" ]]; then
    "$VERIFY_MEDIA" "$tmp/out/media-stage" || refuse "the media stage failed verify-media.sh"
fi
mkdir -p "$OUT"
for part in "$tmp"/out/*; do
    name=$(basename "$part")
    rm -rf "${OUT:?}/$name"
    mv "$part" "$OUT/$name"
done
echo "unpacked $(basename "$TARBALL") into $OUT"
