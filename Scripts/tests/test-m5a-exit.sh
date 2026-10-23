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
printf '#!/usr/bin/env bash\necho "$FAKE_MAKE_OUTPUT"\n' >"$T/bin/make"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$FAKE_LOG_OUTPUT"\n' >"$T/bin/fake-log"
chmod +x "$T/bin/make" "$T/bin/fake-log"
signpost="2026-10-23 10:00:01 Zivlet: [app.zivlet.Zivlet:hud] drop→island end"
card="Result card: <private> · 57 KB → 297 KB"
run() {
    PATH=$T/bin:$PATH ZIVLET_M5A_EXIT_LOGS=$T/logs ZIVLET_M5A_LOG=$T/bin/fake-log FAKE_MAKE_OUTPUT=$card \
        FAKE_LOG_OUTPUT=$1 "$ROOT/Scripts/m5a-exit.sh" "${@:2}"
}
out=$(run "$signpost") || fail "every row stubbed to pass must pass: $out"
for row in X1 X2 X3 X4 X5 X6 X7; do assert_contains "$out" "$row pass"; done
assert_file "$T/logs/X5.log"

asked="2026-10-23 10:00:02 tccd: AUTHREQ_SUBJECT: msgID=1, function=TCCAccessRequest, service=kTCCServiceListenEvent, preflight=no, subject=app.zivlet.Zivlet"
out=$(run "$(printf '%s\n%s' "$signpost" "$asked")" --only X5 || true)
assert_contains "$out" "X5 FAIL"
assert_contains "$(cat "$T/logs/X5.log")" "kTCCServiceListenEvent"

checked="2026-10-23 10:00:03 tccd: AUTHREQ_SUBJECT: msgID=2, function=TCCAccessPreflight, service=kTCCServiceListenEvent, preflight=yes, subject=app.zivlet.Zivlet"
out=$(run "$(printf '%s\n%s' "$signpost" "$checked")" --only X5) || fail "preflight checks must not fail X5: $out"
assert_contains "$out" "X5 pass"
assert_contains "$(cat "$T/logs/X5.log")" "preflight=yes"

out=$(run "no signposts here" --only X2 || true)
assert_contains "$out" "X2 FAIL"
out=$(PATH=$T/bin:$PATH ZIVLET_M5A_EXIT_LOGS=$T/logs ZIVLET_M5A_LOG=$T/bin/fake-log FAKE_LOG_OUTPUT=$signpost \
    FAKE_MAKE_OUTPUT="$(printf '%s\n%s' "$card" "Island: toast")" "$ROOT/Scripts/m5a-exit.sh" --only X4 || true)
assert_contains "$out" "X4 FAIL"
echo "PASS test-m5a-exit"
