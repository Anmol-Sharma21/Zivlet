#!/usr/bin/env bash
# timing.sh judges the real-time budgets of ZivletTimingTests only below a stated load (D-M7-3): it waits for the
# 1-minute load to fall to the limit, refuses to judge above it (exit 3, swift never run), refuses a limit above the
# P-core count (exit 2) and prints the load before and after with the timing lines of the run. The load source and
# swift are stand-ins here.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$ROOT/Scripts/timing.sh
grep -q '^timing:' "$ROOT/Makefile" || fail "Makefile has no timing target"
grep -A2 '^notch-timing:' "$ROOT/Makefile" | grep -q 'timing.sh NotchHUDTiming' || fail "notch-timing must run timing.sh"

T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"
# The load source prints one `sysctl -n vm.loadavg` line per call from $T/loads (the last line repeats).
cat >"$T/bin/loadavg" <<STUB
#!/usr/bin/env bash
n=\$((\$(cat "$T/load-calls" 2>/dev/null || echo 0) + 1)); echo "\$n" >"$T/load-calls"
line=\$(sed -n "\${n}p" "$T/loads"); [[ -n "\$line" ]] || line=\$(tail -1 "$T/loads")
echo "{ \$line 2.00 2.00 }"
STUB
# swift records its arguments and ZIVLET_TIMING; `swift test` prints FAKE_SWIFT_LOG and exits FAKE_SWIFT_STATUS.
cat >"$T/bin/swift" <<STUB
#!/usr/bin/env bash
echo "\$* ZIVLET_TIMING=\${ZIVLET_TIMING:-}" >>"$T/swift-calls"
[[ "\$1" == test ]] && { printf '%s\n' "\${FAKE_SWIFT_LOG:-}"; exit "\${FAKE_SWIFT_STATUS:-0}"; }
exit 0
STUB
chmod +x "$T/bin/"*
run() {
    rm -f "$T/load-calls" "$T/swift-calls"
    printf '%s\n' "$@" >"$T/loads"
    ZIVLET_LOADAVG=$T/bin/loadavg ZIVLET_SWIFT=$T/bin/swift ZIVLET_PCORES=${PCORES:-6} ZIVLET_TIMING_WAIT=${WAIT:-0} \
        ZIVLET_TIMING_POLL=0 ZIVLET_TIMING_DIR=$T/logs "$SCRIPT" ${SUITE:-} 2>&1
}

# A quiet Mac: judged, the timing lines and the loads are printed, the tests ran with ZIVLET_TIMING=1.
measured="timing: drop→island p95 18.2 ms of 50 ms"
out=$(FAKE_SWIFT_LOG=$measured run 1.00) || fail "a quiet run that passes exits 0: $out"
assert_contains "$out" "$measured"
assert_contains "$out" "timing: load before 1.00, after 1.00, limit 3.0"
assert_contains "$(cat "$T/swift-calls")" "--filter ZivletTimingTests ZIVLET_TIMING=1"
assert_file "$T/logs/timing.log"

# A suite name narrows the filter.
SUITE=NotchHUDTiming run 1.00 >/dev/null || fail "a suite run passes"
assert_contains "$(cat "$T/swift-calls")" "--filter ZivletTimingTests.NotchHUDTiming"

# A busy Mac for the whole wait: not judged, exit 3, swift never called.
status=0; out=$(run 9.00) || status=$?
assert_eq "$status" "3" "a busy Mac is not judged"
assert_contains "$out" "timing: not judged (load 1m 9.00 > 3.0)"
assert_no_file "$T/swift-calls"

# The load falls during the wait: judged once it is at the limit.
out=$(WAIT=60 run 9.00 5.00 2.50) || fail "a load that falls to the limit is judged: $out"
assert_contains "$out" "timing: load before 2.50"

# The build itself loads the Mac: the guard waits again before the tests run.
status=0; out=$(run 1.00 9.00) || status=$?
assert_eq "$status" "3" "a load above the limit after the build is not judged"
if grep -q '^test' "$T/swift-calls"; then fail "the tests ran above the limit"; fi

# A failure is judged when the load stayed at the limit, and not judged when it rose above it during the run.
status=0; out=$(FAKE_SWIFT_STATUS=1 FAKE_SWIFT_LOG="✘ Test x() failed" run 1.00 1.00 1.00) || status=$?
assert_eq "$status" "1" "a failure at a quiet load is judged"
assert_contains "$out" "✘ Test x() failed"
status=0; out=$(FAKE_SWIFT_STATUS=1 run 1.00 1.00 7.50) || status=$?
assert_eq "$status" "3" "a failure while the load rose is not judged"
assert_contains "$out" "timing: not judged (load rose to 7.50 > 3.0 during the run)"

# The limit may be lowered, never raised past the P-core count.
out=$(ZIVLET_TIMING_MAX_LOAD=2 run 2.50 || true)
assert_contains "$out" "timing: not judged (load 1m 2.50 > 2"
status=0; ZIVLET_TIMING_MAX_LOAD=8 run 1.00 >/dev/null || status=$?
assert_eq "$status" "2" "a limit above the P-core count is refused"
assert_no_file "$T/swift-calls"
status=0; ZIVLET_TIMING_MAX_LOAD=abc run 1.00 >/dev/null || status=$?
assert_eq "$status" "2" "a limit that is not a number is refused"
out=$(PCORES=4 run 2.10 || true)
assert_contains "$out" "timing: not judged (load 1m 2.10 > 2.0)"
status=0; SUITE="x; rm -rf /" run 1.00 >/dev/null || status=$?
assert_eq "$status" "2" "a suite name that is not a Swift name is refused"
# --guard only waits for the load (X2 judges the app's own signpost with it): exit 0 at the limit, 3 above it.
out=$(SUITE=--guard run 2.00) || fail "--guard on a quiet Mac passes: $out"
assert_contains "$out" "timing: load 1m 2.00, limit 3.0"
assert_no_file "$T/swift-calls"
status=0; out=$(SUITE=--guard run 4.00) || status=$?
assert_eq "$status" "3" "--guard on a busy Mac is not judged"
assert_contains "$out" "timing: not judged (load 1m 4.00 > 3.0)"
echo "PASS test-timing"
