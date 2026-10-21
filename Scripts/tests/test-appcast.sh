#!/usr/bin/env bash
# make-appcast.sh stops with the owner steps when the Sparkle key (O-2) or the download location (O-3) is missing;
# with a throwaway key (never in a keychain) and two small DMGs it writes a valid appcast whose items and delta are
# EdDSA-signed and whose newest item embeds its release notes; an app without SUPublicEDKey is refused.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
APPCAST=$ROOT/Scripts/make-appcast.sh
PREFIX=https://downloads.example.org/zivlet/
clean_env() { env -u SPARKLE_ED_PRIVATE_KEY -u ZIVLET_SPARKLE_ACCOUNT -u ZIVLET_DOWNLOAD_URL_PREFIX "$@"; }

# A throwaway Ed25519 key: a random 32-byte seed (Sparkle's key file format) and its public half from CryptoKit.
head -c 32 /dev/urandom | base64 >"$T/key"
cat >"$T/pub.swift" <<'EOF'
import CryptoKit
import Foundation
let seed = Data(base64Encoded: (readLine() ?? "").trimmingCharacters(in: .whitespaces)) ?? Data()
guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else { exit(1) }
print(key.publicKey.rawRepresentation.base64EncodedString())
EOF
PUBLIC=$(swift "$T/pub.swift" <"$T/key") || fail "cannot derive the public key"

fake_dmg() { # <dir> <short version> <build> [public key]
    local app=$T/apps-$3-${4:+k}/Zivlet.app
    mkdir -p "$app/Contents/MacOS"
    printf '#!/bin/sh\necho %s\n' "$2" >"$app/Contents/MacOS/Zivlet"; chmod +x "$app/Contents/MacOS/Zivlet"
    plutil -create xml1 "$app/Contents/Info.plist"
    for kv in "CFBundleIdentifier=app.zivlet.Zivlet" "CFBundleExecutable=Zivlet" "CFBundlePackageType=APPL" \
        "CFBundleShortVersionString=$2" "CFBundleVersion=$3" "LSMinimumSystemVersion=26.0" ${4:+"SUPublicEDKey=$4"}; do
        plutil -insert "${kv%%=*}" -string "${kv#*=}" "$app/Contents/Info.plist"
    done
    codesign --force --sign - "$app" 2>/dev/null
    ZIVLET_RELEASE_DIR=$1 "$ROOT/Scripts/make-dmg.sh" "$app" "$2" >/dev/null
}
mkdir -p "$T/notes"
printf '# Zivlet 0.1.1\n\n- A test note in our own words.\n' >"$T/notes/0.1.1.md"
fake_dmg "$T/rel" 0.1.0 1 "$PUBLIC"
fake_dmg "$T/rel" 0.1.1 2 "$PUBLIC"

set +e; out=$(clean_env ZIVLET_DOWNLOAD_URL_PREFIX=$PREFIX "$APPCAST" "$T/rel" 2>&1); code=$?; set -e
assert_eq "$code" "3" "exit code without a key"
assert_contains "$out" "Signing the appcast needs the owner's Sparkle key (owner step O-2)."
set +e; out=$(clean_env SPARKLE_ED_PRIVATE_KEY="$(cat "$T/key")" "$APPCAST" "$T/rel" 2>&1); code=$?; set -e
assert_eq "$code" "3" "exit code without a download location"
assert_contains "$out" "owner step O-3"
assert_fails clean_env SPARKLE_ED_PRIVATE_KEY="$(cat "$T/key")" ZIVLET_DOWNLOAD_URL_PREFIX=http://x.example/ \
    "$APPCAST" "$T/rel"

out=$(clean_env SPARKLE_ED_PRIVATE_KEY="$(cat "$T/key")" ZIVLET_DOWNLOAD_URL_PREFIX=$PREFIX \
    ZIVLET_RELEASE_NOTES_DIR="$T/notes" "$APPCAST" "$T/rel" 2>&1) || fail "appcast failed: $out"
XML=$T/rel/appcast.xml
xmllint --noout "$XML" || fail "appcast.xml is not well-formed XML"
assert_eq "$(xmllint --xpath 'count(/rss/channel/item)' "$XML")" "2" "items"
assert_eq "$(xmllint --xpath 'count(/rss/channel/item/enclosure[@*[local-name()="edSignature"]])' "$XML")" "2" \
    "signed enclosures"
assert_eq "$(xmllint --xpath 'count(//*[local-name()="deltas"]/enclosure[@*[local-name()="edSignature"]])' "$XML")" \
    "1" "signed deltas"
assert_contains "$(cat "$XML")" "A test note in our own words."
assert_contains "$(cat "$XML")" "${PREFIX}Zivlet-0.1.1.dmg"
if grep -q "<sparkle:channel>" "$XML"; then fail "stable is Sparkle's default channel; no channel element expected"; fi
signature=$(xmllint --xpath 'string(/rss/channel/item[1]/enclosure/@*[local-name()="edSignature"])' "$XML")
"$ROOT/Vendor/out/sparkle-tools/bin/sign_update" --verify --ed-key-file "$T/key" "$T/rel/Zivlet-0.1.1.dmg" \
    "$signature" >/dev/null 2>&1 || fail "the DMG signature does not verify with the throwaway key"

# An app without the public key would give an unsigned feed: refused.
fake_dmg "$T/nokey" 0.2.0 3
out=$(clean_env SPARKLE_ED_PRIVATE_KEY="$(cat "$T/key")" ZIVLET_DOWNLOAD_URL_PREFIX=$PREFIX "$APPCAST" "$T/nokey" \
    2>&1 || true)
assert_contains "$out" "SUPublicEDKey"
assert_fails clean_env SPARKLE_ED_PRIVATE_KEY="$(cat "$T/key")" ZIVLET_DOWNLOAD_URL_PREFIX=$PREFIX \
    "$APPCAST" "$T/nokey"
mkdir -p "$T/empty"
assert_fails clean_env SPARKLE_ED_PRIVATE_KEY="$(cat "$T/key")" ZIVLET_DOWNLOAD_URL_PREFIX=$PREFIX "$APPCAST" "$T/empty"
echo "PASS test-appcast"
