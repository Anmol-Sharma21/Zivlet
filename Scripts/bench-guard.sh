#!/usr/bin/env bash
# Busy guard for make bench (G-M4-11): samples this Mac before anything is measured, so a background job (Photos
# analysis, Spotlight, a build) cannot fail the regression gate on its own. The Mac is busy when another process uses
# more than MAX_PROCESS_CPU % of a core, or when the 1-minute load average is above MAX_LOAD_PER_CORE per core.
# Busy: sample again every WAIT_STEP s for up to WAIT_MAX s; still busy, exit 3 with one line naming the cause.
# Prints the last sample as JSON on stdout (bench.sh records it as "load"). Exit 0 quiet or forced, 3 busy, 2 bad
# input. ZIVLET_BENCH_FORCE=1 measures anyway; ZIVLET_BENCH_WAIT_STEP and ZIVLET_BENCH_WAIT_MAX change the wait;
# ZIVLET_BENCH_SAMPLER replaces the sampler with a command printing "<load> <cores> <cpu %> <process>" (script tests).
set -euo pipefail
JQ=/usr/bin/jq
MAX_PROCESS_CPU=50
MAX_LOAD_PER_CORE=0.5
STATUS_BUSY=3
STATUS_BAD_INPUT=2
WAIT_STEP=${ZIVLET_BENCH_WAIT_STEP:-10}
WAIT_MAX=${ZIVLET_BENCH_WAIT_MAX:-180}
FORCE=${ZIVLET_BENCH_FORCE:-0}
SAMPLER=${ZIVLET_BENCH_SAMPLER:-}
bad() { echo "bench-guard: $*" >&2; exit "$STATUS_BAD_INPUT"; }

[[ "$WAIT_STEP" =~ ^[0-9]+$ ]] || bad "ZIVLET_BENCH_WAIT_STEP must be whole seconds, got [$WAIT_STEP]"
[[ "$WAIT_MAX" =~ ^[0-9]+$ ]] || bad "ZIVLET_BENCH_WAIT_MAX must be whole seconds, got [$WAIT_MAX]"
[[ -x "$JQ" ]] || bad "jq is missing at $JQ"

# "<load 1 min> <cores> <cpu %> <name>" for this Mac: the heaviest process other than ps itself, by name without
# its folder (names may contain spaces, so the name is last).
sample_mac() {
    local load cores heaviest
    load=$(sysctl -n vm.loadavg | awk '{ print $2 }')
    cores=$(sysctl -n hw.ncpu)
    heaviest=$(ps -Aro pcpu=,comm= | awk '{ cpu = $1; sub(/^ *[^ ]+ +/, ""); sub(/.*\//, "")
        if ($0 != "ps") { print cpu, $0; exit } }')
    echo "$load $cores ${heaviest:-0 none}"
}

take_sample() { if [[ -n "$SAMPLER" ]]; then bash -c "$SAMPLER"; else sample_mac; fi; }

# Reads a sample into load, cores, cpu and process, failing on anything that is not one.
parse_sample() {
    local number='^[0-9]+([.][0-9]+)?$'
    read -r load cores cpu process <<<"$1" || true
    [[ "$load" =~ $number && "$cpu" =~ $number ]] || bad "unreadable sample [$1]"
    [[ "$cores" =~ ^[0-9]+$ ]] && ((cores > 0)) || bad "unreadable core count in sample [$1]"
    [[ -n "$process" ]] || bad "no process name in sample [$1]"
}

# Empty when quiet, else the cause for the skip message.
busy_reason() {
    local cpu_whole
    cpu_whole=$(printf '%.0f' "$cpu")
    if awk -v c="$cpu" -v m="$MAX_PROCESS_CPU" 'BEGIN { exit !(c > m) }'; then
        echo "$process $cpu_whole % CPU"
    elif awk -v l="$load" -v n="$cores" -v m="$MAX_LOAD_PER_CORE" 'BEGIN { exit !(l > n * m) }'; then
        echo "load $(printf '%.1f' "$load") on $cores cores; heaviest $process $cpu_whole % CPU"
    fi
}

print_sample() { # <busy true|false>
    "$JQ" -n --argjson load "$load" --argjson cores "$cores" --argjson cpu "$cpu" --arg process "$process" \
        --argjson busy "$1" --argjson forced "$([[ "$FORCE" == 1 ]] && echo true || echo false)" \
        --argjson samples "$samples" --argjson waited "$waited" \
        '{ load_1min: ($load + 0), cores: $cores, load_per_core: ($load / $cores * 100 | round / 100),
           heaviest: { process: $process, cpu_percent: ($cpu + 0) }, busy: $busy, forced: $forced,
           samples: $samples, waited_s: $waited }'
}

load="" cores="" cpu="" process="" samples=0 waited=0
while :; do
    parse_sample "$(take_sample)"
    samples=$((samples + 1))
    reason=$(busy_reason)
    [[ -z "$reason" ]] && { print_sample false; exit 0; }
    if [[ "$FORCE" == 1 ]]; then
        echo "bench: the Mac is busy ($reason); ZIVLET_BENCH_FORCE=1, measuring anyway" >&2
        print_sample true
        exit 0
    fi
    ((waited + WAIT_STEP <= WAIT_MAX && WAIT_STEP > 0)) || break
    echo "bench: the Mac is busy ($reason); waiting ${WAIT_STEP} s (${waited} of ${WAIT_MAX} s)" >&2
    sleep "$WAIT_STEP"
    waited=$((waited + WAIT_STEP))
done
print_sample true
echo "Skipped: the Mac is busy ($reason). Re-run when idle or set ZIVLET_BENCH_FORCE=1." >&2
exit "$STATUS_BUSY"
