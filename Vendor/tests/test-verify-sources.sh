#!/usr/bin/env bash
# verify-sources.sh checks each source that upstream signs against its detached OpenPGP signature, made by the key
# whose fingerprint Vendor/signatures.lock pins (the key itself is committed under Vendor/keys). A tampered tarball
# or another signer fails. Runs with a throwaway key and file:// URLs.
source "$(dirname "$0")/lib.sh"
command -v gpg >/dev/null || { echo "SKIP test-verify-sources (gpg not installed; brew install gnupg)"; exit 0; }
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
export GNUPGHOME=$T/signer; mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --pinentry-mode loopback --passphrase '' --quick-gen-key "Test Signer <test@example.invalid>" \
    ed25519 sign never 2>/dev/null
fpr=$(gpg --batch --with-colons --list-keys | awk -F: '/^fpr/ { print $10; exit }')
mkdir -p "$T/keys" "$T/dl/pkg-1.0" "$T/srv"
gpg --batch --armor --export "$fpr" >"$T/keys/pkg.asc"
echo payload >"$T/srv/pkg-1.0.tar.gz"
gpg --batch --pinentry-mode loopback --passphrase '' --armor --detach-sign -o "$T/srv/pkg-1.0.tar.gz.asc" \
    "$T/srv/pkg-1.0.tar.gz"
cp "$T/srv/pkg-1.0.tar.gz" "$T/dl/pkg-1.0/"
echo "pkg 1.0 file://$T/srv/pkg-1.0.tar.gz sha256:$(shasum -a 256 "$T/srv/pkg-1.0.tar.gz" | cut -d' ' -f1)" >"$T/versions.lock"
echo "pkg file://$T/srv/pkg-1.0.tar.gz.asc $fpr" >"$T/signatures.lock"
unset GNUPGHOME
verify() {
    "$ROOT/Vendor/verify-sources.sh" --lock "$T/versions.lock" --signatures "$1" --keys "$T/keys" --downloads "$T/dl"
}

out=$(verify "$T/signatures.lock" 2>&1) || fail "a good signature was refused: $out"
assert_contains "$out" "pkg 1.0 signed by $fpr"

echo "pkg file://$T/srv/pkg-1.0.tar.gz.asc $(printf 'A%.0s' {1..40})" >"$T/other-signer.lock"
assert_fails verify "$T/other-signer.lock"

echo tampered >"$T/dl/pkg-1.0/pkg-1.0.tar.gz"
assert_fails verify "$T/signatures.lock"

# The committed pins: every signed source has its key, and the key's fingerprint is the pinned one.
while read -r name _ pinned; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    key=$ROOT/Vendor/keys/$name.asc; assert_file "$key"
    got=$(gpg --batch --with-colons --show-keys "$key" 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')
    assert_eq "$got" "$pinned" "fingerprint of $key"
done <"$ROOT/Vendor/signatures.lock"
grep -q '^ffmpeg ' "$ROOT/Vendor/signatures.lock" || fail "ffmpeg is not signature-checked"
grep -q '^libwebp ' "$ROOT/Vendor/signatures.lock" || fail "libwebp is not signature-checked"
echo "PASS test-verify-sources"
