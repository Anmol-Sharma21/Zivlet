#!/usr/bin/env bash
# Notarizes and staples a release file (P1-53). Credentials, one of:
#   ZIVLET_NOTARY_PROFILE                              a `notarytool store-credentials` keychain profile
#   NOTARY_KEY_ID + NOTARY_ISSUER_ID + NOTARY_KEY_PATH an App Store Connect API key (.p8)
# Submits with `notarytool submit --wait`, fails on any status but Accepted and prints the notary log, then staples
# and validates: the DMG itself, or for a zip the app it was made from, which Gatekeeper must then call
# "Notarized Developer ID". Without credentials: exit 3 naming owner step O-1.
# Usage: Scripts/notarize.sh <file.dmg>  |  Scripts/notarize.sh <file.zip> <Zivlet.app>
set -euo pipefail
OWNER_STEP="Notarization needs the owner's Developer ID and notary key (owner step O-1)."
FILE=${1:?usage: notarize.sh <file.dmg> | notarize.sh <file.zip> <Zivlet.app>}
APP=${2:-}

[[ -f "$FILE" ]] || { echo "error: $FILE not found" >&2; exit 1; }
case "$FILE" in
    *.dmg) STAPLE=$FILE ;;
    *.zip)
        [[ -d "$APP/Contents" ]] || { echo "error: a zip needs the app it was made from, to staple" >&2; exit 2; }
        STAPLE=$APP
        ;;
    *) echo "error: notarize a .dmg or a .zip, not $FILE" >&2; exit 2 ;;
esac

# Sets CREDS to notarytool's credential arguments, or exits 3.
credentials() {
    if [[ -n "${ZIVLET_NOTARY_PROFILE:-}" ]]; then
        CREDS=(--keychain-profile "$ZIVLET_NOTARY_PROFILE")
    elif [[ -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" && -f "${NOTARY_KEY_PATH:-}" ]]; then
        CREDS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
    else
        echo "$OWNER_STEP" >&2
        exit 3
    fi
}

json_field() { plutil -extract "$1" raw -o - -- - 2>/dev/null <<<"$2" || true; }

credentials
echo "Submitting $(basename "$FILE") for notarization (this waits for Apple's answer)"
result=$(xcrun notarytool submit "$FILE" "${CREDS[@]}" --wait --output-format json) || true
status=$(json_field status "$result")
id=$(json_field id "$result")
if [[ "$status" != "Accepted" ]]; then
    echo "error: notarization status ${status:-unknown} for $(basename "$FILE"): $result" >&2
    if [[ -n "$id" ]]; then xcrun notarytool log "$id" "${CREDS[@]}" >&2 || true; fi
    exit 1
fi
xcrun stapler staple "$STAPLE" || { echo "error: stapling $STAPLE failed" >&2; exit 1; }
xcrun stapler validate "$STAPLE" || { echo "error: the staple on $STAPLE does not validate" >&2; exit 1; }
if [[ "$STAPLE" == "$APP" ]]; then
    verdict=$(spctl -a -vv -t exec "$APP" 2>&1 || true)
    grep -q "source=Notarized Developer ID" <<<"$verdict" ||
        { echo "error: Gatekeeper does not accept $APP as notarized: $verdict" >&2; exit 1; }
fi
echo "Notarized and stapled $(basename "$STAPLE") (submission $id)"
