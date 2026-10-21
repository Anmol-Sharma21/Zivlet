#!/usr/bin/env bash
# Makes sure Vendor/out/media-stage matches the current inputs before a Release build (make release-check, dmg):
# up to date -> nothing; a packed archive for the current key in Vendor/out -> unpack it; otherwise build it
# (about 3 minutes clean).
set -euo pipefail
source "$(dirname "$0")/../Scripts/env.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ZIVLET_VENDOR_WORK:-$ROOT/Vendor}
key=$("$ROOT/Vendor/cache-key.sh" media)
stamp=$WORK/out/media-stage/KEY
if [[ -x "$WORK/out/media-stage/Helpers/ffmpeg" && -f "$stamp" && "$(cat "$stamp")" == "$key" ]]; then
    echo "media up to date"
    exit 0
fi
archive=$WORK/out/zivlet-vendor-$("$ROOT/Vendor/cache-key.sh").tar.xz
if [[ -f "$archive" ]]; then "$ROOT/Vendor/unpack.sh" "$archive"; exit 0; fi
exec "$ROOT/Vendor/vendor.sh" media
