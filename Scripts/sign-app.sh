#!/usr/bin/env bash
# Signs Zivlet.app inside-out (P0-38, 11 §7.2): libraries in Contents/Frameworks, then the helpers in
# Contents/Helpers (identifier app.zivlet.helper.<name>), then nested frameworks (their inner bundles and
# executables first), then the XPC services in Contents/XPCServices (the worker, app.zivlet.Zivlet.Worker, plan 18c:
# no entitlements in any build, as it loads only system libraries), then the app with Config/Zivlet.entitlements. Always the hardened runtime; a secure timestamp
# when the identity is a real certificate. Ad-hoc signatures use Config/HelperAdHoc.entitlements for the helpers and
# Config/ZivletAdHoc.entitlements for the app, because library validation cannot match the Team ID of ad-hoc files
# (they have none).
# --nested-only signs everything inside the app but not the app itself (the Xcode embed phase: Xcode signs the app
# afterwards).
# Usage: Scripts/sign-app.sh [--nested-only] <identity|-> <Zivlet.app>
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NESTED_ONLY=0
if [[ "${1:-}" == "--nested-only" ]]; then NESTED_ONLY=1; shift; fi
IDENTITY=${1:?usage: sign-app.sh [--nested-only] <identity|-> <app>}
APP=${2:?usage: sign-app.sh [--nested-only] <identity|-> <app>}
CONTENTS=$APP/Contents
[[ -d "$CONTENTS" ]] || { echo "error: $APP is not an app bundle" >&2; exit 1; }

# Plain strings, not arrays: bash 3.2 (macOS /bin/bash) rejects empty arrays under set -u.
FLAGS="--force --options runtime"
[[ "$IDENTITY" != "-" ]] && FLAGS="$FLAGS --timestamp"
HELPER_FLAGS=""
[[ "$IDENTITY" == "-" ]] && HELPER_FLAGS="--entitlements $ROOT/Config/HelperAdHoc.entitlements"
# The app keeps library validation on with a real identity; ad-hoc it cannot load the ad-hoc Sparkle.framework.
APP_ENTITLEMENTS=$ROOT/Config/Zivlet.entitlements
[[ "$IDENTITY" == "-" ]] && APP_ENTITLEMENTS=$ROOT/Config/ZivletAdHoc.entitlements

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

# Each service with its bundle identifier and no entitlements (02 §2.1: the worker has none).
sign_xpc_services() {
    local service identifier
    for service in "$CONTENTS"/XPCServices/*.xpc; do
        [[ -d "$service" ]] || continue
        identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$service/Contents/Info.plist")
        sign --identifier "$identifier" "$service"
    done
}

sign_libraries
sign_helpers
sign_frameworks
sign_xpc_services
if ((NESTED_ONLY)); then echo "Signed the nested code in $APP with ${IDENTITY}"; exit 0; fi
sign --entitlements "$APP_ENTITLEMENTS" "$APP"
echo "Signed $APP with ${IDENTITY}"
