#!/usr/bin/env bash
# demo-box-busy.sh runs the Debug app's cancelled Move of 50 files with Undo (plan 18e E2, exit row Z8). Here the
# app launcher is a stand-in that plays the app's part in the demo folder (the held overlay, the result, the files
# after Undo), and the capture and the quit are stand-ins too, so the test checks the script: the handshake, the
# picture, the checks of the result and of the files, the folder it makes and removes, and its failures.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$ROOT/Scripts/demo-box-busy.sh
grep -q '^box-busy-demo:' "$ROOT/Makefile" || fail "Makefile has no box-busy-demo target"

T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/Zivlet.app" "$T/tmp"
# The stand-in app: finds the folder after the flag, makes the files as they are after Undo, writes hold.json, waits
# for the script's `captured`, then writes result.json and `done`. FAKE_SOURCE is how many files it leaves in source.
cat >"$T/bin/open" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_OPENED"
folder=""
while (($#)); do [[ "$1" == -ZivletBoxBusyDemo ]] && folder=$2; shift; done
[[ -n "$folder" ]] || exit 0
(
    mkdir -p "$folder/source" "$folder/moved"
    for i in $(seq 1 "${FAKE_SOURCE:-50}"); do echo "item $i" >"$folder/source/item-$i.txt"; done
    printf '{"done":20,"total":50,"frame":"100 200 384 300"}' >"$folder/hold.json"
    for _ in $(seq 1 40); do [[ -e "$folder/captured" ]] && break; sleep 0.1; done
    [[ -n "${FAKE_NO_DONE:-}" ]] && exit 0
    printf '%s' "$FAKE_RESULT" >"$folder/result.json"
    touch "$folder/done"
) &
EOF
printf '#!/usr/bin/env bash\nfor last; do :; done\necho png >"$last"\n' >"$T/bin/screencapture"
printf '#!/usr/bin/env bash\nexit 0\n' >"$T/bin/osascript"
chmod +x "$T/bin/"*
good='{"kind":"partial","toast":"Moved 20 items","card":"Stopped. 30 items weren'"'"'t moved.","movedBeforeUndo":20,"leftBeforeUndo":30,"undo":"Moved back","sourceAfterUndo":50,"movedAfterUndo":0,"captured":true}'
run() {
    PATH=$T/bin:$PATH TMPDIR=$T/tmp FAKE_OPENED=$T/opened ZIVLET_BOX_BUSY_APP=$T/Zivlet.app \
        ZIVLET_BOX_BUSY_OUT=$T/out ZIVLET_BOX_BUSY_TIMEOUT=10 ZIVLET_SCREEN_LOCKED=${LOCKED:-0} \
        FAKE_RESULT=${RESULT:-$good} "$SCRIPT"
}
leftover() { find "$T/tmp" -maxdepth 1 -name 'zivlet-m6-busy.*' | wc -l | tr -d ' '; }

out=$(run) || fail "a cancelled move with a full Undo passes: $out"
assert_contains "$out" "PASS overlay: held at 20 of 50"
assert_contains "$out" "PASS stopped: Moved 20 items; Stopped. 30 items weren't moved."
assert_contains "$out" "PASS undo: 50 back in source, 0 left in moved"
assert_file "$T/out/box-busy.png"
assert_contains "$(cat "$T/opened")" "-ZivletBoxBusyDemo $T/tmp/zivlet-m6-busy."
assert_eq "$(leftover)" "0" "the demo folder is removed"

# The script counts the files itself: an app that says 50 while 49 are back fails.
status=0; out=$(FAKE_SOURCE=49 run) || status=$?
assert_eq "$status" "1" "a file missing after Undo fails"
assert_contains "$out" "FAIL undo"
assert_eq "$(leftover)" "0" "the folder is removed after a failure"

# A run that was not stopped part-way is not the demo.
status=0
out=$(RESULT='{"kind":"done","toast":"Moved 50 items","card":"","movedBeforeUndo":50,"leftBeforeUndo":0,"undo":"Moved back","sourceAfterUndo":50,"movedAfterUndo":0,"captured":true}' run) ||
    status=$?
assert_eq "$status" "1" "a move that was not cancelled fails"
assert_contains "$out" "FAIL stopped"

# An app that never finishes fails after the timeout.
status=0; FAKE_NO_DONE=1 run >/dev/null 2>&1 || status=$?
assert_eq "$status" "1" "a demo that never finishes fails"

# A locked screen skips the picture, not the checks.
rm -f "$T/out/box-busy.png"
out=$(LOCKED=1 run) || fail "a locked screen still checks the move and Undo: $out"
assert_contains "$out" "skipped: screen locked"
assert_contains "$out" "PASS undo"
assert_no_file "$T/out/box-busy.png"
echo "PASS test-box-busy-demo"
