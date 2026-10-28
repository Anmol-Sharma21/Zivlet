#!/usr/bin/env bash
# Gate for the static PDF engine archive (P2-13, D-M7-16). Fails on: a slice other than arm64, an object whose
# LC_BUILD_VERSION minos is not 26.0 (or that has none), an undefined OpenSSL or GnuTLS symbol, no native crypto
# provider defined, or a string with a build machine's path. Prints one line per problem.
# Usage: Vendor/verify-native.sh CQPDF | --archive <lib.a>
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ZIVLET_VENDOR_WORK:-$ROOT/Vendor}
MACOS_MIN=26.0
EXTERNAL_CRYPTO='^_(EVP|SSL|OPENSSL|ERR|RAND|BIO|CRYPTO)_|^_gnutls_'
LEAK_PATTERN='/Users/|/private/tmp|/var/folders/|/opt/homebrew'

case "${1:-}" in
    CQPDF) ARCHIVE=$(find "$WORK/out/CQPDF.xcframework" -name libCQPDF.a 2>/dev/null | head -1) ;;
    --archive) ARCHIVE=${2:-} ;;
    *) echo "usage: verify-native.sh CQPDF | --archive <lib.a>" >&2; exit 2 ;;
esac
[[ -n "${ARCHIVE:-}" && -f "$ARCHIVE" ]] || { echo "verify-native: no archive for ${2:-$1}" >&2; exit 1; }
name=$(basename "$ARCHIVE")
problems=0
problem() { echo "verify-native: $name: $*" >&2; problems=1; }

archs=$(lipo -archs "$ARCHIVE" 2>/dev/null || true)
[[ "$archs" == arm64 ]] || problem "not arm64 only (slices: ${archs:-none})"

# One minos per object: LC_BUILD_VERSION's minos, or "none" for an object that lacks the command.
minos=$(otool -l "$ARCHIVE" | awk '
    /^.*\(.*\.o\):$/ { if (member != "") print (found ? found : "none"); member = $0; found = "" }
    /cmd LC_BUILD_VERSION/ { want = 1 }
    want && $1 == "minos" { found = $2; want = 0 }
    END { if (member != "") print (found ? found : "none") }' | sort -u)
for value in $minos; do
    [[ "$value" == "$MACOS_MIN" ]] || problem "an object has minos $value (want $MACOS_MIN)"
done

external=$(nm -u "$ARCHIVE" 2>/dev/null | grep -E "$EXTERNAL_CRYPTO" | sort -u | tr '\n' ' ' || true)
[[ -z "$external" ]] || problem "references OpenSSL or GnuTLS: $external"
nm -gU "$ARCHIVE" 2>/dev/null | grep -q "QPDFCrypto_native" || problem "no native crypto provider defined"

leaks=$(strings -a "$ARCHIVE" | grep -E "$LEAK_PATTERN" | head -3 | tr '\n' ' ' || true)
[[ -z "$leaks" ]] || problem "contains a build path: $leaks"

((problems == 0)) || exit 1
echo "$name: arm64, minos $MACOS_MIN, native crypto only, no build paths"
