#!/usr/bin/env bash
# embed-helpers.sh copies the media stage into the app. For Release it first checks that the stage was built from
# the current inputs (its KEY stamp equals cache-key.sh media) and passes verify-media.sh, so a stage restored from
# elsewhere is never signed. Runs against a stand-in source root.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
SRC=$T/src
mkdir -p "$SRC/Vendor/out/media-stage/Helpers" "$SRC/Vendor/out/media-stage/Frameworks" "$SRC/Scripts" \
    "$T/build/Zivlet.app/Contents"
cp "$ROOT/Scripts/embed-helpers.sh" "$SRC/Scripts/"
printf '#!/usr/bin/env bash\necho fake\n' >"$SRC/Vendor/out/media-stage/Helpers/ffmpeg"
cp "$SRC/Vendor/out/media-stage/Helpers/ffmpeg" "$SRC/Vendor/out/media-stage/Helpers/ffprobe"
chmod +x "$SRC/Vendor/out/media-stage/Helpers/"*
printf '#!/usr/bin/env bash\necho "%s"\n' "1111111111111111111111111111111111111111111111111111111111111111" \
    >"$SRC/Vendor/cache-key.sh"
printf '#!/usr/bin/env bash\necho "$1" >>"%s"\nexit "${VERIFY_EXIT:-0}"\n' "$T/verified" >"$SRC/Vendor/verify-media.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$SRC/Scripts/sign-app.sh"
chmod +x "$SRC/Vendor/cache-key.sh" "$SRC/Vendor/verify-media.sh" "$SRC/Scripts/sign-app.sh"
embed() {
    local configuration=$1; shift
    env SRCROOT="$SRC" TARGET_BUILD_DIR="$T/build" CONTENTS_FOLDER_PATH=Zivlet.app/Contents \
        CONFIGURATION="$configuration" CODE_SIGN_IDENTITY=- "$@" "$SRC/Scripts/embed-helpers.sh"
}
stamp() { echo "$1" >"$SRC/Vendor/out/media-stage/KEY"; }
helpers=$T/build/Zivlet.app/Contents/Helpers

stamp 0000000000000000000000000000000000000000000000000000000000000000
assert_fails embed Release
assert_no_file "$helpers/ffmpeg"
out=$(embed Debug 2>&1) || fail "Debug refused a stale stage: $out" # Debug builds keep working with any stage
assert_file "$helpers/ffmpeg"
mv "$helpers" "$T/debug-helpers"

stamp 1111111111111111111111111111111111111111111111111111111111111111
assert_fails embed Release VERIFY_EXIT=1
assert_no_file "$helpers/ffmpeg"
out=$(embed Release 2>&1) || fail "a current, verified stage was refused: $out"
assert_file "$helpers/ffmpeg"
assert_contains "$(cat "$T/verified")" "media-stage"
echo "PASS test-embed-helpers"
