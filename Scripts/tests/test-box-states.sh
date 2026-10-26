#!/usr/bin/env bash
# demo-box-states.sh captures every Drop Box and notch tray state (19c §4, OWN-UI-1) from the Debug app, one launch
# per state. Here the dry run must list a capture for every state the app can preview, on every finish, and the real
# loop runs against stand-ins (no app is launched or quit): a refused flag, a missing state line and a locked screen.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$ROOT/Scripts/demo-box-states.sh
FLAGS=$ROOT/Packages/ZivletKit/Sources/ZivletBox/BoxShotFlags.swift
grep -q '^box-states:' "$ROOT/Makefile" || fail "Makefile has no box-states target"

out=$(ZIVLET_STATES_DRY_RUN=1 "$SCRIPT")
# Every panel state the app can preview (BoxShotFlags.State) is listed: hidden as a log line, the rest as captures on
# glass, solid and contrast.
panel_states=$(sed -n '/enum State:/,/}/p' "$FLAGS" | grep -E '^\s*case ' | sed 's/case//; s/,/ /g')
[[ -n "$panel_states" ]] || fail "could not read the panel states from BoxShotFlags.swift"
for state in $panel_states; do
    if [[ "$state" == hidden ]]; then
        assert_contains "$out" "log only after Box: hidden: -ZivletBoxPreview hidden"
        continue
    fi
    for finish in glass solid contrast; do
        assert_contains "$out" "capture box-$state-$finish.png after Box: $state:"
    done
done
# 19c §4.1's states by name, so a state dropped from the enum is noticed here too.
for state in docked collapsed grid list selection dropTarget busy attention confirmTrash confirmClear empty; do
    assert_contains "$out" "box-$state-glass.png"
done
# The tray at the notch and on a pill display (19c §4.2, §4.3), on every finish; the sensor draws nothing.
for state in dropTarget toast compact; do
    for finish in glass solid contrast; do
        assert_contains "$out" "capture tray-$state-$finish.png after Island:"
        assert_contains "$out" "capture pill-tray-$state-$finish.png after Island:"
    done
done
assert_contains "$out" "tray-compact-glass.png after Island: expanded"
assert_contains "$out" "tray-dropTarget-glass.png after Island: dropTarget"
assert_contains "$out" "pill-tray-toast-glass.png after Island: toast: -ZivletTrayPreview toast -ZivletIslandPill YES"
assert_contains "$out" "log only after Island: sensor: -ZivletTrayPreview sensor"
assert_contains "$out" "box-grid-reduce-motion.png"
assert_contains "$out" "tray-dropTarget-reduce-motion.png"
# Over white: the panel, the docked tab and the tray drop target each get a text-free box for the contrast check.
for white in box-grid-white box-docked-white tray-dropTarget-white; do
    grep -F "$white.png" <<<"$out" | grep -F -- "-ZivletIslandBackdrop white" | grep -qF "contrast box" ||
        fail "$white has no contrast box over the white backdrop"
done
assert_eq "$(grep -c "contrast box" <<<"$out" | tr -d ' ')" "$(grep -c -- "-ZivletIslandBackdrop white" <<<"$out" | tr -d ' ')" \
    "every white capture is measured"

# The real loop with stand-ins: open records its arguments, screencapture writes the file, ioreg says the screen is
# awake unless LOCKED is set, and the log reader prints FAKE_LOG_OUTPUT.
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/Zivlet.app"
printf '#!/usr/bin/env bash\necho "$*" >>"%s/opened"\n' "$T" >"$T/bin/open"
printf '#!/usr/bin/env bash\nfor last; do :; done\ntouch "$last"\n' >"$T/bin/screencapture"
printf '#!/usr/bin/env bash\nexit 0\n' >"$T/bin/osascript"
printf '#!/usr/bin/env bash\nexit 0\n' >"$T/bin/pkill"
printf '#!/usr/bin/env bash\n[[ -n "${LOCKED:-}" ]] && printf "<key>CGSSessionScreenIsLocked</key>\\n<true/>\\n"\nexit 0\n' \
    >"$T/bin/ioreg"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$FAKE_LOG_OUTPUT"\n' >"$T/bin/fake-log"
chmod +x "$T/bin/"*
run() {
    PATH=$T/bin:$PATH ZIVLET_STATES_APP=$T/Zivlet.app ZIVLET_STATES_LOG=$T/bin/fake-log ZIVLET_STATES_POLLS=2 \
        ZIVLET_STATES_SETTLE=0 FAKE_LOG_OUTPUT=$1 "$SCRIPT" "$T/out"
}
shown=$(printf '%s\n%s' "Box: grid" "Box: frame 300 120 360 420")
out=$(ZIVLET_STATES_ONLY=box-grid-glass run "$shown") || fail "a state that shows with its frame passes: $out"
assert_file "$T/opened"
assert_contains "$(cat "$T/opened")" "-ZivletBoxPreview grid"
assert_contains "$out" "box-grid-glass.png (300 120 360 420)"
[[ -e "$T/out/box-grid-glass.png" ]] || fail "the capture was not written"

out=$(ZIVLET_STATES_ONLY=box-grid-glass run "$(printf '%s\n%s' "$shown" \
    "Box screenshot flags refused: unknown value for -ZivletBoxPreview")" 2>&1 || true)
assert_contains "$out" "screenshot flags refused"
status=0; ZIVLET_STATES_ONLY=box-grid-glass run "$(printf '%s\n%s' "$shown" \
    "Island screenshot flags refused: unknown value for -ZivletIslandFinish")" >/dev/null 2>&1 || status=$?
assert_eq "$status" "1" "a refused island flag fails the capture"

status=0; ZIVLET_STATES_ONLY=tray-toast-glass run "Island: hidden" >/dev/null 2>&1 || status=$?
assert_eq "$status" "1" "a state that never shows fails"
status=0; ZIVLET_STATES_ONLY=box-nothing run "$shown" >/dev/null 2>&1 || status=$?
assert_eq "$status" "2" "an unknown capture name is refused"

rm -f "$T/opened"
out=$(LOCKED=1 run "$shown") || fail "a locked screen is a skip, not a failure: $out"
assert_contains "$out" "skipped: screen locked"
assert_no_file "$T/opened"
echo "PASS test-box-states"
