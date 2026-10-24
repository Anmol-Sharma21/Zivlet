#!/usr/bin/env bash
# notch-idle.sh (M5a exit row X6, plan 14 D1): CONFIG=debug|release picks the app it measures; release builds its own
# optimised app with the island preview compiled in, into build/NotchIdleRelease. The dry run prints the plan without
# building or launching anything. check-release-paths.sh --scan-only runs the binary scans on one file, so the test
# can show that a binary carrying the preview flag is refused.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
# Stand-ins, so a script that ignored the dry run would fail here instead of building or launching the app.
mkdir "$T/bin"
for tool in open xcodebuild pgrep; do printf '#!/usr/bin/env bash\nexit 1\n' >"$T/bin/$tool"; done
for tool in osascript pkill sleep; do printf '#!/usr/bin/env bash\nexit 0\n' >"$T/bin/$tool"; done
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"

out=$(ZIVLET_IDLE_DRY_RUN=1 CONFIG=release "$ROOT/Scripts/notch-idle.sh")
assert_contains "$out" "build/NotchIdleRelease/Build/Products/Release/Zivlet.app"
assert_contains "$out" "SWIFT_ACTIVE_COMPILATION_CONDITIONS=\$(inherited) ZIVLET_ISLAND_PREVIEW"
assert_contains "$out" "-configuration Release"
while IFS= read -r line; do
    [[ "$line" == release* ]] || fail "every line names the configuration: [$line]"
done <<<"$out"

out=$(ZIVLET_IDLE_DRY_RUN=1 "$ROOT/Scripts/notch-idle.sh")
assert_contains "$out" "build/DerivedData/Build/Products/Debug/Zivlet.app"
for state in baseline hidden collapsed progress indeterminate; do assert_contains "$out" "debug state $state "; done
# plan 14 D20 (19b §6.3): the still glass card and the glass pill with progress, with their limits.
assert_contains "$out" "debug state card-still 0.1 -ZivletHUDPlacement notch -ZivletIslandPreview expanded"
assert_contains "$out" "debug state pill-progress 1 -ZivletHUDPlacement notch -ZivletIslandPreview progress -ZivletIslandPill YES"
# Design review: progress fast enough that the 250 ms floor holds steps back, and the pill with the same progress on
# the solid finish, to compare with glass; WindowServer's CPU is reported beside every row, for information.
assert_contains "$out" "debug state fast-progress 1 -ZivletHUDPlacement notch -ZivletIslandPreview fastProgress"
assert_contains "$out" "debug state pill-progress-solid 1 -ZivletHUDPlacement notch -ZivletIslandPreview progress -ZivletIslandPill YES -ZivletIslandFinish solid"
assert_contains "$out" "debug also samples WindowServer"

if grep -q "xcodebuild" <<<"$out"; then fail "the debug run measures make app's build and builds nothing"; fi

status=0; CONFIG=profile ZIVLET_IDLE_DRY_RUN=1 "$ROOT/Scripts/notch-idle.sh" >/dev/null 2>&1 || status=$?
assert_eq "$status" "2" "an unknown CONFIG exits 2"
grep -q 'CONFIG' "$ROOT/Makefile" || fail "the notch-idle target passes CONFIG"

# A real Mach-O with the flag appended, and one without.
cp /usr/bin/true "$T/clean"
cp /usr/bin/true "$T/with-flag"
printf '%s\0' "-ZivletIslandPreview" >>"$T/with-flag"
status=0; "$ROOT/Scripts/check-release-paths.sh" --scan-only "$T/with-flag" >/dev/null 2>&1 || status=$?
assert_eq "$status" "1" "a binary with the island preview flag is refused"
out=$("$ROOT/Scripts/check-release-paths.sh" --scan-only "$T/with-flag" 2>&1 || true)
assert_contains "$out" "island preview"
"$ROOT/Scripts/check-release-paths.sh" --scan-only "$T/clean" >/dev/null || fail "a clean binary passes the scans"
printf '%s\0' "/opt/homebrew/bin/ffmpeg" >>"$T/clean"
assert_fails "$ROOT/Scripts/check-release-paths.sh" --scan-only "$T/clean"
assert_fails "$ROOT/Scripts/check-release-paths.sh" --scan-only "$T/missing"
echo "PASS test-notch-idle"
