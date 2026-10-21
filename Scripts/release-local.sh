#!/usr/bin/env bash
# The release workflow's steps on this Mac (make release-dry-run, P0-38): vendor outputs, licence gate, Release
# archive, signing, signature gate, notarization, DMG, size gate, corresponding source, SBOM, dSYMs and appcast, all
# written to build/release. Without --identity the app is signed ad-hoc and the owner steps are skipped with their
# messages: notarization (O-1) and the signed appcast (O-2, also skipped without SPARKLE_ED_PRIVATE_KEY).
# Usage: Scripts/release-local.sh <version> [--identity <Developer ID Application identity>]
set -euo pipefail
source "$(dirname "$0")/env.sh"
USAGE="usage: release-local.sh <version> [--identity <identity>]"
VERSION=${1:?$USAGE}
IDENTITY=-
if (($# > 1)); then
    [[ "$2" == "--identity" && $# -eq 3 && -n "$3" && "$3" != "-" ]] || { echo "error: $USAGE" >&2; exit 2; }
    IDENTITY=$3
fi
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] ||
    { echo "error: version must look like 1.2.3 or 1.2.3-alpha, got [$VERSION]" >&2; exit 2; }
RELEASE=${ZIVLET_RELEASE_DIR:-$REPO_ROOT/build/release}
APP=$RELEASE/work/Zivlet.app
DMG=$RELEASE/Zivlet-$VERSION.dmg
S=$REPO_ROOT/Scripts
step() { echo "==> $*"; }
signed() { [[ "$IDENTITY" != "-" ]]; }

step "Vendor outputs"; "$REPO_ROOT/Vendor/ensure-native.sh"; "$REPO_ROOT/Vendor/ensure-media.sh"
step "Licence gate"; "$S/licence-gate.sh"; "$S/collect-licences.sh"
step "Release archive"; "$S/release-build.sh" "$VERSION"
step "Sign ($IDENTITY)"; "$S/sign-app.sh" "$IDENTITY" "$APP"
step "Signature gate"
if signed; then "$S/verify-signatures.sh" "$APP" --require-developer-id; else "$S/verify-signatures.sh" "$APP"; fi
step "Notarize the app"
if signed; then
    rm -f "$RELEASE/work/Zivlet.zip"
    ditto -c -k --keepParent "$APP" "$RELEASE/work/Zivlet.zip"
    "$S/notarize.sh" "$RELEASE/work/Zivlet.zip" "$APP"
else
    echo "skipped: Notarization needs the owner's Developer ID and notary key (owner step O-1)."
fi
step "DMG"
if signed; then "$S/make-dmg.sh" "$APP" "$VERSION" --identity "$IDENTITY"; else "$S/make-dmg.sh" "$APP" "$VERSION"; fi
step "Notarize the DMG"
if signed; then "$S/notarize.sh" "$DMG"; else echo "skipped: owner step O-1 (as above)."; fi
step "Size gate"; "$S/size-gate.sh" "$APP" "$DMG"
step "Corresponding source"; "$S/source-bundle.sh" "$VERSION"
step "SBOM"; "$S/sbom.sh" "$VERSION"
step "Appcast"
if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}${ZIVLET_SPARKLE_ACCOUNT:-}" ]]; then
    mkdir -p "$RELEASE/appcast"
    cp "$DMG" "$RELEASE/appcast/"
    "$S/make-appcast.sh" "$RELEASE/appcast"
else
    echo "skipped: Signing the appcast needs the owner's Sparkle key (owner step O-2)."
fi
step "Release files in $RELEASE"
find "$RELEASE" -maxdepth 2 -type f \( -name "*$VERSION*" -o -name appcast.xml \) -exec du -h {} + | sort -k2
