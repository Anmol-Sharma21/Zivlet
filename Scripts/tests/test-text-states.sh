#!/usr/bin/env bash
# demo-text-states.sh (plan 18d D15, exit row Z9): every Copy Text state on screen from the Debug app, one launch per
# state. Here the dry run must list each state, and a locked screen is skipped, not passed.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$ROOT/Scripts/demo-text-states.sh
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
grep -q '^text-states:' "$ROOT/Makefile" || fail "Makefile has no text-states target"

out=$(ZIVLET_STATES_DRY_RUN=1 "$SCRIPT" "$T/out")
for state in notchToast notchCard hudCard showAll; do
    assert_contains "$out" "capture text-$state.png: -ZivletTextStates $state"
done
assert_contains "$out" "capture text-setting.png: -ZivletDemoSettings general"

out=$(ZIVLET_SCREEN_LOCKED=1 "$SCRIPT" "$T/out" 2>&1) || fail "a locked screen is skipped, not failed"
assert_contains "$out" "skipped: screen locked"
assert_no_file "$T/out/text-notchCard.png"
echo "PASS test-text-states"
