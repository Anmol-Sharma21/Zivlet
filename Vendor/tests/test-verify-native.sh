#!/usr/bin/env bash
# verify-native.sh refuses a static archive with a slice other than arm64, an object built for another macOS than
# 26.0, a reference to OpenSSL or GnuTLS, no native crypto provider, or a build machine's path; a clean archive
# passes. The archives are made here from our own tiny C files.
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

cat >"$T/provider.c" <<'C'
int QPDFCrypto_native_present(void) { return 1; }
C
cat >"$T/crypto.c" <<'C'
extern void *EVP_CIPHER_CTX_new(void);
void *uses_openssl(void) { return EVP_CIPHER_CTX_new(); }
C
cat >"$T/path.c" <<'C'
const char *where = "/Users/x/build";
C
cat >"$T/plain.c" <<'C'
int plain(int a) { return a + 1; }
C

# archive <name> <arch> <minos> <c files...>: one object per file, merged into <name>.a.
archive() {
    local name=$1 arch=$2 minos=$3 objects=() file; shift 3
    for file in "$@"; do
        xcrun clang -c -arch "$arch" -mmacosx-version-min="$minos" -o "$T/$name-$(basename "$file" .c).o" "$T/$file"
        objects+=("$T/$name-$(basename "$file" .c).o")
    done
    xcrun libtool -static -o "$T/$name.a" "${objects[@]}" 2>/dev/null
}
verify() { "$ROOT/Vendor/verify-native.sh" --archive "$T/$1.a" 2>&1; }
refused() {
    local out; out=$(verify "$1") && fail "$1.a passed: $out"
    assert_contains "$out" "$2"
}

archive clean arm64 26.0 provider.c plain.c
out=$(verify clean) || fail "a clean arm64 26.0 archive was refused: $out"
assert_contains "$out" "clean.a: arm64, minos 26.0, native crypto only, no build paths"

# A real archive's symbol list is far bigger than a pipe buffer; the provider sorts first, so a check that stops
# reading at its first match would cut nm off (SIGPIPE under pipefail) and refuse a good archive.
for i in $(seq 1 4000); do echo "int padding_symbol_with_a_long_name_for_the_listing_$i(void) { return $i; }"; done \
    >"$T/many.c"
archive big arm64 26.0 provider.c many.c
out=$(verify big) || fail "a clean archive with a long symbol list was refused: $out"

archive intel x86_64 26.0 provider.c plain.c
refused intel "not arm64 only"
archive old arm64 14.0 provider.c plain.c
refused old "minos 14.0"
archive openssl arm64 26.0 provider.c crypto.c
refused openssl "EVP_CIPHER_CTX_new"
archive noprovider arm64 26.0 plain.c
refused noprovider "no native crypto provider"
archive leak arm64 26.0 provider.c path.c
refused leak "build path"

assert_fails "$ROOT/Vendor/verify-native.sh" not-a-component
assert_fails "$ROOT/Vendor/verify-native.sh" --archive "$T/missing.a"
echo "PASS test-verify-native"
