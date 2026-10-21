#!/usr/bin/env bash
# build-native.sh libwebp packages libwebp 1.6.0 (encoder, mux, demux, sharpyuv) as CWebP.xcframework.
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
X=$ROOT/Vendor/out/CWebP.xcframework
[[ -f "$X/Info.plist" ]] || "$ROOT/Vendor/build-native.sh" libwebp >/dev/null
assert_file "$X/Info.plist"
lib=$(find "$X" -name 'libCWebP.a' | head -1); assert_file "$lib"
nm -gU "$lib" 2>/dev/null | grep -q "_WebPAnimEncoderNew" || fail "anim encoder missing"
nm -gU "$lib" 2>/dev/null | grep -q "_WebPMuxSetChunk" || fail "mux missing"
nm -gU "$lib" 2>/dev/null | grep -q "_WebPDemuxInternal" || fail "demux missing"
nm -gU "$lib" 2>/dev/null | grep -q "_SharpYuvConvert" || fail "sharpyuv missing"
if strings -a "$lib" | grep -qE '/Users/|/private/tmp/|/var/folders/|/opt/homebrew'; then fail "path leak"; fi
grep -q 'module CWebP' "$(find "$X" -name module.modulemap | head -1)" || fail "no module map"
assert_file "$ROOT/Vendor/out/CWebP.sha256"
lipo -archs "$lib" | grep -qx arm64 || fail "not arm64 only"
assert_fails "$ROOT/Vendor/build-native.sh" not-a-library
echo "PASS test-build-native"
