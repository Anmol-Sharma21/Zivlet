#!/usr/bin/env bash
# coverage.sh keeps the test log; a failing test run prints the failing tests and their issues and reports no
# coverage (D-M7-8); a passing run prints one line per gated module from the llvm-cov table.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/kit-bin/codecov"
# A stand-in swift: `swift test` prints FAKE_SWIFT_LOG and exits FAKE_SWIFT_STATUS; `swift build` prints the bin path.
cat >"$T/bin/swift" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    test) cat "$FAKE_SWIFT_LOG"; exit "$FAKE_SWIFT_STATUS" ;;
    build) echo "$FAKE_BIN" ;;
    *) exit 9 ;;
esac
STUB
# A stand-in llvm-cov that prints a report table (column 8 = lines, column 9 = missed lines).
cat >"$T/bin/llvm-cov" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FAKE_BIN/llvm-cov.args"
echo "Filename Regions Missed Cover Functions Missed Executed Lines Missed Cover"
echo "ModA/a.swift 10 1 90% 5 0 100% 100 10 90.00%"
echo "ModB/b.swift 10 1 90% 5 0 100% 50 5 90.00%"
STUB
chmod +x "$T/bin/swift" "$T/bin/llvm-cov"
mkdir "$T/kit-bin/Fake.xctest"
run_coverage() {
    FAKE_BIN=$T/kit-bin FAKE_SWIFT_LOG=$T/swift.log FAKE_SWIFT_STATUS=$1 \
        ZIVLET_SWIFT=$T/bin/swift ZIVLET_LLVM_COV=$T/bin/llvm-cov ZIVLET_COVERAGE_DIR=$T/cov \
        GATED_MODULES="ModA ModB" "$ROOT/Scripts/coverage.sh" 2>&1
}

# (a) A failing run: both failing tests, their issue lines and the tail of the log; no coverage table; exit 1.
{
    echo "Building for debugging..."
    for i in $(seq 1 60); do echo "◇ Test filler$i() started."; done
    echo "✘ Test aDropShowsTheIsland() recorded an issue at NotchTests.swift:41:9: Expectation failed: (a → 3) < 2"
    echo "✘ Test aDropShowsTheIsland() failed after 0.2 seconds with 1 issue."
    echo "✘ Test theUndoKeepsTheButtons() recorded an issue at ResultCardTests.swift:88:5: Expectation failed: x"
    echo "✘ Test theUndoKeepsTheButtons() failed after 4.1 seconds with 1 issue."
    echo "✘ Test run with 900 tests in 80 suites failed after 60 seconds with 2 issues."
} >"$T/swift.log"
status=0; out=$(run_coverage 1) || status=$?
assert_eq "$status" "1" "a failing test run exits 1"
assert_contains "$out" "coverage: tests failed (log: $T/cov/test.log)"
assert_contains "$out" "✘ Test aDropShowsTheIsland() failed after 0.2 seconds"
assert_contains "$out" "✘ Test theUndoKeepsTheButtons() failed after 4.1 seconds"
assert_contains "$out" "NotchTests.swift:41:9: Expectation failed"
assert_contains "$out" "ResultCardTests.swift:88:5: Expectation failed"
assert_contains "$out" "Test run with 900 tests in 80 suites failed"
if grep -qE '[0-9]+/[0-9]+ +lines' <<<"$out"; then fail "a failed run must not print coverage: $out"; fi
if grep -qF "filler1()" <<<"$out"; then fail "only the last 40 lines of the log are printed: $out"; fi
assert_file "$T/cov/test.log"

# (b) A passing run prints the per-module lines as before and keeps the log too.
rm -rf "$T/cov"
echo "✔ Test run with 900 tests in 80 suites passed after 60 seconds." >"$T/swift.log"
out=$(run_coverage 0) || fail "a passing run above the gate must pass: $out"
assert_contains "$out" "ModA                  90/100   lines   90%"
assert_contains "$out" "ModB                  45/50    lines   90%"
assert_file "$T/cov/test.log"

# (c) Coverage under the gate still fails after a passing test run.
status=0; COVERAGE_GATE=95 run_coverage 0 >/dev/null || status=$?
assert_eq "$status" "1" "coverage under the gate exits 1"
# (d) The vendored headers the C++ shim includes (qpdf's inline code) are left out, so the table keeps its paths
# relative to Sources/ and the shim's own files are gated beside the Swift modules.
regex=$(sed -n 's/^-ignore-filename-regex=//p' "$T/kit-bin/llvm-cov.args")
[[ -n "$regex" ]] || fail "coverage.sh passes no -ignore-filename-regex"
grep -qE "$regex" <<<"/repo/Vendor/out/CQPDF.xcframework/macos-arm64/Headers/CQPDF/qpdf/QPDF.hh" ||
    fail "vendored headers are not ignored: $regex"
if grep -qE "$regex" <<<"/repo/Packages/ZivletKit/Sources/CZivletPDF/zivlet_pdf.cc"; then
    fail "the shim's own sources are ignored: $regex"
fi
for module in EnginePDF CZivletPDF; do
    grep -qE "^GATED_MODULES=.*[{ ]$module[} ]" "$ROOT/Scripts/coverage.sh" || fail "$module is not gated"
done
echo "PASS test-coverage"
