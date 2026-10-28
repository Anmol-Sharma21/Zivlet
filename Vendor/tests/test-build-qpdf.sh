#!/usr/bin/env bash
# build-native.sh qpdf packages libqpdf 12.4.2 with libjpeg-turbo 3.2.0 as the static CQPDF.xcframework: native
# crypto only, arm64, no build path. Builds once when the xcframework is missing (minutes), then only checks.
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
X=$ROOT/Vendor/out/CQPDF.xcframework
[[ -f "$X/Info.plist" ]] || nice -n 10 "$ROOT/Vendor/build-native.sh" qpdf >/dev/null
assert_file "$X/Info.plist"
lib=$(find "$X" -name 'libCQPDF.a' | head -1); assert_file "$lib"
symbols=$(nm -gU "$lib" 2>/dev/null)
grep -q "QPDFWriter.*setR6EncryptionParameters" <<<"$symbols" || fail "QPDFWriter missing"
grep -q "QPDFCrypto_native" <<<"$symbols" || fail "the native crypto provider is missing"
grep -q "_jpeg_CreateDecompress" <<<"$symbols" || fail "libjpeg-turbo is not folded in"
if grep -qiE "QPDFCrypto_(openssl|gnutls)" <<<"$symbols"; then fail "an external crypto provider is built in"; fi
if strings -a "$lib" | grep -qE '/Users/|/private/tmp/|/var/folders/|/opt/homebrew'; then fail "path leak"; fi
headers=$(find "$X" -type d -name Headers | head -1)
assert_file "$headers/CQPDF/qpdf/QPDF.hh"
assert_file "$headers/CQPDF/qpdf/QPDFWriter.hh"
assert_file "$ROOT/Vendor/out/CQPDF.sha256"
lipo -archs "$lib" | grep -qx arm64 || fail "not arm64 only"
log=$(ls -t "$ROOT"/Vendor/logs/qpdf-build-*.log 2>/dev/null | head -1); assert_file "$log"
assert_contains "$(cat "$log")" "load average"
echo "PASS test-build-qpdf"
