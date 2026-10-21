#!/usr/bin/env bash
# notarize.sh stops with the O-1 message without credentials, prints the notary log and fails on any status but
# Accepted, and staples and validates on success (the DMG, or the app for a zip). xcrun and spctl are fakes on PATH.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/Zivlet.app/Contents"
cat >"$T/bin/xcrun" <<'EOF'
#!/bin/sh
echo "xcrun $*" >>"$FAKE_CALLS"
case "$1 $2" in
    "notarytool submit") printf '{"id":"0f0e","status":"%s","message":"done"}\n' "$FAKE_STATUS" ;;
    "notarytool log") echo '{"issues":[{"message":"fake issue"}]}' ;;
    stapler*) echo "The staple and validate action worked!" ;;
esac
EOF
cat >"$T/bin/spctl" <<'EOF'
#!/bin/sh
echo "spctl $*" >>"$FAKE_CALLS"
echo "$FAKE_SPCTL" >&2
EOF
chmod +x "$T/bin/xcrun" "$T/bin/spctl"
touch "$T/Zivlet-0.1.0.dmg" "$T/Zivlet.zip"
export FAKE_CALLS=$T/calls PATH="$T/bin:$PATH"
NOTARIZE=$ROOT/Scripts/notarize.sh
clean_env() { env -u ZIVLET_NOTARY_PROFILE -u NOTARY_KEY_ID -u NOTARY_ISSUER_ID -u NOTARY_KEY_PATH "$@"; }

# No credentials: exit 3 with the owner step.
set +e; out=$(clean_env "$NOTARIZE" "$T/Zivlet-0.1.0.dmg" 2>&1); code=$?; set -e
assert_eq "$code" "3" "exit code without credentials"
assert_contains "$out" "Notarization needs the owner's Developer ID and notary key (owner step O-1)."
# Half an API key is no key.
set +e; clean_env NOTARY_KEY_ID=ABC "$NOTARIZE" "$T/Zivlet-0.1.0.dmg" >/dev/null 2>&1; code=$?; set -e
assert_eq "$code" "3" "exit code with a partial API key"

# Invalid: exit 1, and the log is fetched and printed.
: >"$FAKE_CALLS"
set +e; out=$(clean_env ZIVLET_NOTARY_PROFILE=zivlet-notary FAKE_STATUS=Invalid "$NOTARIZE" "$T/Zivlet-0.1.0.dmg" 2>&1)
code=$?; set -e
assert_eq "$code" "1" "exit code for Invalid"
assert_contains "$out" "fake issue"
assert_contains "$(cat "$FAKE_CALLS")" "notarytool log 0f0e --keychain-profile zivlet-notary"
assert_contains "$(cat "$FAKE_CALLS")" "--wait --output-format json"
if grep -q stapler "$FAKE_CALLS"; then fail "stapled after Invalid"; fi

# Accepted DMG: stapled and validated.
: >"$FAKE_CALLS"
out=$(clean_env ZIVLET_NOTARY_PROFILE=zivlet-notary FAKE_STATUS=Accepted "$NOTARIZE" "$T/Zivlet-0.1.0.dmg" 2>&1) ||
    fail "Accepted DMG failed: $out"
assert_contains "$(cat "$FAKE_CALLS")" "stapler staple $T/Zivlet-0.1.0.dmg"
assert_contains "$(cat "$FAKE_CALLS")" "stapler validate $T/Zivlet-0.1.0.dmg"

# Accepted zip with an API key: the app is stapled and Gatekeeper must call it notarized.
touch "$T/AuthKey_TEST.p8"
api=(NOTARY_KEY_ID=KEY1 NOTARY_ISSUER_ID=ISSUER1 NOTARY_KEY_PATH="$T/AuthKey_TEST.p8" FAKE_STATUS=Accepted)
: >"$FAKE_CALLS"
out=$(clean_env "${api[@]}" FAKE_SPCTL="source=Notarized Developer ID" "$NOTARIZE" "$T/Zivlet.zip" "$T/Zivlet.app" \
    2>&1) ||
    fail "Accepted zip failed: $out"
assert_contains "$(cat "$FAKE_CALLS")" "--key $T/AuthKey_TEST.p8 --key-id KEY1 --issuer ISSUER1"
assert_contains "$(cat "$FAKE_CALLS")" "stapler staple $T/Zivlet.app"
assert_contains "$(cat "$FAKE_CALLS")" "spctl -a -vv -t exec $T/Zivlet.app"
assert_fails clean_env "${api[@]}" FAKE_SPCTL="source=Developer ID" "$NOTARIZE" "$T/Zivlet.zip" "$T/Zivlet.app"

# Refusals: a zip needs the app to staple, a missing file, another file type, a missing key file.
assert_fails clean_env "${api[@]}" "$NOTARIZE" "$T/Zivlet.zip"
assert_fails clean_env "${api[@]}" "$NOTARIZE" "$T/missing.dmg"
touch "$T/Zivlet.pkg"; assert_fails clean_env "${api[@]}" "$NOTARIZE" "$T/Zivlet.pkg"
set +e; clean_env NOTARY_KEY_ID=K NOTARY_ISSUER_ID=I NOTARY_KEY_PATH="$T/none.p8" "$NOTARIZE" "$T/Zivlet-0.1.0.dmg" \
    >/dev/null 2>&1; code=$?; set -e
assert_eq "$code" "3" "exit code with a missing key file"
echo "PASS test-notarize"
