#!/usr/bin/env bash
# Builds whatever vendor output is missing or stale (P0-37 local half): check tools, fetch, then per component
#   media       build-media.sh -> stage-media.sh -> verify-media.sh     stamp: out/media-stage/KEY
#   CWebP       build-native.sh libwebp                                 stamp: out/CWebP.key
#   CZivletSVG  build-rs.sh                                             stamp: out/CZivletSVG.key
# A component whose stamp equals its cache key (cache-key.sh) and whose output exists prints "up to date".
# Usage: Vendor/vendor.sh [component...]    (default: all three, then out/KEY is written)
set -euo pipefail
source "$(dirname "$0")/../Scripts/env.sh" # DEVELOPER_DIR: the same Xcode for every build and key
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ZIVLET_VENDOR_WORK:-$ROOT/Vendor}
OUT=$WORK/out
ALL=(media CWebP CZivletSVG)

stamp_of() {
    case "$1" in
        media) echo "$OUT/media-stage/KEY" ;;
        *) echo "$OUT/$1.key" ;;
    esac
}

output_of() {
    case "$1" in
        media) echo "$OUT/media-stage/Helpers/ffmpeg" ;;
        *) echo "$OUT/$1.xcframework/Info.plist" ;;
    esac
}

build() {
    case "$1" in
        media)
            "$ROOT/Vendor/build-media.sh"
            "$ROOT/Vendor/stage-media.sh"
            "$ROOT/Vendor/verify-media.sh" "$OUT/media-stage"
            ;;
        CWebP) "$ROOT/Vendor/build-native.sh" libwebp ;;
        CZivletSVG) "$ROOT/Vendor/build-rs.sh" ;;
    esac
}

# Builds one component unless its stamp matches the current key; writes the stamp only after success.
ensure() {
    local component=$1 key stamp
    key=$("$ROOT/Vendor/cache-key.sh" "$component"); stamp=$(stamp_of "$component")
    if [[ -f "$(output_of "$component")" && -f "$stamp" && "$(cat "$stamp")" == "$key" ]]; then
        echo "$component up to date"
        return
    fi
    build "$component"
    echo "$key" >"$stamp"
}

for c in "$@"; do
    [[ " ${ALL[*]} " == *" $c "* ]] || { echo "error: unknown component $c (known: ${ALL[*]})" >&2; exit 2; }
done
components=("${@:-${ALL[@]}}")
"$ROOT/Vendor/check-tools.sh"
if [[ " ${components[*]} " == *" media "* ]]; then "$ROOT/Vendor/fetch.sh" --src "$WORK/src" >/dev/null; fi
for c in "${components[@]}"; do ensure "$c"; done
if (($# == 0)); then "$ROOT/Vendor/cache-key.sh" >"$OUT/KEY"; fi
