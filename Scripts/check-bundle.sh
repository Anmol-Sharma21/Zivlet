#!/usr/bin/env bash
# P1-50: the app carries ffmpeg and ffprobe in Contents/Helpers and every library they load in Contents/Frameworks.
# Fails when a helper is missing, names a dependency outside @rpath/, /usr/lib/ and /System/Library/, needs an
# @rpath library the bundle lacks, or has an LC_RPATH other than @executable_path/../Frameworks; then runs the
# bundled ffmpeg, which proves the rpath resolves inside the bundle. Plan 18c C10: the worker must be in
# Contents/XPCServices/ZivletWorker.xpc with identifier app.zivlet.Zivlet.Worker, and load only OS or bundle code.
# Usage: Scripts/check-bundle.sh <Zivlet.app>
set -euo pipefail
APP=${1:?usage: check-bundle.sh <app>}
HELPERS="ffmpeg ffprobe"
RPATH="@executable_path/../Frameworks"
WORKER=XPCServices/ZivletWorker.xpc
WORKER_ID=app.zivlet.Zivlet.Worker
CONTENTS=$APP/Contents
problems=0
problem() { echo "check-bundle: $*" >&2; problems=1; }

[[ -d "$CONTENTS" ]] || { echo "check-bundle: $APP is not an app bundle" >&2; exit 1; }

# Install names a Mach-O loads, without its own id line.
deps_of() { otool -L "$1" | tail -n +2 | awk '{print $1}' | grep -v -x -F "$(otool -D "$1" | tail -n +2)" || true; }

check_deps() {
    local file=$1 dep lib
    for dep in $(deps_of "$file"); do
        case "$dep" in
            /usr/lib/* | /System/Library/*) ;;
            @rpath/*)
                lib=${dep#@rpath/}
                [[ -f "$CONTENTS/Frameworks/$lib" ]] || problem "${file#"$APP/"} needs $lib, missing from Contents/Frameworks"
                ;;
            *) problem "${file#"$APP/"} loads $dep (outside the bundle and the OS)" ;;
        esac
    done
}

for helper in $HELPERS; do
    file=$CONTENTS/Helpers/$helper
    if [[ ! -x "$file" ]]; then problem "Contents/Helpers/$helper is missing"; continue; fi
    check_deps "$file"
    rpaths=$(otool -l "$file" | awk '/cmd LC_RPATH/ { getline; getline; print $2 }' | tr '\n' ' ')
    [[ "$rpaths" == "$RPATH " ]] || problem "Contents/Helpers/$helper has LC_RPATH [$rpaths] (want $RPATH)"
done
check_worker() {
    local bundle=$CONTENTS/$WORKER identifier
    if [[ ! -x "$bundle/Contents/MacOS/ZivletWorker" ]]; then problem "Contents/$WORKER is missing"; return; fi
    identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist" 2>/dev/null || true)
    [[ "$identifier" == "$WORKER_ID" ]] || problem "Contents/$WORKER has identifier [$identifier] (want $WORKER_ID)"
    check_deps "$bundle/Contents/MacOS/ZivletWorker"
}
check_worker
libraries=0
for lib in "$CONTENTS"/Frameworks/lib*.dylib; do
    [[ -f "$lib" ]] || continue
    check_deps "$lib"
    libraries=$((libraries + 1))
done
if ((problems)); then exit 1; fi
version=$("$CONTENTS/Helpers/ffmpeg" -hide_banner -version 2>&1 | head -1) ||
    { echo "check-bundle: the bundled ffmpeg does not run: $version" >&2; exit 1; }
echo "Bundle OK: $(wc -w <<<"$HELPERS" | tr -d ' ') helpers, $libraries libraries, 1 worker ($version)"
