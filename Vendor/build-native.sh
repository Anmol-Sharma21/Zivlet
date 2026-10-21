#!/usr/bin/env bash
# Packages in-process native libraries as static xcframeworks for SwiftPM binary targets (P1-25, D-M4-9).
# Usage: Vendor/build-native.sh libwebp
#   libwebp: libwebp.a + libwebpmux.a + libwebpdemux.a + libsharpyuv.a (built by build-media.sh with the same
#   flags) -> libCWebP.a + headers + module map -> Vendor/out/CWebP.xcframework, content hash in CWebP.sha256.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ZIVLET_VENDOR_WORK:-$ROOT/Vendor}
PREFIX=$WORK/prefix; OUT=$WORK/out; STAGING=$WORK/build/native
export ZERO_AR_DATE=1

source "$ROOT/Vendor/xcframework.sh"

build_libwebp() {
    if [[ ! -f "$PREFIX/lib/libwebp.a" ]]; then
        [[ -d "$(ls -d "$WORK"/src/libwebp-* 2>/dev/null | head -1)" ]] || "$ROOT/Vendor/fetch.sh" --only libwebp \
            --src "$WORK/src" >/dev/null
        "$ROOT/Vendor/build-media.sh" libwebp
    fi
    local dir=$STAGING/CWebP
    rm -rf "$dir"
    mkdir -p "$dir/Headers/webp"
    xcrun libtool -static -o "$dir/libCWebP.a" "$PREFIX/lib/libwebp.a" "$PREFIX/lib/libwebpmux.a" \
        "$PREFIX/lib/libwebpdemux.a" "$PREFIX/lib/libsharpyuv.a"
    cp "$PREFIX"/include/webp/{decode,encode,types,mux,mux_types,demux}.h "$dir/Headers/webp/"
    cat >"$dir/Headers/module.modulemap" <<'MAP'
module CWebP {
    header "webp/encode.h"
    header "webp/decode.h"
    header "webp/mux.h"
    header "webp/demux.h"
    link "CWebP"
    export *
}
MAP
    package_xcframework CWebP "$dir/libCWebP.a" "$dir/Headers"
}

case "${1:-}" in
    libwebp) build_libwebp ;;
    *) echo "usage: build-native.sh libwebp" >&2; exit 2 ;;
esac
