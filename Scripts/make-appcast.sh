#!/usr/bin/env bash
# Sparkle appcast for the DMGs in a directory (P1-53): Sparkle's generate_appcast from the pinned tarball
# (Vendor/sparkle-tools.sh) writes <dir>/appcast.xml with EdDSA-signed items, deltas against the previous two
# versions present, and the release notes of each version (docs/release-notes/<version>.md, copied next to its DMG
# and embedded as Markdown). "Stable" is Sparkle's default channel, so items carry no channel element.
#   SPARKLE_ED_PRIVATE_KEY      the private EdDSA key (passed on standard input), or
#   ZIVLET_SPARKLE_ACCOUNT      a keychain account holding it on the release runner        (owner step O-2)
#   ZIVLET_DOWNLOAD_URL_PREFIX  https:// location the DMGs are downloaded from              (owner step O-3)
# Fails if any item is unsigned (the app lacks SUPublicEDKey). Without a key or location: exit 3.
# Usage: Scripts/make-appcast.sh <dir-with-dmgs>
set -euo pipefail
source "$(dirname "$0")/env.sh"
DIR=${1:?usage: make-appcast.sh <dir-with-dmgs>}
NOTES=${ZIVLET_RELEASE_NOTES_DIR:-$REPO_ROOT/docs/release-notes}
MAX_DELTAS=2

[[ -d "$DIR" ]] || { echo "error: $DIR is not a directory" >&2; exit 1; }
dmgs=$(find "$DIR" -maxdepth 1 -name 'Zivlet-*.dmg' | sort)
[[ -n "$dmgs" ]] || { echo "error: no Zivlet-<version>.dmg in $DIR" >&2; exit 1; }
if [[ -z "${SPARKLE_ED_PRIVATE_KEY:-}" && -z "${ZIVLET_SPARKLE_ACCOUNT:-}" ]]; then
    echo "Signing the appcast needs the owner's Sparkle key (owner step O-2)." >&2
    exit 3
fi
PREFIX=${ZIVLET_DOWNLOAD_URL_PREFIX:-}
if [[ -z "$PREFIX" ]]; then
    echo "The appcast needs the owner's download location, ZIVLET_DOWNLOAD_URL_PREFIX (owner step O-3)." >&2
    exit 3
fi
[[ "$PREFIX" =~ ^https://[^/[:space:]]+(/[^[:space:]]*)?$ ]] ||
    { echo "error: ZIVLET_DOWNLOAD_URL_PREFIX must be an https:// URL, got [$PREFIX]" >&2; exit 2; }
[[ "$PREFIX" == */ ]] || PREFIX="$PREFIX/"

TOOLS=$("$REPO_ROOT/Vendor/sparkle-tools.sh")
while IFS= read -r dmg; do
    version=$(basename "$dmg" .dmg); version=${version#Zivlet-}
    notes=$DIR/Zivlet-$version.md
    if [[ -f "$NOTES/$version.md" && ! -f "$notes" ]]; then cp "$NOTES/$version.md" "$notes"; fi
done <<<"$dmgs"

ARGS=(--download-url-prefix "$PREFIX" --embed-release-notes --maximum-deltas "$MAX_DELTAS")
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
    printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY" | "$TOOLS/generate_appcast" --ed-key-file - "${ARGS[@]}" "$DIR"
else
    "$TOOLS/generate_appcast" --account "$ZIVLET_SPARKLE_ACCOUNT" "${ARGS[@]}" "$DIR"
fi

XML=$DIR/appcast.xml
xmllint --noout "$XML" || { echo "error: $XML is not well-formed" >&2; exit 1; }
items=$(xmllint --xpath 'count(//enclosure)' "$XML")
signed=$(xmllint --xpath 'count(//enclosure[@*[local-name()="edSignature"]])' "$XML")
if [[ "$items" != "$signed" || "$items" == "0" ]]; then
    echo "error: $((items - signed)) of $items appcast enclosures are unsigned; Sparkle signs only apps whose" \
        "Info.plist has SUPublicEDKey (owner step O-2)" >&2
    exit 1
fi
echo "Appcast: $XML ($(xmllint --xpath 'count(/rss/channel/item)' "$XML") items, $signed signed enclosures)"
