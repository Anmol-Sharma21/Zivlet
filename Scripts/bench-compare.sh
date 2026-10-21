#!/usr/bin/env bash
# Regression gate for make bench (P1-63, G-9): bench-compare.sh <run.json> <baseline.json>
# Fails when a baseline metric is missing from the run or is more than 10 % worse; every metric is lower-is-better.
# A regression must also be more than one unit of the metric worse (1 ms, 1 s, 1 wake-up, 1 % CPU), so noise in
# sub-millisecond timings and a zero baseline do not fail on their own. A baseline may also give a metric a
# "slack": the run-to-run spread measured on that Mac (UI timings that include window-server work), which then
# replaces the one-unit floor. Without a baseline file the run becomes the baseline for this Mac (tagged with its
# model and "27-only", 05 §8).
set -euo pipefail
JQ=/usr/bin/jq
TOLERANCE=${BENCH_TOLERANCE:-1.10}
FLOOR=${BENCH_FLOOR:-1}
die() { echo "bench-compare: $*" >&2; exit 1; }

(($# == 2)) || die "usage: bench-compare.sh <run.json> <baseline.json>"
RUN=$1 BASELINE=$2
[[ -x "$JQ" ]] || die "jq is missing at $JQ"
[[ -f "$RUN" ]] || die "no run file $RUN"
"$JQ" -e '.metrics | type == "object"' "$RUN" >/dev/null || die "$RUN has no metrics object"

if [[ ! -f "$BASELINE" ]]; then
    mkdir -p "$(dirname "$BASELINE")"
    "$JQ" '.note = "27-only"' "$RUN" >"$BASELINE"
    echo "baseline written: $BASELINE ($("$JQ" -r '.model' "$RUN"))"
    exit 0
fi

# One line per baseline metric that the run is missing or exceeds: "<name> <run> <baseline>".
problems=$("$JQ" -r --slurpfile base "$BASELINE" --argjson tolerance "$TOLERANCE" --argjson floor "$FLOOR" '
    .metrics as $run
    | ($base[0].slack // {}) as $slack
    | $base[0].metrics | to_entries[]
    | .key as $name | .value as $limit | ($run[$name] // null) as $value
    | if $value == null then "\($name) missing (baseline \($limit))"
      elif $value > ([$limit * $tolerance, $limit + ($slack[$name] // $floor)] | max)
      then "\($name) \($value) (baseline \($limit), more than 10 % worse)"
      else empty end' "$RUN")
if [[ -n "$problems" ]]; then
    echo "$problems" >&2
    die "regression against $BASELINE"
fi
echo "bench OK: $("$JQ" -r '.metrics | length' "$RUN") metrics within 10 % of $(basename "$BASELINE")"
