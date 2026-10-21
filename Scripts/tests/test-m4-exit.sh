#!/usr/bin/env bash
# m4-exit.sh runs the automated M4 exit rows X1–X9 of 10h F8 in order, each into its own log, and prints one line
# per row. --list shows the rows and their commands without running anything; --only picks rows.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
listed=$("$ROOT/Scripts/m4-exit.sh" --list)
for row in X1 X2 X3 X4 X5 X6 X7 X8 X9; do assert_contains "$listed" "$row "; done
assert_contains "$listed" "make vendor-test lint test coverage app release-check licence-gate"
assert_contains "$listed" "ZIVLET_MATRIX=full make matrix"
assert_contains "$listed" "ZIVLET_FFMPEG_DIR=/opt/homebrew/bin make smoke"
assert_eq "$("$ROOT/Scripts/m4-exit.sh" --list --only X4,X1 | cut -d' ' -f1 | tr '\n' ' ')" "X1 X4 " "--only keeps the row order"
assert_fails "$ROOT/Scripts/m4-exit.sh" --list --only X10
assert_fails "$ROOT/Scripts/m4-exit.sh" --bogus
grep -q '^m4-exit:' "$ROOT/Makefile" || fail "Makefile has no m4-exit target"

# X6 on a busy Mac: make bench skips (bench-guard.sh), and the row says skipped (busy), not FAIL. A stand-in make on
# PATH plays make bench; ZIVLET_M4_EXIT_LOGS keeps the real logs in build/m4-exit untouched.
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"
printf '#!/usr/bin/env bash\necho "$FAKE_BENCH_OUTPUT" >&2\nexit 2\n' >"$T/bin/make"
chmod +x "$T/bin/make"
x6() { PATH=$T/bin:$PATH ZIVLET_M4_EXIT_LOGS=$T/logs FAKE_BENCH_OUTPUT=$1 "$ROOT/Scripts/m4-exit.sh" --only X6; }
busy="Skipped: the Mac is busy (mediaanalysisd 150 % CPU). Re-run when idle or set ZIVLET_BENCH_FORCE=1."
out=$(x6 "$busy") || fail "a busy skip must not fail the exit run: $out"
assert_contains "$out" "X6 skipped (busy)"
assert_contains "$out" "mediaanalysisd 150 % CPU"
assert_file "$T/logs/X6.log"
out=$(x6 "bench: REGRESSION mov1080p60s_to_mp4_s" || true)
assert_contains "$out" "X6 FAIL"
assert_fails x6 "bench: REGRESSION mov1080p60s_to_mp4_s"
echo "PASS test-m4-exit"
