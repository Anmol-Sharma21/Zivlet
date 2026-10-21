# Performance baselines (P1-63, G-9)

`make bench` runs `Scripts/bench.sh` on the Mac in front of it, writes `build/bench/<timestamp>.json` and compares
the run with `baseline-<model>.json` in this folder through `Scripts/bench-compare.sh`. The first run on a Mac model
writes its baseline; commit it. Baselines are tagged `27-only`: they were measured on macOS 27 and say nothing about
macOS 26 (05 §8).

It needs `make app` (the Debug app, for the demo hooks and signposts) and `make release-check` (the Release app,
for idle wake-ups) first, and a logged-in session with a display. It stops only the app processes it starts.

## Busy Mac

Before measuring, `Scripts/bench-guard.sh` samples the Mac: the 1-minute load average (`vm.loadavg`) against the
core count (`hw.ncpu`) and the heaviest other process (`ps`, by CPU). The Mac is busy when one process uses more
than 50 % of a core or the load is above 0.5 per core. A busy Mac is sampled again every 10 s for up to 180 s; if it
stays busy, `make bench` measures nothing and exits with status 3 and one line that names the cause, for example:

    Skipped: the Mac is busy (mediaanalysisd 150 % CPU). Re-run when idle or set ZIVLET_BENCH_FORCE=1.

A skip is not a pass and not a regression: re-run on a quiet Mac. `make m4-exit` reports the X6 row as
`skipped (busy)` with that line. `ZIVLET_BENCH_FORCE=1` measures anyway (the sample then says `forced`);
`ZIVLET_BENCH_WAIT_STEP` and `ZIVLET_BENCH_WAIT_MAX` change the wait, in whole seconds.

Each run's JSON records the sample it started from as `load`: `load_1min`, `cores`, `load_per_core`,
`heaviest.process` and `heaviest.cpu_percent`, `busy`, `forced`, `samples` and `waited_s`. The gate only reads
`metrics`. The guard was added after the M4 exit run (G-M4-11), where `mediaanalysisd` (Photos analysis) used about
135 % CPU and failed the gate without a code change; the Mac14,9 baseline below predates it and has no `load`.

## Metrics

| Metric | How | Budget (10 §8.11, 05 P1-63) |
|---|---|---|
| `heic12mp_to_jpeg_ms` | 4032 × 3024 HEIC (`build/fixtures/full/srgb.heic`) → JPEG through `ImageEngine` (prepare, execute, verify), median of 5, `zivlet-bench` release build | ≤ 150 ms on an M1 |
| `mov1080p60s_to_mp4_s` | 60 s 1920 × 1080 MPEG-4 Part 2 MOV with B-frames (so it is re-encoded, not copied) → MP4 through `MediaEngine`, the vendored ffmpeg and `h264_videotoolbox` | ≤ 10 s |
| `drop_to_admit_ms` | `drop→admit` signpost of the Debug app, median of 5 demo conversions (`-ZivletDemoConvert`), each in a fresh launch | ≤ 50 ms |
| `drop_to_hud_ms` | `drop→hud` signpost of the same runs | ≤ 50 ms |
| `idle_wakeups`, `idle_cpu_percent` | Release app, 10 s after launch, last of three `top -stats pid,cpu,idlew` samples | 0 and 0.0 % |
| `tap_to_wheel_p95_ms` | p95 of the `trigger→frame` signpost over 50 demo shows (`-ZivletDemoWheel convert -ZivletDemoRepeat 50`): from the show to the wheel's first display-link callback | ≤ 16 ms at 120 Hz for a real drag |

Signpost durations come from `log show --signpost` (mach ticks over `hw.tbfrequency`), so no Instruments template
is needed.

The demo shows have no real input latency: they start at the show, not at the key event. The real-drag p95 at 120 Hz
and the M1 Air numbers are owner steps on that hardware (O-6).

## Gate

A run fails when a baseline metric is missing or more than 10 % worse. A regression must also be more than one unit
of the metric worse (1 ms, 1 s, 1 wake-up, 1 % CPU): sub-millisecond timings such as `drop_to_admit_ms` vary by
more than 10 % from run to run, and 10 % of a zero baseline would fail on any wake-up. A baseline may give a metric
a `slack` instead of the one-unit floor: the run-to-run spread measured on that Mac for timings that include
window-server work (the HUD and wheel panels coming on screen in a fresh launch).

## Mac14,9 (MacBook Pro, M2 Pro, 120 Hz), macOS 27.0 (26A428), 2026-10-21

Nine runs on the dev Mac while it was otherwise in use. The baseline is the run of 21:44; its slack is 6 ms for
`drop_to_hud_ms` and 4 ms for `tap_to_wheel_p95_ms`, from the spread below.

| Metric | Baseline | Range over the runs | Budget |
|---|---|---|---|
| HEIC 12 MP → JPEG | 29.5 ms | 27.3–29.5 ms | ≤ 150 ms (M1) |
| 1080p minute → MP4 | 8.97 s | 8.95–8.97 s | ≤ 10 s |
| drop → admit | 0.7 ms | 0.7–1.1 ms | ≤ 50 ms |
| drop → HUD | 15.9 ms | 12.5–21.2 ms | ≤ 50 ms |
| idle wake-ups, CPU | 0, 0.0 % | 0–1, 0.0 % | 0, 0.0 % |
| tap → wheel p95 (demo) | 19.3 ms | 17.0–22.0 ms | ≤ 16 ms (real drag) |

The demo tap → wheel p95 is above the 16 ms real-drag budget: each demo show swaps the wheel model and then waits for
the next display refresh before the interval ends. It is recorded here as measured; whether real drags meet 16 ms is
decided by the owner's measurement (O-6). One wake-up in 10 s was seen in two of the runs.
