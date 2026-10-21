#!/usr/bin/env bash
# Checks each source that upstream signs (Vendor/signatures.lock: name, detached-signature URL, signer fingerprint)
# against its OpenPGP signature, using only the committed key Vendor/keys/<name>.asc in a throwaway keyring. Run it
# when a pin in versions.lock changes, after fetch.sh has verified the SHA-256 (the signature is the second,
# independent check; Vendor/PROVENANCE.md records the result). Needs gpg (Homebrew gnupg).
# Usage: Vendor/verify-sources.sh [--lock FILE] [--signatures FILE] [--keys DIR] [--downloads DIR]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOCK=$ROOT/Vendor/versions.lock; SIGNATURES=$ROOT/Vendor/signatures.lock; KEYS=$ROOT/Vendor/keys
DOWNLOADS=$ROOT/Vendor/downloads
while (($#)); do
    case "$1" in
        --lock) LOCK=$2; shift 2 ;;
        --signatures) SIGNATURES=$2; shift 2 ;;
        --keys) KEYS=$2; shift 2 ;;
        --downloads) DOWNLOADS=$2; shift 2 ;;
        *) echo "error: unknown argument $1" >&2; exit 2 ;;
    esac
done
command -v gpg >/dev/null || { echo "error: gpg not found (brew install gnupg)" >&2; exit 1; }
RING=$(mktemp -d "${TMPDIR:-/tmp}/zivlet-keyring.XXXXXX"); chmod 700 "$RING"
trap 'rm -rf "$RING"' EXIT

problems=0
while read -r name url fingerprint extra; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    [[ -z "${extra:-}" && "$fingerprint" =~ ^[0-9A-F]{40}$ && "$url" =~ ^(https|file):// ]] ||
        { echo "error: $SIGNATURES: bad line for $name" >&2; exit 2; }
    read -r _ version source _ < <(awk -v n="$name" '$1 == n { print; exit }' "$LOCK")
    [[ -n "${version:-}" ]] || { echo "error: $name is not in $LOCK" >&2; exit 2; }
    tarball=$DOWNLOADS/$name-$version/$(basename "${source%%\?*}")
    [[ -f "$tarball" ]] || { echo "error: $tarball missing: run Vendor/fetch.sh first" >&2; exit 1; }
    signature=$DOWNLOADS/signatures/$(basename "${url%%\?*}")
    mkdir -p "$DOWNLOADS/signatures"
    curl -fsSL --retry 3 --proto '=https,file' -o "$signature" "$url" ||
        { echo "error: no signature for $name at $url" >&2; exit 1; }
    gpg --homedir "$RING" --batch --quiet --import "$KEYS/$name.asc" 2>/dev/null
    status=$(gpg --homedir "$RING" --batch --status-fd 1 --verify "$signature" "$tarball" 2>/dev/null || true)
    if grep -q "^\[GNUPG:\] VALIDSIG $fingerprint " <<<"$status"; then
        echo "$name $version signed by $fingerprint"
    else
        echo "error: $name $version: no valid signature by $fingerprint" >&2
        problems=1
    fi
done <"$SIGNATURES"
exit "$problems"
