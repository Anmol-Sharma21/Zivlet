#!/usr/bin/env bash
# Xcode post-build phase of target Zivlet (P1-50, D-M4-10): copies the vendored media stage into the app,
#   Vendor/out/media-stage/Helpers/{ffmpeg,ffprobe} -> Contents/Helpers/
#   Vendor/out/media-stage/Frameworks/*.dylib      -> Contents/Frameworks/
#   Vendor/out/licenses/                            -> Contents/Resources/Licenses/   (when collected, A13)
# then signs the copies inside-out with the build's identity; Xcode signs the app itself afterwards.
# Without a stage, Release fails and Debug warns: a Debug app still finds ZIVLET_FFMPEG_DIR or Homebrew (D-M3-19).
set -euo pipefail
: "${SRCROOT:?run from Xcode}" "${TARGET_BUILD_DIR:?}" "${CONTENTS_FOLDER_PATH:?}" "${CONFIGURATION:?}"
STAGE=$SRCROOT/Vendor/out/media-stage
LICENSES=$SRCROOT/Vendor/out/licenses
CONTENTS=$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH
IDENTITY=${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}
MESSAGE="Media helpers are missing: run make vendor"

if [[ ! -x "$STAGE/Helpers/ffmpeg" || ! -x "$STAGE/Helpers/ffprobe" ]]; then
    if [[ "$CONFIGURATION" == "Release" ]]; then echo "error: $MESSAGE" >&2; exit 1; fi
    echo "warning: $MESSAGE (this Debug app uses ZIVLET_FFMPEG_DIR or Homebrew instead)"
    exit 0
fi

mkdir -p "$CONTENTS/Helpers" "$CONTENTS/Frameworks"
ditto "$STAGE/Helpers" "$CONTENTS/Helpers"
ditto "$STAGE/Frameworks" "$CONTENTS/Frameworks"
if [[ -d "$LICENSES" ]]; then ditto "$LICENSES" "$CONTENTS/Resources/Licenses"; fi

# Libraries first, then the helpers that load them (inside-out). Ad-hoc helpers need library validation off,
# because ad-hoc files have no Team ID to match (Config/HelperAdHoc.entitlements).
# Extra flags go in plain strings because bash 3.2 (the macOS /bin/bash) rejects empty arrays under set -u.
lib_flags="--options runtime"; helper_flags="--options runtime"
if [[ "$IDENTITY" == "-" ]]; then
    helper_flags="$helper_flags --entitlements $SRCROOT/Config/HelperAdHoc.entitlements"
else
    lib_flags="$lib_flags --timestamp"; helper_flags="$helper_flags --timestamp"
fi
sign() { codesign --force --sign "$IDENTITY" "$@" 2>&1 | { grep -v "replacing existing signature" || true; }; }
for lib in "$CONTENTS"/Frameworks/lib*.dylib; do
    # shellcheck disable=SC2086 # fixed flag words
    sign $lib_flags "$lib"
done
for helper in ffmpeg ffprobe; do
    # shellcheck disable=SC2086
    sign $helper_flags --identifier "app.zivlet.helper.$helper" "$CONTENTS/Helpers/$helper"
done
echo "Embedded media helpers from $STAGE (signed with ${IDENTITY})"
