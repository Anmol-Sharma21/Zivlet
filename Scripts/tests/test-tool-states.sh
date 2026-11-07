#!/usr/bin/env bash
# demo-tool-states.sh (plan 20g F3, exit row V11): every new M7 state on screen. The dry run lists each state in
# each finish; with stand-ins for the app, the log reader, screencapture and the luminance reader, a state whose
# window shows and reads 4.5:1 passes, a missing PNG fails, a surface too light for white text fails, every capture
# is by window number (never a region of the screen), and a locked screen is skipped with nothing captured.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
source "$(dirname "$0")/demo-stubs.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$ROOT/Scripts/demo-tool-states.sh
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
grep -q '^tool-states:' "$ROOT/Makefile" || fail "Makefile has no tool-states target"

out=$(ZIVLET_STATES_DRY_RUN=1 "$SCRIPT" "$T/out")
for finish in glass solid contrast; do
    for state in lockEmpty lockMismatch lockSuggested lockNonASCII lockRestricted unlockWrong unlockBatch retry change \
        changeRetry ownerNeeded open; do
        assert_contains "$out" "capture password-$state-$finish.png"
    done
    assert_contains "$out" "capture qr-results-$finish.png"
    for card in lockCard unlockCard changeCard wrongCard; do assert_contains "$out" "capture island-$card-$finish.png"; done
done
for card in lockCard unlockCard changeCard wrongCard; do assert_contains "$out" "capture near-$card-glass.png"; done
assert_contains "$out" "-ZivletPasswordStates unlockWrong -ZivletIslandFinish contrast"
assert_eq "$(grep -c '^capture ' <<<"$out")" "55" "55 captures"

stub_bin "$T"
printf '#!/usr/bin/env bash\nexit 0\n' >"$T/fake-app"
printf '#!/usr/bin/env bash\necho "${FAKE_LUMINANCE:-0.005}"\n' >"$T/luminance"
chmod +x "$T/fake-app" "$T/luminance"
lines=$'2026-11-07 10:00:00 Zivlet: Password shot: unlockWrong window 77 size 340x262\n2026-11-07 10:00:00 Zivlet: Password shot: window 77 frame 10 20 340 262'
run() {
    PATH=$T/bin:$PATH ZIVLET_DEMO_APP=$T/Zivlet.app ZIVLET_SCREEN_LOCKED=0 ZIVLET_APP_PID_POLLS=1 \
        ZIVLET_DEMO_LOG=$T/bin/fake-log ZIVLET_LUMINANCE=$T/luminance ZIVLET_STATES_POLLS=2 ZIVLET_STATES_SETTLE=0 \
        ZIVLET_STATES_ONLY=${ONLY_STATES:-password-unlockWrong-glass} FAKE_LOG_OUTPUT=${LOG_LINES-$lines} "$SCRIPT" "$@"
}
out=$(run "$T/good" 2>&1) || fail "a shown state must pass: $out"
assert_file "$T/good/password-unlockWrong-glass.png"
assert_contains "$out" "white 0.8 text"
assert_contains "$(cat "$T/argv.log")" "screencapture -x -o -l 77"
grep -q 'screencapture.* -R' "$T/argv.log" && fail "a capture must never be a region of the screen"
status=0; out=$(FAKE_NO_PNG=1 run "$T/nopng" 2>&1) || status=$?
assert_eq "$status" "1" "a missing PNG fails"
assert_contains "$out" "no PNG was written"
status=0; out=$(FAKE_LUMINANCE=0.6 run "$T/light" 2>&1) || status=$?
assert_eq "$status" "1" "a surface too light for white text fails"
assert_contains "$out" "FAIL"
status=0; out=$(LOG_LINES="" run "$T/never" 2>&1) || status=$?
assert_eq "$status" "1" "a state that never shows fails"
assert_fails env ZIVLET_STATES_ONLY=nothing-like-this "$SCRIPT" "$T/unknown"

# Each state's app is quit before the next state launches, and the last one when the script ends: here the stand-in
# app keeps running until it is signalled, as the real one does, and nothing of it may be left after two states.
APP_BINARY=$T/Zivlet.app/Contents/MacOS/Zivlet
printf '#!/usr/bin/env bash\nwhile :; do sleep 0.1; done\n' >"$APP_BINARY"
cat >"$T/bin/open" <<EOF
#!/usr/bin/env bash
echo "open \$*" >>"$T/argv.log"
shift 3  # -n <app> --args
"$APP_BINARY" "\$@" >/dev/null 2>&1 &
sleep 0.3
EOF
chmod +x "$APP_BINARY" "$T/bin/open"
trap 'pkill -f "$APP_BINARY" || true; rm -rf "$T"' EXIT
: >"$T/argv.log"
out=$(ONLY_STATES=password-unlockWrong-glass,password-unlockWrong-solid run "$T/two" 2>&1) ||
    fail "two shown states must pass: $out"
assert_eq "$(grep -c '^open -n' "$T/argv.log")" "2" "one launch per state"
assert_eq "$(pgrep -f "$APP_BINARY" | wc -l | tr -d ' ')" "0" "every app the script launched is quit"

out=$(ZIVLET_SCREEN_LOCKED=1 "$SCRIPT" "$T/locked" 2>&1) || fail "a locked screen is skipped, not failed"
assert_contains "$out" "skipped: screen locked"
assert_no_file "$T/locked"
echo "PASS test-tool-states"
