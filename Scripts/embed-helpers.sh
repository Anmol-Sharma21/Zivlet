#!/usr/bin/env bash
# Xcode post-build phase of target Zivlet (P1-50, D-M4-10): copies the vendored media stage into the app,
#   Vendor/out/media-stage/Helpers/{ffmpeg,ffprobe} -> Contents/Helpers/
#   Vendor/out/media-stage/Frameworks/*.dylib      -> Contents/Frameworks/
#   Vendor/out/licenses/                            -> Contents/Resources/Licenses/   (when collected, A13)
# then signs the copies with Scripts/sign-app.sh --helpers-only; Xcode signs the app itself afterwards.
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

# One signing path for Xcode builds and the release pipeline (D-M4-10): libraries, then helpers, inside-out.
"$SRCROOT/Scripts/sign-app.sh" --helpers-only "$IDENTITY" "$(dirname "$CONTENTS")" >/dev/null
echo "Embedded media helpers from $STAGE (signed with ${IDENTITY})"
