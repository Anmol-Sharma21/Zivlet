#!/usr/bin/env bash
# Sparkle's release tools (generate_appcast, sign_update, generate_keys, BinaryDelta) from the pinned Sparkle tarball
# (Vendor/versions.lock): fetched and hash-checked by fetch.sh, then only its bin/ directory is extracted into
# Vendor/out/sparkle-tools/bin. Prints that directory. The app's framework comes from Sparkle's Swift package instead.
# Usage: Vendor/sparkle-tools.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ZIVLET_VENDOR_WORK:-$ROOT/Vendor}
OUT=$WORK/out/sparkle-tools
read -r _ version url hash < <(awk '$1 == "sparkle"' "$ROOT/Vendor/versions.lock")
[[ -n "${hash:-}" ]] || { echo "error: no sparkle line in Vendor/versions.lock" >&2; exit 1; }
STAMP=$OUT/.zivlet-sha256

if [[ -x "$OUT/bin/generate_appcast" && -f "$STAMP" && "$(cat "$STAMP")" == "$hash" ]]; then echo "$OUT/bin"; exit 0; fi
"$ROOT/Vendor/fetch.sh" --only sparkle >&2
TARBALL=$ROOT/Vendor/downloads/sparkle-$version/$(basename "$url")
[[ "sha256:$(shasum -a 256 "$TARBALL" | cut -d' ' -f1)" == "$hash" ]] ||
    { echo "error: $TARBALL does not match its pinned SHA-256" >&2; exit 1; }
mkdir -p "$WORK/out"
tmp=$(mktemp -d "$WORK/out/.sparkle-tools.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
tar -xf "$TARBALL" -C "$tmp" ./bin || { echo "error: cannot extract bin/ from $TARBALL" >&2; exit 1; }
echo "$hash" >"$tmp/.zivlet-sha256"
rm -rf "$OUT"
mv "$tmp" "$OUT"
trap - EXIT
echo "$OUT/bin"
