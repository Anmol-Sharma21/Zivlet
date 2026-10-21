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
echo "PASS test-m4-exit"
