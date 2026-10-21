#!/usr/bin/env bash
# Xcode post-build phase of target Zivlet (P1-50, D-M4-10, D-M4-11):
#   Contents/Frameworks/Sparkle.framework           -> trimmed (no XPC services, arm64 only; Scripts/trim-sparkle.sh)
#   Vendor/out/media-stage/Helpers/{ffmpeg,ffprobe} -> Contents/Helpers/
#   Vendor/out/media-stage/Frameworks/*.dylib      -> Contents/Frameworks/
#   Vendor/out/licenses/                            -> Contents/Resources/Licenses/   (when collected, A13)
# then signs everything nested with Scripts/sign-app.sh --nested-only; Xcode signs the app itself afterwards.
# Without a stage, Release fails and Debug warns: a Debug app still finds ZIVLET_FFMPEG_DIR or Homebrew (D-M3-19).
# Release embeds a stage only when its KEY stamp equals `Vendor/cache-key.sh media` and it passes
# Vendor/verify-media.sh, so a stage from another build or a cache is never signed as it came.
set -euo pipefail
: "${SRCROOT:?run from Xcode}" "${TARGET_BUILD_DIR:?}" "${CONTENTS_FOLDER_PATH:?}" "${CONFIGURATION:?}"
STAGE=$SRCROOT/Vendor/out/media-stage
LICENSES=$SRCROOT/Vendor/out/licenses
CONTENTS=$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH
IDENTITY=${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}
MESSAGE="Media helpers are missing: run make vendor"

if [[ -d "$CONTENTS/Frameworks/Sparkle.framework" ]]; then
    "$SRCROOT/Scripts/trim-sparkle.sh" "$CONTENTS/Frameworks/Sparkle.framework"
fi

# Release only: the stage must come from the current inputs and pass the media gate before it is signed.
check_release_stage() {
    local want
    want=$("$SRCROOT/Vendor/cache-key.sh" media)
    if [[ "$(tr -d '[:space:]' <"$STAGE/KEY" 2>/dev/null)" != "$want" ]]; then
        echo "error: the media stage was not built from the current inputs: run make vendor" >&2
        exit 1
    fi
    "$SRCROOT/Vendor/verify-media.sh" "$STAGE" || { echo "error: the media stage failed verify-media.sh" >&2; exit 1; }
}

if [[ -x "$STAGE/Helpers/ffmpeg" && -x "$STAGE/Helpers/ffprobe" ]]; then
    if [[ "$CONFIGURATION" == "Release" ]]; then check_release_stage; fi
    mkdir -p "$CONTENTS/Helpers" "$CONTENTS/Frameworks"
    ditto "$STAGE/Helpers" "$CONTENTS/Helpers"
    ditto "$STAGE/Frameworks" "$CONTENTS/Frameworks"
    if [[ -d "$LICENSES" ]]; then ditto "$LICENSES" "$CONTENTS/Resources/Licenses"; fi
    echo "Embedded media helpers from $STAGE"
elif [[ "$CONFIGURATION" == "Release" ]]; then
    echo "error: $MESSAGE" >&2
    exit 1
else
    echo "warning: $MESSAGE (this Debug app uses ZIVLET_FFMPEG_DIR or Homebrew instead)"
fi

# One signing path for Xcode builds and the release pipeline (D-M4-10): libraries, helpers, frameworks, inside-out.
"$SRCROOT/Scripts/sign-app.sh" --nested-only "$IDENTITY" "$(dirname "$CONTENTS")" >/dev/null
echo "Signed the nested code with ${IDENTITY}"
