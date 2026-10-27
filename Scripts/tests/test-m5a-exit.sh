#!/usr/bin/env bash
# m5a-exit.sh runs the M5a exit rows X1–X7 (plan 12 §6) in order, each into its own log, and prints one line per
# row. Here every row's commands are stand-ins on PATH (make, git stays real) and the log reader is a stub, so the
# test checks the runner: the row list, --only, the summary, and the TCC rule of D-M5a-5.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
listed=$("$ROOT/Scripts/m5a-exit.sh" --list)
for row in X1 X2 X3 X4 X5 X6 X7; do assert_contains "$listed" "$row "; done
assert_contains "$listed" "make test lint coverage app release-check licence-gate"
assert_contains "$listed" "make notch-demo"
assert_eq "$("$ROOT/Scripts/m5a-exit.sh" --list --only X5,X2 | cut -d' ' -f1 | tr '\n' ' ')" "X2 X5 " "--only keeps the row order"
assert_fails "$ROOT/Scripts/m5a-exit.sh" --list --only X8
assert_fails "$ROOT/Scripts/m5a-exit.sh" --bogus
grep -q '^m5a-exit:' "$ROOT/Makefile" || fail "Makefile has no m5a-exit target"
grep -q '^notch-demo:' "$ROOT/Makefile" || fail "Makefile has no notch-demo target"

T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"
# make fails for the target named in FAKE_MAKE_FAIL; the log reader fails for the TCC stream when FAKE_LOG_FAIL is set.
# Every make call is recorded in $T/make-calls, one line of targets per call; the output comes before a failure.
printf '#!/usr/bin/env bash\necho "$*" >>"%s/make-calls"\necho "$FAKE_MAKE_OUTPUT"\n[[ -n "${FAKE_MAKE_FAIL:-}" && " $* " == *" $FAKE_MAKE_FAIL "* ]] && exit 1\nexit 0\n' \
    "$T" >"$T/bin/make"
# The load source of timing.sh's guard: FAKE_LOAD (default 1.00) for the 1-minute load.
printf '#!/usr/bin/env bash\necho "{ ${FAKE_LOAD:-1.00} 1.00 1.00 }"\n' >"$T/bin/fake-load"
printf '#!/usr/bin/env bash\n[[ -n "${FAKE_LOG_FAIL:-}" && "$*" == *com.apple.TCC* ]] && exit 1\nprintf "%%s\\n" "$FAKE_LOG_OUTPUT"\n' \
    >"$T/bin/fake-log"
chmod +x "$T/bin/make" "$T/bin/fake-log" "$T/bin/fake-load"
touch "$T/srgb.heic"
# The app's drop→island interval as `log show --signpost --style ndjson` prints it; 24 MHz ticks, so 432000 = 18 ms.
interval() {
    printf '{"eventType":"signpostEvent","signpostName":"drop→island","signpostID":7,"signpostType":"%s","machTimestamp":%s}\n' \
        begin 1000000 end $((1000000 + $1))
}
signpost=$(interval 432000)
card="Result card: <private> · 57 KB → 297 KB"
run() {
    PATH=$T/bin:$PATH ZIVLET_M5A_EXIT_LOGS=$T/logs ZIVLET_M5A_LOG=$T/bin/fake-log FAKE_MAKE_OUTPUT=${MAKE_OUT:-$card} \
        ZIVLET_LOADAVG=$T/bin/fake-load ZIVLET_PCORES=6 ZIVLET_TIMING_WAIT=0 ZIVLET_M5A_TICKS=24000000 \
        ZIVLET_M5A_FIXTURE=${FIXTURE:-$T/srgb.heic} FAKE_LOG_OUTPUT=$1 "$ROOT/Scripts/m5a-exit.sh" "${@:2}"
}
out=$(run "$signpost") || fail "every row stubbed to pass must pass: $out"
for row in X1 X2 X3 X4 X5 X6 X7; do assert_contains "$out" "$row pass"; done
assert_file "$T/logs/X5.log"

asked="2026-10-23 10:00:02 tccd: AUTHREQ_SUBJECT: msgID=1, function=TCCAccessRequest, service=kTCCServiceListenEvent, preflight=no, subject=app.zivlet.Zivlet"
out=$(run "$(printf '%s\n%s' "$signpost" "$asked")" --only X2,X3,X4,X5 || true)
assert_contains "$out" "X5 FAIL"
assert_contains "$(cat "$T/logs/X5.log")" "kTCCServiceListenEvent"

checked="2026-10-23 10:00:03 tccd: AUTHREQ_SUBJECT: msgID=2, function=TCCAccessPreflight, service=kTCCServiceListenEvent, preflight=yes, subject=app.zivlet.Zivlet"
out=$(run "$(printf '%s\n%s' "$signpost" "$checked")" --only X2,X3,X4,X5) || fail "preflight checks must not fail X5: $out"
assert_contains "$out" "X5 pass"
assert_contains "$(cat "$T/logs/X5.log")" "preflight=yes"
assert_contains "$(cat "$T/logs/X5.log")" "TCC lines examined: 3"

# X5 checks nothing on its own: the demos it watches must run in the same invocation.
out=$(run "$signpost" --only X5 || true)
assert_contains "$out" "X5 FAIL"
assert_contains "$(cat "$T/logs/X5.log")" "needs X2, X3 and X4"
# A log reader that fails is a failure, not "no request".
out=$(FAKE_LOG_FAIL=1 run "$signpost" --only X2,X3,X4,X5 || true)
assert_contains "$out" "X5 FAIL"
# A failing step inside a row fails the row, even when the row's last check passes.
out=$(FAKE_MAKE_FAIL=notch-timing run "$signpost" --only X2 || true)
assert_contains "$out" "X2 FAIL"
out=$(FIXTURE=$T/missing.heic run "$signpost" --only X2 || true)
assert_contains "$out" "X2 FAIL"

# X3 alone in a fresh clone makes its own fixture before the demo (D-M7-9).
rm -f "$T/make-calls"
out=$(run "$signpost" --only X3) || fail "X3 alone must pass on the stubs: $out"
assert_contains "$out" "X3 pass"
assert_eq "$(tr '\n' ',' <"$T/make-calls")" "fixtures,notch-demo," "X3 makes the fixtures, then runs the demo"
# The demo itself makes the fixture when it is missing, before it looks for the app.
rm -f "$T/make-calls"
out=$(PATH=$T/bin:$PATH ZIVLET_NOTCH_DEMO_FIXTURE=$T/none/srgb.heic ZIVLET_NOTCH_DEMO_APP=$T/none/Zivlet.app \
    "$ROOT/Scripts/demo-notch.sh" "$T/notch-out" 2>&1 || true)
assert_contains "$(cat "$T/make-calls")" "fixtures"
assert_contains "$out" "not found after make fixtures"

out=$(run "no signposts here" --only X2 || true)
assert_contains "$out" "X2 FAIL"
# X2 prints the app's own drop→island time and judges it against 50 ms below the load limit (D-M7-4).
out=$(run "$signpost" --only X2) || fail "an 18 ms island at a quiet load passes: $out"
assert_contains "$out" "X2 pass"
assert_contains "$(cat "$T/logs/X2.log")" "drop→island in the app: 18.0 ms of 50 ms"
out=$(run "$(interval 1440000)" --only X2 || true)
assert_contains "$out" "X2 FAIL"
assert_contains "$(cat "$T/logs/X2.log")" "drop→island in the app: 60.0 ms of 50 ms"
# Above the load limit the app's time is printed and not judged: the row is skipped, and a skip is not a pass.
status=0; out=$(FAKE_LOAD=9.00 run "$(interval 1440000)" --only X2) || status=$?
assert_eq "$status" "1" "a skipped row fails the exit run"
assert_contains "$out" "X2 SKIP"
assert_contains "$(cat "$T/logs/X2.log")" "timing: not judged (load 1m 9.00 > 3.0)"
# The timing suite not judged (make notch-timing exits 3 through make) skips the row too; other failures fail it.
status=0; out=$(MAKE_OUT="timing: not judged (load 1m 7.10 > 3.0)" FAKE_MAKE_FAIL=notch-timing \
    run "$signpost" --only X2) || status=$?
assert_eq "$status" "1" "a row whose timing suite was not judged fails the exit run"
assert_contains "$out" "X2 SKIP"
out=$(PATH=$T/bin:$PATH ZIVLET_M5A_EXIT_LOGS=$T/logs ZIVLET_M5A_LOG=$T/bin/fake-log FAKE_LOG_OUTPUT=$signpost \
    ZIVLET_M5A_FIXTURE=$T/srgb.heic FAKE_MAKE_OUTPUT="$(printf '%s\n%s' "$card" "Island: toast")" \
    "$ROOT/Scripts/m5a-exit.sh" --only X4 || true)
assert_contains "$out" "X4 FAIL"
echo "PASS test-m5a-exit"
