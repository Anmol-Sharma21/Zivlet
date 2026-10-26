#!/usr/bin/env bash
# demo-box.sh adds four files to a demo box, shows the panel, quits, relaunches and expects the box restored (plan 16
# E4, Y4). Here the app launcher, the quit, the capture and the log reader are stand-ins, so the test checks the
# script: the lines it waits for, the screenshot, the folder it makes and removes, and its failures.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$ROOT/Scripts/demo-box.sh
grep -q '^box-demo:' "$ROOT/Makefile" || fail "Makefile has no box-demo target"

T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/Zivlet.app" "$T/fixtures" "$T/tmp"
for file in alpha.heic alpha.png pages.tiff pcm24.wav; do echo "$file" >"$T/fixtures/$file"; done
printf '#!/usr/bin/env bash\necho "$*" >>"%s/opened"\n' "$T" >"$T/bin/open"
printf '#!/usr/bin/env bash\nfor last; do :; done\ntouch "$last"\n' >"$T/bin/screencapture"
printf '#!/usr/bin/env bash\nexit 0\n' >"$T/bin/osascript"
printf '#!/usr/bin/env bash\nexit 0\n' >"$T/bin/pkill"
printf '#!/usr/bin/env bash\n[[ -n "${LOCKED:-}" ]] && printf "<key>CGSSessionScreenIsLocked</key>\\n<true/>\\n"\nexit 0\n' \
    >"$T/bin/ioreg"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$FAKE_LOG_OUTPUT"\n' >"$T/bin/fake-log"
chmod +x "$T/bin/"*
run() {
    PATH=$T/bin:$PATH TMPDIR=$T/tmp ZIVLET_BOX_DEMO_APP=$T/Zivlet.app ZIVLET_BOX_DEMO_LOG=$T/bin/fake-log \
        ZIVLET_BOX_DEMO_FIXTURES=${FIXTURES:-$T/fixtures} ZIVLET_BOX_DEMO_OUT=$T/out ZIVLET_BOX_DEMO_POLLS=2 \
        FAKE_LOG_OUTPUT=$1 "$SCRIPT"
}
shown=$(printf '%s\n' "Box: hidden" "Box: shown" "Box: items 4" "Box: expanded" "Box: frame 1400 200 384 252")
all=$(printf '%s\n%s' "$shown" "Box: restored 4 items")

out=$(run "$all") || fail "the three lines and a frame pass: $out"
assert_contains "$out" "Box: shown"
assert_contains "$out" "Box: items 4"
assert_contains "$out" "Box: restored 4 items"
assert_file "$T/opened"
assert_eq "$(grep -c -- "-ZivletBoxDemo $T/tmp/zivlet-m5b-demo." "$T/opened" | tr -d ' ')" "2" "two launches with the demo folder"
[[ -e "$T/out/box-demo.png" ]] || fail "the panel was not captured"
assert_eq "$(find "$T/tmp" -maxdepth 1 -name 'zivlet-m5b-demo.*' | wc -l | tr -d ' ')" "0" "the demo folder is removed"

# Without the restore line the run fails, and the folder is still removed.
status=0; run "$shown" >/dev/null 2>&1 || status=$?
assert_eq "$status" "1" "a box that is not restored fails"
assert_eq "$(find "$T/tmp" -maxdepth 1 -name 'zivlet-m5b-demo.*' | wc -l | tr -d ' ')" "0" "the folder is removed after a failure"
status=0; run "$(printf '%s\n' "Box: shown" "Box: items 3" "Box: restored 3 items")" >/dev/null 2>&1 || status=$?
assert_eq "$status" "1" "a box with fewer than four items fails"
status=0; FIXTURES=$T/missing run "$all" >/dev/null 2>&1 || status=$?
assert_eq "$status" "1" "a missing fixture fails"

# A locked screen skips the picture, not the check.
rm -f "$T/out/box-demo.png"
out=$(LOCKED=1 run "$all") || fail "a locked screen still checks the restore: $out"
assert_contains "$out" "skipped: screen locked"
assert_contains "$out" "Box: restored 4 items"
assert_no_file "$T/out/box-demo.png"
echo "PASS test-box-demo"
