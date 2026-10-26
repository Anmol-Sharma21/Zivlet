# 16f — M5b Stream E: QA rows, exit runner, every state on screen, record (NB8)

Part of [16-implementation-plan-m5b](16-implementation-plan-m5b.md). Conventions: index §6. Exit rows: index §7.
Owner steps: index §8. Patterns reused: `docs/plan/qa/notch.md`, `Scripts/m5a-exit.sh` and its test,
`Scripts/demo-notch-states.sh`, `Scripts/notch-idle.sh`, `Scripts/idle-cpu.sh`, `Scripts/png-luminance.swift`.

Every script writes only under `build/` or a `mktemp -d` folder it names and removes; deletions use the folder's
literal pattern check, as `m5a-exit.sh`'s `drop_demo_dir` does. No script raises an alert in the running app, and
the screenshot steps check that the screen is awake first and say "skipped: screen locked" instead of failing.

---

## Task E1 — `docs/plan/qa/drop-box.md`

| Field | Value |
|---|---|
| Goal | The owner's checklist for real hardware, in the format of `qa/notch.md`: setup (Debug build, quitting Zivlet, the debug flags of D-M5b-20, recording the macOS build, Mac model, display modes and the Zivlet commit), then the sections below. Each row: check, steps, expected, result (pass / fail with what happened / n/a with why) |
| Acceptance | every 05 clause that index §2.1 marks "QA" or "real drag" has a row; every row names its expected result; §R documents the recorder |
| Effort | S |

**Files:** create `docs/plan/qa/drop-box.md`.

Sections and rows:

| § | Rows |
|---|---|
| B. Drop Box panel | B1 the BOX slice shows `tray.full` "BOX" and adds to the most recent box; ⌥ makes a new box · B2 "Show Drop Box" shows the panel without taking focus from the app being typed in · B3 dock: attach at 28 pt, detach at 48 pt, a short move is a click · B4 grid and list, ⌘1/⌘2 · **B5 drag 200 items out to Finder in one drag** (all 200 arrive; the panel stays; nothing takes focus) · B6–B8 file promises from Mail (an attachment), Photos (a photo) and Safari (an image): each lands as an owned copy · B9 Quick Look on Space from the panel · B10 keyboard table of 17e §2.3 · B11 marquee, type-to-select, context menu · B12 Share and AirDrop to a real device · B13 Convert all: drag the stack out with the convert modifier, the wheel opens for every item · B14 Move to and Copy to with one Undo each, across volumes too · B15 Trash with inline confirm, Clear with a 10 s Undo, Remove missing, Locate… · B16 restore after relaunch (frame, dock, items; missing, in the Trash and offline states) · B17 storage line and the 2 GB dot (owned copies from B6–B8 repeated) |
| T. Notch tray | T1 a file drag resting at the notch opens the drop target; a pass on the way to the menu bar opens nothing · T2 drop at the notch adds to the current box, "Added 3", Undo · T3 hover on the housing opens the compact view; "Open Drop Box" opens the panel · **T4 a drop at the notch in a full-screen Space** · T5 an external display: the pill drop target at its top centre · T6 the wheel wins: open the wheel during a drag near the notch; the tray steps aside and a drop cannot land in it · T7 HUD progress is never hidden by the tray at rest · T8 Pause stops the tray and shake · T9 the menu bar beside the housing stays usable while the tray rests (sensor) · T10 "Open at the notch while dragging" off: no drop target |
| A. Look and accessibility | A1 every state matches 19c (with `make box-states` shots) · A2 Reduce Transparency, A3 Increase Contrast, A4 Reduce Motion, with the system settings · A5 VoiceOver: list rows, labels, the drop-target announcement · A6 Voice Control "click Share" · A7 Light mode: the panel stays dark (OP-M5b-1) |
| C4. Reads before and after a drop | C4a–C4d as written in 16d task D7 |
| S. Shake (opt-in) | S1 off by default: shaking opens nothing · S2 on: 4 quick side-to-side swings during a drag open the box under the pointer · S3 ordinary drags for a day with it on: note any accidental open |
| R. Recordings (OS-M5b-1) | R1 setup: `open -n build/DerivedData/Build/Products/Debug/Zivlet.app --args -ZivletRecordDragTraces normal`; the log shows `DragTrace: recording normal`; traces go to `~/Library/Application Support/Zivlet/DragTraces/` (timings, positions and display geometry only; nothing about files) · R2 200 normal drags over a few days of ordinary work (Finder, the Desktop, browser uploads, Mail, the Dock, status items) · R3 relaunch with `notch` and make 50 drags aimed at the notch, waiting there as you would for the tray · R4 `make drag-replay TRACES="$HOME/Library/Application Support/Zivlet/DragTraces"`: pass = ≥ 95 % of notch-bound detected and 0 accidental opens; on a fail, `swift run --package-path Packages/ZivletKit zivlet-traces tune <folder>` and a one-commit `Config` change · R5 decide whether to keep the traces local (default) or commit them under `Fixtures/drag-traces/` |

Commit `docs: add the Drop Box and notch tray QA list`.

---

## Task E2 — `Scripts/m5b-exit.sh` and its test

| Field | Value |
|---|---|
| Goal | Rows Y1–Y9 of index §7 in the structure of `m5a-exit.sh`: `--only`, `--list`, internal `--row`; each row in its own `bash` process with errexit; logs in `build/m5b-exit/<row>.log`; one pass/fail line per row; exit 1 when any row failed. Environment overrides for the script test only: `ZIVLET_M5B_EXIT_LOGS`, `ZIVLET_M5B_LOG` (replaces `/usr/bin/log`), `ZIVLET_M5B_BASE` (default `0ef22d6`). Y3 calls `Scripts/m5a-exit.sh --only X2,X3,X4,X5`. Y6 checks the TCC stream since Y3 started, as X5 does (D-M5a-5), and refuses to run without Y3–Y5 in the same run. Y9's hygiene adds two checks to X7's: `grep '^import'` in `Sources/ZivletShelfCore` shows only `Foundation` and `os`; `grep -r NSAlert Sources/ZivletBox` finds nothing. `make m5b-exit` |
| Acceptance | `Scripts/tests/test-m5b-exit.sh` (stubbed `make` and `log`, as `test-m5a-exit.sh`): `--list` prints nine rows; `--only` refuses an unknown row; a failing stub fails its row only; Y6 refuses to run alone; the hygiene row fails on a commit without sign-off, on a `Co-Authored-By`, on an 800-line file, on a personal path, on a non-Foundation import in the shelf core and on `NSAlert` in the box module |
| Effort | S |

**Files:** create `Scripts/m5b-exit.sh`, `Scripts/tests/test-m5b-exit.sh`; modify `Makefile`.

Commit `test(scripts): add the M5b exit runner`.

---

## Task E3 — `Scripts/demo-box-states.sh`: every box and tray state (OWN-UI-1)

| Field | Value |
|---|---|
| Goal | In the pattern of `demo-notch-states.sh`: one Debug-app launch per state with `-ZivletBoxPreview <state>` or `-ZivletTrayPreview <state>` (B10, D12) and the screenshot flags; wait for `Box: <state>` or `Island: <surface>` in the log; crop from the `Box: frame …` or `Island: frame …` line into `build/box-states/`; quit the app. States: panel hidden (no capture, log only), docked, collapsed, grid, list, selection, dropTarget, busy, attention, confirmTrash, confirmClear, empty; tray dropTarget, toast, compact, and the pill versions of all three; each on glass, solid and contrast; grid and the tray drop target also with `-ZivletIslandReduceMotion YES`; over `-ZivletIslandBackdrop white`, measure a text-free box of the panel, the docked tab and the tray drop target with `Scripts/png-luminance.swift` and fail when white at 0.8 would fall under 4.5:1. `ZIVLET_STATES_DRY_RUN=1` lists the captures and launches nothing. `make box-states` |
| Acceptance | `Scripts/tests/test-box-states.sh` (dry run: the capture list covers every 19c §4 state; a refused flag in the log fails the capture); one real run on the owner's Mac with the screen awake produces every file (Y5) |
| Effort | S |

**Files:** create `Scripts/demo-box-states.sh`, `Scripts/tests/test-box-states.sh`; modify `Makefile`.

Commit `test(scripts): capture every Drop Box and tray state`.

---

## Task E4 — `Scripts/demo-box.sh`: add, show, relaunch, restored

| Field | Value |
|---|---|
| Goal | Copies four small fixtures (`build/fixtures/small`: `alpha.heic`, `alpha.png`, `pages.tiff`, `pcm24.wav`) into a `mktemp -d` folder `zivlet-m5b-demo.XXXXXX`; launches the Debug app with `-ZivletBoxDemo <folder>` (B10: a demo box in a temporary store, never the person's `boxes.json`); waits for `Box: shown` and `Box: items 4`; captures the panel from `Box: frame …` into `build/m5b-exit/`; quits; relaunches with the same flag and store and waits for `Box: restored 4 items`; quits; removes its folder. `make box-demo` |
| Acceptance | `Scripts/tests/test-box-demo.sh` with a stubbed app launcher and log (pass on the three lines, fail when `restored` is missing); a real run passes Y4 |
| Effort | S |

**Files:** create `Scripts/demo-box.sh`, `Scripts/tests/test-box-demo.sh`; modify `Makefile`, `App/BoxShots.swift` (the
`restored` log line, if B10 did not add it).

Commit `test(scripts): demo the Drop Box across a relaunch`.

---

## Task E5 — Idle CPU of the box and the tray (Y8)

| Field | Value |
|---|---|
| Goal | `Scripts/box-idle.sh`, in the pattern of `notch-idle.sh` (Debug build, one launch per state, `Scripts/idle-cpu.sh PID 120`, WindowServer printed for information): baseline (no box shown, nothing at the notch), the panel shown and still (`-ZivletBoxPreview grid`), the tray at rest on its sensor (`-ZivletTrayPreview sensor`). Limits: each state minus the baseline ≤ 0.1 %. `make box-idle`. G-M5a-1's fast-progress row is not part of it |
| Acceptance | `Scripts/tests/test-box-idle.sh` (stubbed sampler: pass at 0.09, fail at 0.11, refuses a missing baseline); a real run on a quiet Mac, recorded as Debug numbers |
| Effort | S |

**Files:** create `Scripts/box-idle.sh`, `Scripts/tests/test-box-idle.sh`; modify `Makefile`.

Commit `test(scripts): measure the idle CPU of the Drop Box and the tray`.

---

## Task E6 — Exit run, owner list, `docs/plan/17-m5b-record.md`

| Field | Value |
|---|---|
| Goal | Run the full gate list (index §6) and `make m5b-exit`; fix and rerun until Y1–Y9 pass or a row is recorded as open with its reason. Write `docs/plan/17-m5b-record.md` in the shape of `13-m5a-record.md` and `15-notch-design-record.md` |
| Acceptance | the record exists, is under 800 lines, and is honest: what passed, what failed and why, what was not measured or not seen, and what is deferred |
| Effort | S |

**Files:** create `docs/plan/17-m5b-record.md`.

The record's sections:

| § | Content |
|---|---|
| Status | one paragraph: code complete or not; which Y rows passed; that the P2-197 detection bar is or is not measured (it is only with OS-M5b-1's recordings) |
| 1. What was built | per stream, with the commits |
| 2. Exit rows | Y1–Y9 with result, duration, and log excerpts (numbers only, no paths) |
| 3. Tests and coverage | bundles, test counts, coverage per gated module (16) |
| 4. Screenshots | the `make box-states` list, which were reviewed by the owner (OS-M5b-3), what was not seen |
| 5. NB5 | the synthetic replay numbers; the recordings' numbers if made, else "not measured"; the constants in use |
| 6. C4 | the prototype's answer (index §3.5) and the C4a–C4d results if run |
| 7. Gaps | G-M5b-1 … with next steps (Zip; recordings; hardware rows; anything Y left open) |
| 8. Owner steps | OS-M5b-1 … 4 with state; OP-M5b-1 … 5 with the owner's answers or "open" |
| 9. Review | findings of a code review of the branch and what was done with each |

Commit `docs: record M5b`.
