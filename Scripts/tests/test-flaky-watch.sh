#!/usr/bin/env bash
# flaky-watch.sh counts passing and failing runs, keeps only failing logs, writes the job summary and fails on any
# failed run.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT

# Fails on the second of three runs.
counter=$T/count; echo 0 >"$counter"
flaky="n=\$((\$(cat $counter) + 1)); echo \$n >$counter; echo attempt \$n; [ \$n -ne 2 ]"
out=$(ZIVLET_WATCH_COMMAND=$flaky ZIVLET_WATCH_LOGS=$T/logs GITHUB_STEP_SUMMARY=$T/summary \
    "$ROOT/Scripts/flaky-watch.sh" 3 2>&1 || true)
assert_contains "$out" "Wheel tests: 2 passed, 1 failed of 3 runs"
assert_contains "$(cat "$T/summary")" "2 passed, 1 failed"
assert_file "$T/logs/run-2.log"
assert_no_file "$T/logs/run-1.log"
assert_contains "$(cat "$T/logs/run-2.log")" "attempt 2"
echo 0 >"$counter"
assert_fails env ZIVLET_WATCH_COMMAND="$flaky" ZIVLET_WATCH_LOGS="$T/logs" "$ROOT/Scripts/flaky-watch.sh" 3

out=$(ZIVLET_WATCH_COMMAND=true ZIVLET_WATCH_LOGS=$T/ok "$ROOT/Scripts/flaky-watch.sh" 2) || fail "all green must pass"
assert_contains "$out" "2 passed, 0 failed of 2 runs"
assert_fails "$ROOT/Scripts/flaky-watch.sh" 0
assert_fails "$ROOT/Scripts/flaky-watch.sh" "1; rm -rf /"
echo "PASS test-flaky-watch"
