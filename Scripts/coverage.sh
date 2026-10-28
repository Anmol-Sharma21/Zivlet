#!/usr/bin/env bash
# Line coverage per module over every test bundle; fails below the gate (owner rule: 80 %). CZivletPDF is the C++ shim
# around qpdf (D-M7-16), gated like a Swift module; qpdf's vendored headers are left out of the table.
source "$(dirname "$0")/env.sh"
GATE="${COVERAGE_GATE:-80}"
GATED_MODULES="${GATED_MODULES:-ZivletCore ZivletTrigger ZivletWheelCore ZivletEngineKit EngineMedia EngineImage ZivletRuntime ZivletTriggerHost ZivletWheel ZivletActions ZivletSettings ZivletUI ZivletNotchCore ZivletNotch ZivletShelfCore ZivletBox ZivletIPC ZivletWorkerCore EngineVision EnginePDF CZivletPDF}"
# ZIVLET_SWIFT, ZIVLET_LLVM_COV and ZIVLET_COVERAGE_DIR replace the tools and the log folder (script tests only).
SWIFT="${ZIVLET_SWIFT:-swift}"
LLVM_COV="${ZIVLET_LLVM_COV:-xcrun llvm-cov}"
LOG_DIR="${ZIVLET_COVERAGE_DIR:-$REPO_ROOT/build/coverage}"
LOG="$LOG_DIR/test.log"
TAIL_LINES=40

# A failed run names its failing tests and issues and reports no coverage (D-M7-8).
report_failed_run() {
    echo "coverage: tests failed (log: $LOG)" >&2
    grep -E '✘|recorded an issue|Expectation failed| error: ' "$LOG" >&2 || true
    echo "coverage: last $TAIL_LINES lines of the log:" >&2
    tail -n "$TAIL_LINES" "$LOG" >&2
}

mkdir -p "$LOG_DIR"
cd "$KIT"
if ! "$SWIFT" test --enable-code-coverage >"$LOG" 2>&1; then
    report_failed_run
    exit 1
fi
BIN="$("$SWIFT" build --show-bin-path)"
objects=()
for bundle in "$BIN"/*.xctest; do
    objects+=(-object "$bundle/Contents/MacOS/$(basename "$bundle" .xctest)")
done
report="$($LLVM_COV report -instr-profile "$BIN/codecov/default.profdata" "${objects[@]}" \
    -ignore-filename-regex='(Tests|\.build|Vendor)/')"
status=0
for module in $GATED_MODULES; do
    read -r covered total < <(awk -v m="$module/" '
        index($1, m) == 1 { total += $8; missed += $9 }
        END { print total - missed, total }' <<<"$report")
    # bash 3.2 evaluates both ternary arms, so an empty module must be handled before dividing.
    if (( total == 0 )); then
        printf '%-18s no executable lines yet\n' "$module"
        continue
    fi
    pct=$(( covered * 100 / total ))
    printf '%-18s %5d/%-5d lines  %3d%%\n' "$module" "$covered" "$total" "$pct"
    if (( pct < GATE )); then status=1; fi
done
exit $status
