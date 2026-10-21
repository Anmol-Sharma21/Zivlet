#!/usr/bin/env bash
# Signs Zivlet.app inside-out (P0-38, 11 §7.2): libraries in Contents/Frameworks, then the helpers in
# Contents/Helpers (identifier app.zivlet.helper.<name>), then nested frameworks (their inner bundles and
# executables first), then the app with Config/Zivlet.entitlements. Always the hardened runtime; a secure timestamp
# when the identity is a real certificate. Ad-hoc helpers also get Config/HelperAdHoc.entitlements, because library
# validation cannot match the Team ID of ad-hoc files (they have none).
# Usage: Scripts/sign-app.sh [--helpers-only] <identity|-> <Zivlet.app>
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HELPERS_ONLY=0
if [[ "${1:-}" == "--helpers-only" ]]; then HELPERS_ONLY=1; shift; fi
IDENTITY=${1:?usage: sign-app.sh [--helpers-only] <identity|-> <app>}
APP=${2:?usage: sign-app.sh [--helpers-only] <identity|-> <app>}
CONTENTS=$APP/Contents
[[ -d "$CONTENTS" ]] || { echo "error: $APP is not an app bundle" >&2; exit 1; }

# Plain strings, not arrays: bash 3.2 (macOS /bin/bash) rejects empty arrays under set -u.
FLAGS="--force --options runtime"
[[ "$IDENTITY" != "-" ]] && FLAGS="$FLAGS --timestamp"
HELPER_FLAGS=""
[[ "$IDENTITY" == "-" ]] && HELPER_FLAGS="--entitlements $ROOT/Config/HelperAdHoc.entitlements"

sign() {
    local out
    # shellcheck disable=SC2086 # FLAGS holds fixed flag words
    if ! out=$(codesign $FLAGS --sign "$IDENTITY" "$@" 2>&1); then
        echo "error: codesign failed for ${*: -1}: $out" >&2
        exit 1
    fi
}

sign_libraries() {
    local lib
    for lib in "$CONTENTS"/Frameworks/*.dylib; do [[ -f "$lib" ]] && sign "$lib"; done
    return 0
}

sign_helpers() {
    local helper
    for helper in "$CONTENTS"/Helpers/*; do
        [[ -f "$helper" ]] || continue
        # shellcheck disable=SC2086
        sign $HELPER_FLAGS --identifier "app.zivlet.helper.$(basename "$helper")" "$helper"
    done
}

# Nested bundles (deepest first), then loose executables inside the framework, then the framework itself.
sign_frameworks() {
    local framework nested
    for framework in "$CONTENTS"/Frameworks/*.framework; do
        [[ -d "$framework" ]] || continue
        while IFS= read -r nested; do sign "$nested"; done < <(
            find "$framework" -depth \( -name '*.xpc' -o -name '*.app' \) -type d)
        while IFS= read -r nested; do sign "$nested"; done < <(
            find "$framework/Versions" -type f -perm -u+x ! -path '*.xpc/*' ! -path '*.app/*' \
                ! -name "$(basename "$framework" .framework)" 2>/dev/null)
        sign "$framework"
    done
}

sign_libraries
sign_helpers
if ((HELPERS_ONLY)); then echo "Signed the helpers in $APP with ${IDENTITY}"; exit 0; fi
sign_frameworks
sign --entitlements "$ROOT/Config/Zivlet.entitlements" "$APP"
echo "Signed $APP with ${IDENTITY}"
