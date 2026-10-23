#!/usr/bin/env bash
# idle-cpu.sh samples a process's CPU time with ps at the start and the end of a window and prints the average CPU
# percentage with three decimals. It refuses windows under 120 s (ps counts in 10 ms steps) and missing processes.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"
# A stand-in ps that answers from a list, one line per call, and a sleep that returns at once.
cat >"$T/bin/ps" <<'STUB'
#!/usr/bin/env bash
count=$(cat "$FAKE_PS_STATE" 2>/dev/null || echo 0)
echo $((count + 1)) >"$FAKE_PS_STATE"
line=$(sed -n "$((count + 1))p" "$FAKE_PS_TIMES")
[[ -n "$line" ]] || exit 1
echo "$line"
STUB
printf '#!/usr/bin/env bash\nexit 0\n' >"$T/bin/sleep"
chmod +x "$T/bin/ps" "$T/bin/sleep"
sample() {
    rm -f "$T/state"
    printf '%s\n' "${@:3}" >"$T/times"
    PATH=$T/bin:$PATH FAKE_PS_STATE=$T/state FAKE_PS_TIMES=$T/times "$ROOT/Scripts/idle-cpu.sh" "$1" "$2"
}
assert_eq "$(sample 123 120 '   0:01.00' '   0:01.12')" "0.100" "0.12 s of CPU over 120 s"
assert_eq "$(sample 123 200 '1:00.00' '1:02.00')" "1.000" "minutes in ps time"
assert_eq "$(sample 123 120 '1:00:00.00' '1:00:00.00')" "0.000" "hours in ps time"
out=$(sample 123 60 '0:01.00' '0:01.00' 2>&1) && fail "60 s must be refused"
assert_contains "$out" "sample at least 120 s"
status=0; sample 123 60 0 0 >/dev/null 2>&1 || status=$?
assert_eq "$status" "2" "a short window exits 2"
out=$(sample 999 120 2>&1) && fail "a missing process must be refused"
assert_contains "$out" "no process"
status=0; sample 999 120 >/dev/null 2>&1 || status=$?
assert_eq "$status" "2" "a missing process exits 2"
out=$(sample 123 120 '0:01.00' 2>&1) && fail "a process that ends during the sample must be refused"
assert_contains "$out" "ended during the sample"
assert_fails "$ROOT/Scripts/idle-cpu.sh" abc 120
echo "PASS test-idle-cpu"
