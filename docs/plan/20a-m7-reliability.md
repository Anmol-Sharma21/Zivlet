# 20a — M7 Stream R: test reliability under load

Part of [20-implementation-plan-m7](20-implementation-plan-m7.md). Conventions: index §6. Decisions: D-M7-3 to
D-M7-9. Gap audit: index §2.1. Swift below is specification-grade and was not compiled.

Why this stream comes first. M5a, M5b and M6 each ended with an exit run that failed on timing alone and passed when
rerun by name at a lower load (19-m6-record §11: X2's 50 ms test failed in all three exit scripts at load 2–13; the
M6 re-verify saw it fail 6 of 6 times inside exit scripts at load 10–31). A gate that fails on a busy Mac and passes on
a quiet one tells nobody anything. The rule this stream adopts (D-M7-3):

- **Unit tests test behaviour, never the scheduler.** They use injected clocks (`ManualClock`, which exists in
  `NotchTestSupport`), readiness signals from children, structural facts (a pre-warmed panel was used, no panel was
  built on the drop path) and per-thread CPU time where "work done on the main thread" is the property.
- **Real-time budgets are not loosened and not dropped.** They move to one dedicated target, `ZivletTimingTests`, run by
  `make timing` through `Scripts/timing.sh`. The script records the load average before and after, waits up to
  10 minutes for the 1-minute load to fall to the stated limit, and **refuses to judge** above it: it prints
  `timing: not judged (load 1m 12.4 > 3.0)` and exits 3. Exit rows report exit 3 as `skip` (which, as in M6, makes the
  exit script exit 1: a skip is not a pass).
- **The stated load limit is 3.0** (the 1-minute load average; half of this Mac's 6 performance cores,
  `hw.perflevel0.physicalcpu`). `ZIVLET_TIMING_MAX_LOAD` may lower it, never raise it above the P-core count; the script
  refuses a higher value.
- The record states, for every timing row, the load at which it was judged, or that it was not judged.

Measured for this plan (this session, `m7` at `5107be7`, load 3.7–9.3, five runs of the four tests by name): all
passed. `cancellingARunningEncodeStopsFFmpegQuickly` took **1.459–1.490 s** against its 1.5 s bound in every run, so it
sits 10–40 ms from failing at any load. `aChildIgnoringSIGINTIsKilledAfterTheGrace` took 1.375–1.386 s,
`aDropShowsTheIslandWithin50ms` and `anUndoThatChangedNothingKeepsTheButtons` passed (their wall time inside the
test is not printed).

---

## Task R0 — Baseline

| Field | Value |
|---|---|
| Goal | Record the starting state before any change: `nice -n 10 make test lint coverage app` on `m7` at `5107be7`, with the load average before and after each |
| Acceptance | The four results and loads written in the record's baseline table; any failure rerun once by name and both results kept |
| Effort | S |

No commit (record only, written in F4).

---

## Task R1 — `coverage.sh` shows the tests that failed (D-M7-8)

| Field | Value |
|---|---|
| Goal | Today `swift test --enable-code-coverage >/dev/null` under `set -e` exits 1 with no output when a test fails, so a red coverage gate shows nothing. Keep the test log in `build/coverage/test.log`; on failure print `coverage: tests failed (log: build/coverage/test.log)`, then every `✘ Test …` line, every `recorded an issue` / `Expectation failed` line with its location, and the last 40 lines of the log; exit 1 **before** the coverage table (a coverage number from a failed run is not reported) |
| Acceptance | `Scripts/tests/test-coverage.sh` with a stub `swift` on `PATH` (the pattern of the other script tests): (a) stub test run fails with two `✘` lines → the script exits 1 and prints both names and the issue lines; (b) stub test run passes and the stub `llvm-cov` prints a table → the per-module lines are printed as today; (c) the log file exists in both cases. The stub is selected by `ZIVLET_SWIFT` / `ZIVLET_LLVM_COV` (script tests only) |
| Effort | S |

**Files:** `Scripts/coverage.sh`, create `Scripts/tests/test-coverage.sh`.

RED: `bash Scripts/tests/test-coverage.sh` → case (a) fails: "expected the failing test name in the output, got
nothing". Commit `fix(scripts): show the failing tests when the coverage run fails`.

---

## Task R2 — Every exit row makes the fixtures it needs (D-M7-9)

| Field | Value |
|---|---|
| Goal | `m5a-exit.sh` X3 (`make notch-demo`) uses `build/fixtures/small/srgb.heic`, which only X2's `demo_file` made (`make fixtures`); run alone (`--only X3`) in a fresh clone it fails with "run make fixtures". `Scripts/demo-notch.sh` makes the fixture when it is missing (as `demo-box.sh` already does); the same audit covers every row of `m4-exit.sh`, `m5a-exit.sh`, `m5b-exit.sh` and `m6-exit.sh` (read this session: only `demo-notch.sh` refuses; `demo-box.sh` makes its own; `demo-copy-text.sh` renders its own inputs) |
| Acceptance | `Scripts/tests/test-m5a-exit.sh` gains a case: X3 alone with an empty fixtures folder and a stub `make` that records its targets → `fixtures` is called before the demo, and the row passes on the stub. `test-m6-exit.sh` gains the same check for every row that names a fixture (none today; the test asserts the list so a new one is caught) |
| Effort | S |

**Files:** `Scripts/demo-notch.sh`, `Scripts/tests/test-m5a-exit.sh`, `Scripts/tests/test-m6-exit.sh`.

RED: the new X3 case fails with `error: …/srgb.heic not found; run make fixtures`. Commit `fix(scripts): the notch
demo makes its own fixture`.

---

## Task R3 — The timing target and its load guard (D-M7-3)

| Field | Value |
|---|---|
| Goal | A test target `ZivletTimingTests` (depends on `ZivletUI`, `ZivletEngineKit`, `EngineMedia`, `NotchTestSupport`, `EngineTestSupport`) whose suites run only when `ZIVLET_TIMING=1` (`.enabled(if:)`), so `make test` never judges wall time. `Scripts/timing.sh` (sourced env, `set -euo pipefail`): reads `sysctl -n vm.loadavg`, waits (poll every 15 s, at most 10 min) until the 1-minute value ≤ `MAX_LOAD`; then runs `swift test --filter ZivletTimingTests` with `ZIVLET_TIMING=1`, prints `timing: load before 2.1, after 2.6, limit 3.0` and each suite's measured values; exits 0 (judged, passed), 1 (judged, failed) or 3 (not judged). Every timing test prints its measured value (`timing: drop→island p95 18.2 ms of 50 ms`) through `FileHandle.standardError`, not `print` |
| Acceptance | `Scripts/tests/test-timing.sh` with `ZIVLET_LOADAVG` (a fake load source) and a stub `swift`: load 1.0 → runs, exit 0; load 9.0 for the whole wait (wait shortened by `ZIVLET_TIMING_WAIT=0`) → `not judged`, exit 3, `swift` never called; `ZIVLET_TIMING_MAX_LOAD=8` on a 6-P-core Mac (`ZIVLET_PCORES=6`) → refused, exit 2 |
| Effort | M |

**Files:** `Package.swift` (test target `ZivletTimingTests`), create `Tests/ZivletTimingTests/TimingGate.swift`,
`Scripts/timing.sh`, `Scripts/tests/test-timing.sh`, `Makefile` (`timing:` target; `notch-timing` becomes an alias of
`timing` filtered to the notch suite, so X2's command keeps working).

RED: `bash Scripts/tests/test-timing.sh` → `Scripts/timing.sh: No such file`. Commit `test(timing): a timing target
that judges real time only below a stated load`.

---

## Task R4 — The notch HUD's 50 ms test (G-M5b-5, D-M7-4)

The budget (P1-40: a drop shows its HUD in ≤ 50 ms) stays. What the unit test can check without a quiet scheduler:

1. the drop path uses the pre-warmed host and builds no panel (D-N8, D-N9: the reason the budget is reachable);
2. the island panel is on screen with the collapsed frame after `prepare` + `show` (unchanged);
3. the main thread's **CPU time** for `prepare` + `show` is under 50 ms (`clock_gettime(CLOCK_THREAD_CPUTIME_ID)`),
   which a loaded scheduler cannot inflate (waiting is not CPU time);
4. the `drop→island` signpost interval is begun and ended once (a recording `HUDSignposting` seam; today it is an
   `OSSignposter` field).

The wall-clock check moves to `ZivletTimingTests.NotchHUDTiming` (20 drops, p95 ≤ 50 ms, judged by R3). X2 in
`m5a-exit.sh` keeps parsing the in-app `drop→island` signpost from the log and now also prints its duration; it judges
that duration against 50 ms only when R3's guard says the load is under the limit, else prints `not judged` (exit 3,
row `skip`).

| Field | Value |
|---|---|
| Goal | `NotchHUDTimingTests` (in `ZivletUITests`) becomes `NotchHUDDropPathTests` with checks 1–4; `NotchHUD` and `IslandHosts` gain a `panelsBuilt` counter (internal, test seam) and an injected `HUDSignposting` (default: the existing signposter) |
| Acceptance | Each check is seen to fail first: (1) a variant that closes the pre-warmed hosts before the drop → `panelsBuilt == 1` fails the test; (3) a test-only `show` that spins 60 ms of CPU fails the CPU check; (4) a recorder with no `end` fails. Run 20 times with `Scripts/flaky-watch.sh` (`ZIVLET_WATCH_COMMAND` set to this suite) while `make test` runs beside it: 20/20 pass |
| Effort | M |

**Files:** `Sources/ZivletUI/Notch/NotchHUD.swift`, `Sources/ZivletNotch/IslandHosts.swift`, create
`Sources/ZivletUI/Notch/HUDSignposting.swift`; rename `Tests/ZivletUITests/NotchHUDTimingTests.swift` →
`NotchHUDDropPathTests.swift`; create `Tests/ZivletTimingTests/NotchHUDTiming.swift`; `Scripts/m5a-exit.sh` (X2),
`Scripts/tests/test-m5a-exit.sh`.

```swift
@Test func aDropUsesThePrewarmedHostAndLittleMainThreadTime() throws {
    let displays = try FakeDisplayProvider.notchOnly()
    let hosts = IslandHosts(provider: displays)
    defer { hosts.close() }
    let signposts = RecordingSignposts()
    let hud = NotchHUD(hosts: hosts, provider: displays, signposts: signposts)
    let built = hosts.panelsBuilt
    let cpu = ThreadCPUTime.measure {
        hud.prepare(near: CGPoint(x: -4500, y: -4500))
        hud.show(try! HUDFx.snapshot(submitted: 1))
    }
    #expect(hosts.panelsBuilt == built)
    #expect(try #require(hosts.host(on: 1)).isVisible)
    #expect(cpu < .milliseconds(50))
    #expect(signposts.intervals == ["drop→island"])
}
```

RED: `value of type 'IslandHosts' has no member 'panelsBuilt'`. Commits `test(notch): check the drop path's structure
and CPU time instead of wall time`, `test(timing): the 50 ms drop budget in the timing target`.

---

## Task R5 — `SubprocessRunner`'s grace test (G-M6-9, D-M7-5)

Cause, read from the test: the child is `/bin/sh -c "trap '' INT; sleep 100"` and the test sends the cancel after a
fixed 300 ms sleep. Under load the shell may not have run `trap` yet; SIGINT then ends it at once and the test sees
0.41 s, *shorter* than the grace (the M6 baseline's failure). A loaded scheduler can also stretch the upper bound
(`< 2 s`).

| Field | Value |
|---|---|
| Goal | The child prints `ready` after `trap`; the test waits for that line through `run(_:onSpawn:onLine:)` before cancelling (no fixed sleep). The runner is built with `SubprocessRunner(teardownGrace: .milliseconds(300))` (the initializer exists). Checks: the task throws `.cancelled`; elapsed ≥ the grace (a lower bound no scheduler can break, since the SIGKILL timer cannot fire early); the process group is gone (`groupIsGone`, existing helper, its 500 ms window widened to 5 s because it is a poll that ends at the first ESRCH). The same readiness change applies to `teardownIsPromptWhileManyOtherChildrenRun`, whose `< 1.5 s` bound moves to `ZivletTimingTests.SubprocessTiming` with the production grace (1 s, P1-20) and the bound "grace + 0.5 s" |
| Acceptance | With the readiness line removed from the child script (a test-only variant), the test fails at least once in 20 runs under `make test` load (the race, reproduced); with it, 20/20 pass under the same load (`flaky-watch.sh`) |
| Effort | S |

**Files:** `Tests/ZivletEngineKitTests/SubprocessRunnerTests.swift`, create
`Tests/ZivletTimingTests/SubprocessTiming.swift`.

RED: the reproduction run (without the readiness line) recorded in the record with its failure count. Commit
`test(enginekit): wait for the child's ready line before cancelling (G-M6-9)`.

---

## Task R6 — EngineMedia's cancel test and the NFR-9 question (D-M7-6)

What the 1.5 s bound covers. NFR-9 (01-prd) says the ffmpeg process group is gone ≤ 1 s after a cancel; P1-20 sends
SIGINT, then SIGKILL at +1 s. The test's 1.5 s bound is already looser than NFR-9, and the measured 1.46–1.49 s (above)
is over NFR-9's 1 s. Either ffmpeg (libvpx-vp9, mid-encode) ignores SIGINT until the SIGKILL and the reap and pipe
drain take ~0.45 s, or ffmpeg exits on SIGINT after ~1.45 s of flushing. Nobody has measured which. This task finds
out and does **not** change NFR-9 or the grace (G-M7-3, OS-M7-7).

| Field | Value |
|---|---|
| Goal | (1) `MediaIntegrationTests.cancellingARunningEncodeStopsFFmpegQuickly` checks behaviour only: the job throws `JobError.cancelled`; the spawned PID's group is gone (`groupIsGone` within 5 s); the staged file does not exist; the runner sent SIGINT before SIGKILL (a recording `ChildSignalling` seam on `ChildProcess.terminate(grace:)`, default = `killpg`). (2) `ZivletTimingTests.MediaCancelTiming` measures, at production grace: cancel → SIGINT sent, SIGINT → child exit (and whether the exit was SIGKILL or a normal exit), exit → reap, reap → `task.value` returned; judged against NFR-9 (group gone ≤ 1 s) and printed. (3) The record states the split and whether NFR-9 is met; if not, OS-M7-7 asks the owner (shorter grace for ffmpeg, a `q` on stdin before SIGINT, or a budget change) |
| Acceptance | (1) is seen to fail first by a seam that drops SIGINT (only SIGKILL) → the order check fails. (2) prints the four intervals and exits 3 above the load limit |
| Effort | M |

**Files:** `Sources/ZivletEngineKit/SubprocessSpawn.swift` (`ChildSignalling` seam, default unchanged),
`Tests/EngineMediaTests/MediaIntegrationTests.swift`, create `Tests/ZivletTimingTests/MediaCancelTiming.swift`.

RED: `cannot find 'ChildSignalling' in scope`. Commits `test(media): check what a cancel does, not how long it
takes`, `test(timing): measure where an ffmpeg cancel spends its time`.

---

## Task R7 — `ResultCardTests.anUndoThatChangedNothingKeepsTheButtons` (D-M7-7)

Cause, read from the code: `ResultHUD` defaults to `SystemClock()`. After the undo reply the success card's 4 s linger
restarts (`restartLinger`); the test then checks `isLingering`. A loaded scheduler that delays the test past the 4 s
deadline lets `scheduleExpiry` close the card first, so `visibleButtons` is empty.

| Field | Value |
|---|---|
| Goal | The test passes `clock: ManualClock()` (from `NotchTestSupport`, already a dependency of `ZivletUITests`); time never moves unless the test moves it. A second test advances the manual clock past the linger and expects the card closed, which pins the expiry path that the flake was hiding. Audit every other `ResultHUD(`/`ActionHUD(` built in `ZivletUITests` without a clock and give each a `ManualClock` unless it tests real sleep (list printed in the commit message body) |
| Acceptance | With `SystemClock` and a test-only 4.1 s pause before the check, the old test fails (the race, reproduced once); with `ManualClock` the same pause passes |
| Effort | S |

**Files:** `Tests/ZivletUITests/ResultCardTests.swift` (and any file the audit finds).

RED: the reproduction with the pause. Commit `test(ui): result card tests run on a manual clock`.

---

## Task R8 — Proof under load

| Field | Value |
|---|---|
| Goal | Each fixed test (R4, R5, R6 (1), R7) is run 20 times by name with `Scripts/flaky-watch.sh` while `nice -n 10 make test` runs beside it, and the load average is printed before and after each batch |
| Acceptance | 20/20 for each; the record lists the four batches with their loads. A failure is investigated, not rerun away |
| Effort | S |

No commit (record only).

---

## Decisions of this stream (copied to index §4)

| ID | Decision |
|---|---|
| D-M7-3 | Unit tests never judge wall time; real-time budgets live in `ZivletTimingTests`, run by `make timing`, which waits up to 10 min for the 1-minute load to reach 3.0 (half the P-cores; may be lowered, never raised past the P-core count) and otherwise prints "not judged" and exits 3. Exit rows report that as skip |
| D-M7-4 | The notch HUD test checks the pre-warmed host, the island's frame, main-thread CPU time < 50 ms and the signpost; the 50 ms wall budget is judged in the timing target and from the in-app `drop→island` signpost in X2 |
| D-M7-5 | `SubprocessRunner` tests wait for the child's `ready` line; they use a 300 ms grace and check only the lower bound and the group's end; the upper bound is a timing test |
| D-M7-6 | The ffmpeg cancel test checks cancelled, group gone, staged file removed, SIGINT before SIGKILL; the wall time is measured and split in the timing target against NFR-9 (1 s), which is not changed here |
| D-M7-7 | HUD tests run on `ManualClock` unless they test real sleeping |
| D-M7-8 | `coverage.sh` keeps the test log, prints failing tests and issues, and reports no coverage from a failed run |
| D-M7-9 | Every exit row and demo makes the fixtures it uses; a script test runs each such row alone |

---

## Execution notes (stream R, done on `m7`)

Facts for the record (F4). Commits: R1 `af8f8f3`, R2 `625cb21`, R3 `6ef9ffe`, R4 `29e21e8` and `90b4f87`, R5 `a738638`,
R6 `8bf0930` and `5d2c092`, R7 `4954de5`. R0 and R8 have no commits.

**R0 baseline.** `make test` on `77e181c`: 2084 tests in 21 bundles, all passing. The load was 4.9 before and 15.0
after.

**Deviations from the tasks above:**

- **R2.** The audit found one more script that used a fixture it did not make: the drop step of `bench.sh` (m4-exit
  X6). It now makes the small set. X3 runs `make fixtures` before the demo, and the demo also makes its own fixture.
- **R3.** `timing.sh` waits a second time after building, because the build raises the load too. A failure while the
  load rose above the limit during the run is reported as `not judged`. `--guard` runs only the wait, for X2. Suites
  run one at a time (`--no-parallel`): run beside the encode and the 80 children, the drop test measured 59.6 ms;
  alone it measured 18.9 ms.
- **R4.** The timing suite judges *every* one of the 20 drops against 50 ms, not only the p95 (stricter than
  D-M7-4). Measured with the gate off: p50 2.1–2.5 ms, p95 2.9–6.0 ms, slowest (the first drop) 16–26 ms. A skip
  inside m5a X2 now carries through `exit-lib.sh`, so m5b Y3 and m6 Z3 show SKIP instead of FAIL.
- **R5.** The race was reproduced *without* load: the old design, given a child that sets its trap after 0.5 s,
  failed 3 of 3 runs. With the plain child it passed 0 of 20 times at load 2.5–3. The slow-starting child is now a
  case of the fixed test. The teardown-beside-80-children test checks an order instead of a time: the cancelled child
  ends while every other child still runs. It was seen to fail, after 30 s, when the reap was moved onto the shared
  pool. `aTaskCancelledBeforeLaunchSpawnsNothing` lost its 500 ms bound; not spawning is the behaviour it checks. The
  1.5 s bounds of the group test and the teardown test moved to `SubprocessTiming`.
- **R6.** The check that the staged file is removed was **dropped** from the engine test. The engine leaves the file
  by design, and the scheduler removes the staging folder (`JobSchedulerTests`). `ChildSignalling` also reports how
  the leader exited, which the split needs. The cancel now waits for ffmpeg's first progress past zero instead of a
  fixed 300 ms.
- **R6 finding (G-M7-3).** Measured with the gate off at load 3–4.6, five runs: SIGINT is sent at once. libvpx-vp9
  ffmpeg does not stop on it and is SIGKILLed at the grace. The group is gone after **1066–1074 ms**, and the job
  returns 0.3 ms later. **NFR-9 (≤ 1 s) is missed by about 70 ms.** The budget is unchanged. The comparison runs
  inside `withKnownIssue` (intermittent) until the owner decides (OS-M7-7). The old test's 1.46–1.49 s waited only a
  fixed 300 ms after the spawn; why it took about 0.4 s longer than the split was not investigated.
- **R7.** `ManualClock` let a task that was cancelled before its sleep registered keep sleeping. The stale linger
  then closed the card at the next advance, so the new expiry test passed even with the restarted linger's expiry
  removed. `ManualClock` now refuses to register a cancelled sleeper, and that mutation fails the test. `ActionHUD`
  has no clock to inject (noted in the commit).

- **R4 finding (G-M7-10).** The gates run after R8 showed the first drop in each process is cold: in the timing
  suite it took 23–94 ms, including 90.8 and 93.6 ms in two runs that m5a X2 judged at load 2.9. Every later drop
  took 3–5 ms. The old unit test never saw this, because other UI tests had already warmed its process. The suite now
  judges the 19 warm drops strictly and prints the first drop on its own as a known issue (OS-M7-12). The app's own
  first drop, which X2 reads from its signpost, is judged unchanged against 50 ms: **12.7 ms**, judged at load 2.3.

**R8 proof under load.** Each fixed test ran 20 times by name with `Scripts/flaky-watch.sh`. Beside it ran a full
debug build and a release build of the package in a separate build folder, plus `nice -n 10 make test` three times.
The watched test ran through the toolchain's `swiftpm-testing-helper` on the built bundle, because two `swift test`
processes queue on the `.build` lock.

| Batch | Test | Result | Load 1m before → after |
|---|---|---|---|
| R4 | `NotchHUDDropPathTests` (3 tests) | 20/20 | 11.8 → 13.0 |
| R5 | `aChildIgnoringSIGINTIsKilledAfterTheGrace` (2 cases) | 20/20 | 13.0 → 24.1 |
| R5 | `teardownIsPromptWhileManyOtherChildrenRun` | 20/20 | 24.1 → 36.8 |
| R6 | `cancellingARunningEncodeStopsFFmpeg` | 20/20 | 36.8 → 36.4 |
| R7 | `anUndoThatChangedNothingKeepsTheButtons` | 20/20 | 36.4 → 33.8 |

The three `make test` runs that served as load also passed, with no issues.

**Not done in stream R (G-M7-9).** Unit tests that still judge wall time, outside the four named tests: the near-drop
`HUDTimingTests.firstFrameWithin50ms` (50 ms), `JobSchedulerTests` (100 ms and 1 s), `SharedLoadTests` (300 ms),
`StallWatchTests` (2 s), `TextServiceTests` (2 s), `TrayTimingTests` and the opt-in `OCRFixtureTests` (3 s). None of
them was seen to fail in this stream's runs. D-M7-3's "no wall-clock assertion outside `ZivletTimingTests`" is
therefore not yet true; they are the next candidates for the same treatment.

**Gates after stream R (load 1m before → after, `nice -n 10`).**

| Gate | Result | Load |
|---|---|---|
| `make test` (2096 tests, 22 bundles) | pass | 6.6 → 12.9; rerun after the last commit: pass at load up to 33 |
| `make lint` | pass | 12.9 → 11.9 |
| `make coverage` (every gated module ≥ 80 %; lowest EngineVision 86 %) | pass | 11.9 → 17.1 |
| `make app` | pass (also inside m6 Z1); **failed inside m5a X1 and m5b Y1** (see below) | 17.1 → 14.5 |
| `make release-check` | pass | 14.5 → 11.7 |
| `make licence-gate` | pass | 11.7 → 10.5 |
| `make script-test` | pass | 10.5 → 2.3 |
| `make timing` | first run not judged (load rose to 3.57); rerun **judged at load 2.54, every budget met**; NFR-9 and the cold first drop shown as known issues | 2.4 at the end |
| `Scripts/m5a-exit.sh` | X3, X4, X5, X7 pass. X2 failed under the every-drop rule (fixed in `fa9c851`, then X2–X5 rerun: all pass, the app's drop 12.7 ms). X1 failed in `make app`. X6 failed on idle CPU (G-M5a-1, not worked on) | 3.6 → 2.6 |
| `Scripts/m5b-exit.sh` | Y2, Y4–Y9 pass. Y1 failed in `make app`, Y3 by X2 (see above). Y4, Y5, Y7 rerun: pass | 2.6 → 2.8 |
| `Scripts/m6-exit.sh` | Z1, Z2, Z4, Z5, Z6, Z10, Z11 pass. Z7–Z9 skipped (screen locked). Z3 failed by X2 and by Y5, whose screenshots failed as the screen locked; both rerun since: pass | 2.8 → 11.1 |
| `Scripts/m7-exit.sh` | not yet written (stream F, task F2) | — |

`make app` inside X1 failed first in the "Embed media helpers" phase: `rm` reported "Directory not empty" under Sparkle's
`XPCServices`, which suggests something else was writing there at the same moment. Y1's next build then failed to sign
Sparkle (`cannot find code object on disk`, a leftover `Autoupdate.thin`). Neither the build scripts nor the project
changed in stream R, and the standalone `make app` and m6 Z1 passed before and after. The cause was not found; it is
recorded as G-M7-11.

