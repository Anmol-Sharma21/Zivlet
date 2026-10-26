#!/usr/bin/env bash
# check-bundle.sh: helpers in Contents/Helpers, their libraries in Contents/Frameworks, only @rpath and OS
# dependencies, LC_RPATH @executable_path/../Frameworks, and a helper that runs from inside the bundle; the worker
# (plan 18c C10) in Contents/XPCServices with its identifier and only OS or bundle dependencies.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
STAGE=$ROOT/Vendor/out/media-stage
[[ -x "$STAGE/Helpers/ffmpeg" ]] || fail "no media stage; run make vendor first"
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
printf 'int main(void) { return 0; }\n' >"$T/worker.c"
cc -o "$T/worker" "$T/worker.c"
fake() { # a fresh fake app built from the stage, with a tiny worker
    rm -rf "$T/Fake.app"; mkdir -p "$T/Fake.app/Contents"
    cp -R "$STAGE/Helpers" "$STAGE/Frameworks" "$T/Fake.app/Contents/"
    local xpc=$T/Fake.app/Contents/XPCServices/ZivletWorker.xpc/Contents
    mkdir -p "$xpc/MacOS"; cp "$T/worker" "$xpc/MacOS/ZivletWorker"
    plutil -create xml1 "$xpc/Info.plist"
    plutil -insert CFBundleIdentifier -string "${1:-app.zivlet.Zivlet.Worker}" "$xpc/Info.plist"
}
WORKER_BIN=Fake.app/Contents/XPCServices/ZivletWorker.xpc/Contents/MacOS/ZivletWorker
check() { "$ROOT/Scripts/check-bundle.sh" "$T/Fake.app" 2>&1 || true; }

fake; "$ROOT/Scripts/check-bundle.sh" "$T/Fake.app" >/dev/null || fail "a complete fake bundle must pass"

fake; rm "$T/Fake.app/Contents/Helpers/ffprobe"
assert_contains "$(check)" "ffprobe"
assert_fails "$ROOT/Scripts/check-bundle.sh" "$T/Fake.app"

fake; install_name_tool -change @rpath/libavutil.61.dylib /opt/homebrew/lib/libavutil.61.dylib \
    "$T/Fake.app/Contents/Helpers/ffmpeg" 2>/dev/null
assert_contains "$(check)" "/opt/homebrew/lib/libavutil"
assert_fails "$ROOT/Scripts/check-bundle.sh" "$T/Fake.app"

fake; rm -rf "$T/Fake.app/Contents/XPCServices"
assert_contains "$(check)" "ZivletWorker.xpc is missing"
assert_fails "$ROOT/Scripts/check-bundle.sh" "$T/Fake.app"

fake; install_name_tool -change /usr/lib/libSystem.B.dylib /opt/homebrew/lib/libSystem.B.dylib "$T/$WORKER_BIN" 2>/dev/null
assert_contains "$(check)" "/opt/homebrew/lib/libSystem"
assert_fails "$ROOT/Scripts/check-bundle.sh" "$T/Fake.app"

fake app.zivlet.Other
assert_contains "$(check)" "app.zivlet.Other"
assert_fails "$ROOT/Scripts/check-bundle.sh" "$T/Fake.app"

fake; rm "$T/Fake.app/Contents/Frameworks/libswresample.7.dylib"
assert_contains "$(check)" "libswresample.7.dylib"
assert_fails "$ROOT/Scripts/check-bundle.sh" "$T/Fake.app"

fake; install_name_tool -rpath @executable_path/../Frameworks @loader_path/elsewhere \
    "$T/Fake.app/Contents/Helpers/ffprobe" 2>/dev/null
assert_contains "$(check)" "LC_RPATH"
assert_fails "$ROOT/Scripts/check-bundle.sh" "$T/Fake.app"

# The real Debug app after make app: the bundled ffmpeg resolves its libraries inside the bundle and runs.
APP=$ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app
[[ -d "$APP" ]] || fail "no Debug app; run make app first"
out=$("$ROOT/Scripts/check-bundle.sh" "$APP")
assert_contains "$out" "Bundle OK: 2 helpers, 7 libraries, 1 worker"
"$APP/Contents/Helpers/ffmpeg" -hide_banner -version | head -1 | grep -q "ffmpeg version 9.0.2" ||
    fail "the bundled ffmpeg does not run from the app"
echo "PASS test-check-bundle"
