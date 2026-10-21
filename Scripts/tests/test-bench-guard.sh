#!/usr/bin/env bash
# bench-guard.sh samples the Mac before make bench measures (G-M4-11). Quiet: it passes and prints the sample as JSON.
# Busy (one other process over 50 % CPU, or a 1-minute load over half the cores): it samples again in short steps up
# to a bound, then exits 3 with one line naming the busy process, so a loaded Mac skips the regression gate instead
# of failing it. ZIVLET_BENCH_FORCE=1 measures anyway. ZIVLET_BENCH_SAMPLER injects samples (script tests only).
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
GUARD=$ROOT/Scripts/bench-guard.sh

# Each sample is "<load 1 min> <cores> <CPU % of the heaviest other process> <its name>". The sampler prints the
# next line of $T/samples per call and repeats the last; $T/count counts the calls.
cat >"$T/sampler" <<EOF
#!/usr/bin/env bash
n=\$((\$(cat "$T/count") + 1)); echo "\$n" >"$T/count"
total=\$(wc -l <"$T/samples")
sed -n "\$(( n < total ? n : total ))p" "$T/samples"
EOF
chmod +x "$T/sampler"
samples() { printf '%s\n' "$@" >"$T/samples"; echo 0 >"$T/count"; }
guard() { ZIVLET_BENCH_SAMPLER=$T/sampler ZIVLET_BENCH_WAIT_STEP=${STEP:-0} ZIVLET_BENCH_WAIT_MAX=${MAX:-0} "$GUARD"; }
status_of() { local s=0; "$@" >"$T/out" 2>"$T/err" || s=$?; echo "$s"; }
field() { /usr/bin/jq -r "$1" "$T/out"; }

# Quiet Mac: pass, and the sample is the JSON on stdout.
samples "1.5 10 12.0 WindowServer"
assert_eq "$(status_of guard)" 0 "a quiet Mac must pass"
assert_eq "$(field .busy)" false
assert_eq "$(field .load_1min)" 1.5
assert_eq "$(field .cores)" 10
assert_eq "$(field .heaviest.process)" WindowServer
assert_eq "$(field .heaviest.cpu_percent)" 12
assert_eq "$(field .samples)" 1

# One busy process that does not settle: exit 3 and the one-line message naming it.
samples "6.2 10 150.4 mediaanalysisd"
assert_eq "$(status_of guard)" 3 "a busy process must skip with status 3"
assert_eq "$(cat "$T/err")" \
    "Skipped: the Mac is busy (mediaanalysisd 150 % CPU). Re-run when idle or set ZIVLET_BENCH_FORCE=1."
assert_eq "$(field .busy)" true

# A high load average with no single heavy process also skips, and says so.
samples "8.0 10 30.0 Google Chrome Helper"
assert_eq "$(status_of guard)" 3 "a load over half the cores must skip"
assert_contains "$(cat "$T/err")" "Skipped: the Mac is busy (load 8.0 on 10 cores; heaviest Google Chrome Helper 30 % CPU)."
assert_contains "$(cat "$T/err")" "set ZIVLET_BENCH_FORCE=1."

# Busy, then quiet within the bound: wait one step, then pass.
samples "6.0 10 140 mediaanalysisd" "1.0 10 5 WindowServer"
assert_eq "$(STEP=1 MAX=5 status_of guard)" 0 "a Mac that settles within the bound must pass"
assert_eq "$(field .samples)" 2
assert_eq "$(field .waited_s)" 1
assert_eq "$(field .heaviest.process)" WindowServer

# Busy for the whole bound: sample at 0, 1 and 2 s, then skip.
samples "6.0 10 140 mediaanalysisd"
assert_eq "$(STEP=1 MAX=2 status_of guard)" 3
assert_eq "$(cat "$T/count")" 3 "samples at 0, 1 and 2 s"

# Forced: measure anyway, recording that the Mac was busy.
samples "6.2 10 150 mediaanalysisd"
assert_eq "$(ZIVLET_BENCH_FORCE=1 status_of guard)" 0 "ZIVLET_BENCH_FORCE=1 must measure anyway"
assert_eq "$(field .forced)" true
assert_eq "$(field .busy)" true
assert_contains "$(cat "$T/err")" "measuring anyway"

# Bad samples and bad settings are errors (status 2), never a pass or a skip.
samples "x 10 5 WindowServer"
assert_eq "$(status_of guard)" 2 "a non-numeric load"
samples "1.0 0 5 WindowServer"
assert_eq "$(status_of guard)" 2 "zero cores"
samples "1.0 10 5"
assert_eq "$(status_of guard)" 2 "no process name"
samples "1.0 10 5 WindowServer"
assert_eq "$(MAX='1; rm -rf /' status_of guard)" 2 "a bad wait bound"
assert_eq "$(STEP=-1 status_of guard)" 2 "a negative step"

# The real sampler (no injection) reads this Mac: forced, so the result does not depend on the load right now.
real=$(ZIVLET_BENCH_FORCE=1 ZIVLET_BENCH_WAIT_MAX=0 "$GUARD" 2>/dev/null) || fail "the real sampler failed"
assert_eq "$(/usr/bin/jq -r .cores <<<"$real")" "$(sysctl -n hw.ncpu)"
/usr/bin/jq -e '.load_1min >= 0 and .heaviest.cpu_percent >= 0 and (.heaviest.process | length > 0)' \
    <<<"$real" >/dev/null || fail "the real sample is incomplete: $real"

# make bench runs the guard before measuring and records the sample in its JSON.
grep -q 'bench-guard.sh' "$ROOT/Scripts/bench.sh" || fail "bench.sh does not run bench-guard.sh"
grep -q 'load: \$load' "$ROOT/Scripts/bench.sh" || fail "bench.sh does not record the load sample"
echo "PASS test-bench-guard"
