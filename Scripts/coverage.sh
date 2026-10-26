#!/usr/bin/env bash
# Line coverage per module over every test bundle; fails below the gate (owner rule: 80 %).
source "$(dirname "$0")/env.sh"
GATE="${COVERAGE_GATE:-80}"
GATED_MODULES="${GATED_MODULES:-ZivletCore ZivletTrigger ZivletWheelCore ZivletEngineKit EngineMedia EngineImage ZivletRuntime ZivletTriggerHost ZivletWheel ZivletActions ZivletSettings ZivletUI ZivletNotchCore ZivletNotch ZivletShelfCore}"
cd "$KIT"
swift test --enable-code-coverage >/dev/null
BIN="$(swift build --show-bin-path)"
objects=()
for bundle in "$BIN"/*.xctest; do
    objects+=(-object "$bundle/Contents/MacOS/$(basename "$bundle" .xctest)")
done
report="$(xcrun llvm-cov report -instr-profile "$BIN/codecov/default.profdata" "${objects[@]}" \
    -ignore-filename-regex='(Tests|\.build)/')"
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
