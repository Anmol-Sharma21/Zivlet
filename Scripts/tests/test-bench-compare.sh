#!/usr/bin/env bash
# bench-compare.sh fails when a metric is more than 10 % worse than the baseline or missing from the run, passes
# within 10 %, and writes the baseline for this Mac on the first run (P1-63, G-9).
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
run() { # <file> <metrics JSON object>
    printf '{"model":"Mac99,1","macos":"26A428","note":"27-only","metrics":%s}\n' "$2" >"$T/$1"
}

run baseline.json '{"heic12mp_to_jpeg_ms":100,"idle_wakeups":0}'
run slow.json '{"heic12mp_to_jpeg_ms":111,"idle_wakeups":0}'
run fine.json '{"heic12mp_to_jpeg_ms":109,"idle_wakeups":0}'
run missing.json '{"idle_wakeups":0}'
run woken.json '{"heic12mp_to_jpeg_ms":90,"idle_wakeups":2}'
run tiny-base.json '{"drop_to_admit_ms":0.7}'
run tiny-run.json '{"drop_to_admit_ms":1.1}'
run tiny-slow.json '{"drop_to_admit_ms":1.8}'

out=$("$ROOT/Scripts/bench-compare.sh" "$T/slow.json" "$T/baseline.json" 2>&1 || true)
assert_contains "$out" "heic12mp_to_jpeg_ms"
assert_fails "$ROOT/Scripts/bench-compare.sh" "$T/slow.json" "$T/baseline.json"
out=$("$ROOT/Scripts/bench-compare.sh" "$T/fine.json" "$T/baseline.json" 2>&1) || fail "109 against 100 must pass: $out"
assert_contains "$out" "bench OK"
assert_fails "$ROOT/Scripts/bench-compare.sh" "$T/missing.json" "$T/baseline.json"
assert_fails "$ROOT/Scripts/bench-compare.sh" "$T/woken.json" "$T/baseline.json"
# Sub-unit timings: a regression must also be more than one unit (1 ms, 1 s, 1 wake-up) worse, so noise passes.
"$ROOT/Scripts/bench-compare.sh" "$T/tiny-run.json" "$T/tiny-base.json" >/dev/null || fail "0.7 → 1.1 ms is noise"
assert_fails "$ROOT/Scripts/bench-compare.sh" "$T/tiny-slow.json" "$T/tiny-base.json"
# A baseline may record the run-to-run spread seen on its Mac for a metric (slack, in the metric's unit).
printf '{"model":"Mac99,1","note":"27-only","metrics":{"drop_to_hud_ms":12},"slack":{"drop_to_hud_ms":8}}\n' \
    >"$T/noisy-base.json"
run noisy-ok.json '{"drop_to_hud_ms":19.5}'
run noisy-slow.json '{"drop_to_hud_ms":20.5}'
"$ROOT/Scripts/bench-compare.sh" "$T/noisy-ok.json" "$T/noisy-base.json" >/dev/null || fail "within the slack"
assert_fails "$ROOT/Scripts/bench-compare.sh" "$T/noisy-slow.json" "$T/noisy-base.json"

# No baseline yet: the run becomes the baseline for this model.
out=$("$ROOT/Scripts/bench-compare.sh" "$T/fine.json" "$T/new-baseline.json" 2>&1) || fail "first run must pass: $out"
assert_contains "$out" "baseline written"
assert_eq "$(/usr/bin/jq -r '.metrics.heic12mp_to_jpeg_ms' "$T/new-baseline.json")" "109"
assert_eq "$(/usr/bin/jq -r '.note' "$T/new-baseline.json")" "27-only"

assert_fails "$ROOT/Scripts/bench-compare.sh" "$T/nothing.json" "$T/baseline.json"
echo "PASS test-bench-compare"
