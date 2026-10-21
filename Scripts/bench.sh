#!/usr/bin/env bash
# make bench (P1-63, P1-24 signpost, G-9): measures this Mac and compares with docs/plan/perf/baseline-<model>.json.
#   1. HEIC 12 MP → JPEG through ImageEngine (median of 5; budget ≤ 150 ms on an M1)
#   2. 1-minute 1080p MOV (MPEG-4 Part 2) → MP4 through the vendored ffmpeg with VideoToolbox (budget ≤ 10 s)
#   3. drop→admit and drop→HUD from the Debug app's signposts, median of 5 demo conversions (budget ≤ 50 ms)
#   4. idle wake-ups and CPU of the Release app 10 s after launch (budget 0 and 0.0 %)
#   5. tap→wheel p95 from the trigger→frame signpost over 50 DEBUG demo shows (no real event latency: the real-drag
#      p95 at 120 Hz is an owner step, O-6)
# First bench-guard.sh samples the load (G-M4-11): on a Mac kept busy by another process it waits a bounded time, then
# exits 3 with a "Skipped: the Mac is busy (...)" line instead of measuring (ZIVLET_BENCH_FORCE=1 measures anyway).
# Writes build/bench/<timestamp>.json with that sample as "load", then runs bench-compare.sh (the first run writes
# this Mac's baseline).
# Needs make app (Debug) and make release-check (Release) first; only the apps this script starts are stopped.
set -euo pipefail
source "$(dirname "$0")/env.sh"
JQ=/usr/bin/jq
OUT=$REPO_ROOT/build/bench
STAGE=$REPO_ROOT/Vendor/out/media-stage/Helpers
DEBUG_APP=$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app/Contents/MacOS/Zivlet
RELEASE_APP=$REPO_ROOT/build/ReleaseCheck/Build/Products/Release/Zivlet.app/Contents/MacOS/Zivlet
TICKS_PER_SECOND=$(sysctl -n hw.tbfrequency)
die() { echo "bench: $*" >&2; exit 1; }
note() { echo "bench: $*" >&2; }

[[ -x "$DEBUG_APP" ]] || die "no Debug app: run make app"
[[ -x "$RELEASE_APP" ]] || die "no Release app: run make release-check"
[[ -x "$STAGE/ffmpeg" ]] || die "no vendored ffmpeg: run make vendor"
load=$("$REPO_ROOT/Scripts/bench-guard.sh") || exit $? # 3: busy, skipped (the guard printed why)
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/run.XXXXXX")
started=()
cleanup() {
    local pid
    for pid in "${started[@]+"${started[@]}"}"; do kill "$pid" 2>/dev/null || true; done
    rm -rf "$WORK"
}
trap cleanup EXIT

# Durations in ms of one signpost interval in one process since a time, one per line, begin and end paired by id.
signpost_ms() { # <pid> <name> <since>
    /usr/bin/log show --start "$3" --signpost --style ndjson \
        --predicate "subsystem == \"app.zivlet.Zivlet\" AND processID == $1" 2>/dev/null |
        "$JQ" -r --arg name "$2" 'select(.eventType == "signpostEvent" and .signpostName == $name)
            | "\(.signpostID) \(.signpostType) \(.machTimestamp)"' |
        awk -v hz="$TICKS_PER_SECOND" '$2 == "begin" { b[$1] = $3 } $2 == "end" && ($1 in b) {
            printf "%.3f\n", ($3 - b[$1]) * 1000 / hz; delete b[$1] }'
}

# Median and p95 of numbers on stdin (empty → nothing).
median() { sort -n | awk '{ v[NR] = $1 } END { if (NR) print v[int((NR + 1) / 2)] }'; }
p95() { sort -n | awk '{ v[NR] = $1 } END { if (NR) { i = int(NR * 0.95 + 0.999); print v[i] } }'; }

# Starts an app binary with arguments in the background; its PID goes to $launched.
launch() {
    "$@" >/dev/null 2>&1 &
    launched=$!
    started+=("$launched")
}
stop() { kill "$1" 2>/dev/null || true; wait "$1" 2>/dev/null || true; }
now() { date '+%Y-%m-%d %H:%M:%S'; }

engine_metrics() {
    (cd "$KIT" && swift build -c release --product zivlet-bench >/dev/null) || die "zivlet-bench did not build"
    local tool
    tool="$(cd "$KIT" && swift build -c release --show-bin-path)/zivlet-bench"
    "$REPO_ROOT/Fixtures/generate.sh" --set full >/dev/null
    heic_ms=$("$tool" image "$REPO_ROOT/build/fixtures/full/srgb.heic" jpg 5)
    local mov=$OUT/source-1080p-60s.mov
    [[ -s "$mov" ]] || "$STAGE/ffmpeg" -hide_banner -nostdin -loglevel error -y \
        -f lavfi -i testsrc2=d=60:s=1920x1080:r=30 -f lavfi -i sine=d=60:sample_rate=48000 \
        -c:v mpeg4 -bf 2 -q:v 12 -c:a aac -ac 2 "$mov"
    mov_s=$("$tool" media "$mov" mp4 "$STAGE" | awk '{ printf "%.2f", $1 / 1000 }')
}

DROP_RUNS=${BENCH_DROP_RUNS:-5}

drop_metrics() {
    local run since admits=() huds=()
    for run in $(seq 1 "$DROP_RUNS"); do
        mkdir -p "$WORK/drop$run"
        cp "$REPO_ROOT/build/fixtures/small/srgb.png" "$WORK/drop$run/photo.png"
        since=$(now)
        launch "$DEBUG_APP" -ZivletDemoConvert "$WORK/drop$run/photo.png" jpg
        sleep 5
        stop "$launched"
        admits+=("$(signpost_ms "$launched" "drop→admit" "$since" | head -1)")
        huds+=("$(signpost_ms "$launched" "drop→hud" "$since" | head -1)")
    done
    admit_ms=$(printf '%s\n' "${admits[@]}" | grep . | median || true)
    hud_ms=$(printf '%s\n' "${huds[@]}" | grep . | median || true)
}

idle_metrics() {
    launch "$RELEASE_APP"
    sleep 10
    local row
    row=$(top -l 3 -s 1 -stats pid,cpu,idlew -pid "$launched" | awk -v p="$launched" '$1 == p' | tail -1)
    stop "$launched"
    idle_cpu=$(awk '{ print $2 }' <<<"$row")
    idle_wakeups=$(awk '{ print $3 + 0 }' <<<"$row")
}

wheel_metrics() {
    local since
    since=$(now)
    launch "$DEBUG_APP" -ZivletDemoWheel convert -ZivletDemoRepeat 50
    sleep 26
    stop "$launched"
    local shows
    shows=$(signpost_ms "$launched" "trigger→frame" "$since")
    wheel_count=$(grep -c . <<<"$shows" || true)
    wheel_p95=$(p95 <<<"$shows")
}

note "engines (HEIC 12 MP → JPEG, 1080p minute → MP4)…"
engine_metrics
note "drop → admit and drop → HUD ($DROP_RUNS demo conversions)…"
drop_metrics
note "idle wake-ups (Release app, 10 s)…"
idle_metrics
note "tap → wheel (50 demo shows)…"
wheel_metrics
note "trigger→frame intervals seen: $wheel_count of 50"

model=$(sysctl -n hw.model)
stamp=$(date '+%Y%m%d-%H%M%S')
result=$OUT/$stamp.json
"$JQ" -n --arg model "$model" --arg macos "$(sw_vers -buildVersion)" --arg date "$stamp" \
    --arg heic "$heic_ms" --arg mov "$mov_s" --arg admit "${admit_ms:-}" --arg hud "${hud_ms:-}" \
    --arg wake "${idle_wakeups:-}" --arg cpu "${idle_cpu:-}" --arg wheel "${wheel_p95:-}" \
    --argjson load "$load" '
    def num: if . == "" then null else tonumber end;
    { model: $model, macos: $macos, date: $date, note: "27-only", load: $load,
      metrics: ({ heic12mp_to_jpeg_ms: ($heic | num), mov1080p60s_to_mp4_s: ($mov | num),
        drop_to_admit_ms: ($admit | num), drop_to_hud_ms: ($hud | num), idle_wakeups: ($wake | num),
        idle_cpu_percent: ($cpu | num), tap_to_wheel_p95_ms: ($wheel | num) }
        | with_entries(select(.value != null))) }' >"$result"
cat "$result"
"$REPO_ROOT/Scripts/bench-compare.sh" "$result" "$REPO_ROOT/docs/plan/perf/baseline-$model.json"
