#!/usr/bin/env bash
# Packs the vendor outputs (media stage, dSYMs, xcframeworks, keys) into Vendor/out/zivlet-vendor-<KEY>.tar.xz,
# so another checkout or CI job restores them with unpack.sh instead of compiling FFmpeg (11a §6.6).
# Usage: Vendor/pack.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ZIVLET_VENDOR_WORK:-$ROOT/Vendor}
OUT=$WORK/out
PARTS="KEY media-stage media-dsym CWebP.xcframework CWebP.sha256 CWebP.key CZivletSVG.xcframework
CZivletSVG.sha256 CZivletSVG.key"

[[ -s "$OUT/KEY" ]] || { echo "error: $OUT/KEY missing; run make vendor first" >&2; exit 1; }
key=$(tr -d '[:space:]' <"$OUT/KEY")
[[ "$key" =~ ^[0-9a-f]{64}$ ]] || { echo "error: $OUT/KEY is not a cache key" >&2; exit 1; }
members=()
for part in $PARTS; do [[ -e "$OUT/$part" ]] && members+=("out/$part"); done
tarball=$OUT/zivlet-vendor-$key.tar.xz
COPYFILE_DISABLE=1 tar -C "$WORK" -cJf "$tarball" "${members[@]}"
echo "packed ${#members[@]} parts into $tarball ($(du -h "$tarball" | cut -f1 | tr -d ' '))"
