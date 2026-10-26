# 17 — M5b record: the notch Drop Box

Date: 2026-10-26. Status: **code complete on the local branch `m5b`; not merged, not pushed**. Every task of streams
A–E in [16](16-implementation-plan-m5b.md) is committed. The automated exit rows Y1–Y9 pass (§2): Y1, Y2 and Y7–Y9
in the first run; Y3 failed there on the 50 ms timing test under `nice` and passed in a second run of Y3–Y6, which
all passed. **The P2-197 detection bar (≥ 95 % of 50 recorded notch-bound drags, 0 accidental opens over 200
recorded normal drags) is not measured**: it needs the owner's recordings (OS-M5b-1), and Y7 runs on synthetic drags
only. None of the owner rows in [qa/drop-box.md](qa/drop-box.md) has been run, so M5b is not "complete" in the sense
of 16 §7. Zip is deferred (G-M5b-1). A code review of the branch has not been run yet (§9).

This is a record, not a plan. The plan is [16](16-implementation-plan-m5b.md) with its parts 16a–16f; the look is
[design/19c](../design/19c-drop-box-look.md); the behaviour is [design/17e](../design/17e-app.md) §2 and §2a.

Clean-room rule: unchanged. No code, assets, sounds or UI strings from the reference app, Open-Tangerine or any notch
or shelf app. Every string in the panel, the tray, the Settings rows, the menu and the QA list is Zivlet's own.

Machine for every number below: 14-inch MacBook Pro (Mac14,9), macOS 27.0 (26A428), Xcode 27.0, Debug app, with the
owner's other work running (load average 2.4–4.8 during the runs).

---

## 1. What was built

| Stream | What is on `m5b` | Commits |
|---|---|---|
| Plan | plan 16 and its parts, design 19c | `a3b5f3f` |
| A — shelf core, shake (NB1, NB2) | `ZivletShelfCore` (Foundation, `os` and `ZivletCore` only): validated immutable items, boxes and the library with de-dup and caps, bookmarks without a security scope and item status (present, in the Trash, volume not connected, missing), the private schema-versioned `boxes.json`, owned-copy storage, auto-clear plans and the 2 GB warning; the Settings group `box`; `ShakeDetector` (opt-in) and the trigger host's live-sample hook | `c675826` … `3f41131` (9) |
| B — Drop Box panel (NB3) | `ZivletBox`: the non-activating panel, presentation states and dock rules, tokens and finish on the 19b tokens (shared with the island), off-main Quick Look thumbnails with type icons first, the views, intake of files, promises and clippings, the controller with restore, selection, keys, marquee and context menu; the BOX slice (`tray.full`, `ActionID.pinFloating` raw value kept), "Show Drop Box", Settings rows, app wiring, Debug previews and their Release refusal | `8e5ad9c` … `240ce21` (20) |
| C — bulk actions (NB4) | bulk targets, Share, AirDrop, Copy, Copy Paths, Move to and Copy to with one undo each (undo schema 2), Remove, Trash with an inline question, Clear with a 10 s undo, Locate…, storage line, Empty Box Storage, auto-clear; a test that a drag out of the box opens the wheel for every item; a test that there is no Zip | `ac6d215` … `e7a1a55` (16) |
| D — proximity, recorder, tray (NB5–NB7) | `NotchProximity`, the tray zone per display, the drag-trace format, synthetic drags and the evaluator, the replay harness (`make drag-replay`), the `zivlet-traces` tuning tool, the Debug-only recorder, the pre-drop-read test (C4); the island's `.dropTarget` and `.sensor` surfaces with visible rests ranked first, drops into a client, the tray client, the drop into the current box, the compact view and its open button, app wiring, the 50 ms tray timing test | `3d755a5` … `fa21061` (15) |
| E — QA and exit (NB8) | `qa/drop-box.md`; `Scripts/m5b-exit.sh` (`make m5b-exit`); `Scripts/demo-box-states.sh` (`make box-states`); `Scripts/demo-box.sh` (`make box-demo`); `Scripts/box-idle.sh` (`make box-idle`); their script tests; this record | `da9cbe3`, `bf1cdf5`, `52acc9d`, `fffb09c`, `3537677`, and this commit |

## 2. Exit rows

| Row | Result | Time | What the log shows |
|---|---|---|---|
| Y1 | pass | 179 s | 18 test bundles, 1714 tests, all passed; lint clean; coverage per module (§3), `ZivletShelfCore` 98 %, `ZivletBox` 93 %; `make app` built; release-check: "Release build contains no Homebrew path, no island preview, no Drop Box debug flag and no drag recorder"; licences OK (13 components, 58 crates) |
| Y2 | pass | 181 s | 28 script tests, all PASS, among them the four new ones (`test-m5b-exit`, `test-box-states`, `test-box-demo`, `test-box-idle`) |
| Y3 | **fail**, then pass | 53 s, then 28 s | First run (whole runner under `nice -n 10`, load about 4): X2's `NotchHUDTimingTests` measured 73 ms against 50 ms; X3–X5 passed. `make notch-timing` alone under `nice` failed again (70 ms); three plain runs of the test passed straight after; the second run of Y3–Y6 (not under `nice`) passed X2–X5. See G-M5b-5 |
| Y4 | pass | 13 s | `Box: shown`, `Box: items 4`, the panel captured (384 × 178 pt, real Quick Look thumbnails of the four fixtures), `Box: restored 4 items` after the relaunch; the scratch folder was removed |
| Y5 | pass | 268 s, 270 s | 63 captures and 2 log-only checks (hidden panel, resting sensor); no refused flag; over white: panel 7.16:1 (glass luminance 0.054), docked tab 5.13:1 (0.102), tray drop target 5.55:1 (0.089), pill drop target 5.13:1 (0.102), each against 4.5:1 |
| Y6 | pass | 2 s, 1 s | no tccd request with `preflight=no` for Zivlet while Y3–Y5 ran, in both runs (5,416 TCC lines read in the first); no preflight check for Zivlet either |
| Y7 | pass | 7 s | 16 tests in 2 suites: the proximity rule on five seeded synthetic sets on the recorded 14-inch display and five on a constructed pill display, each meeting ≥ 95 % detection and 0 accidental opens; the shake detector with no false positive on the synthetic non-shake sets. The recorded-drag test was skipped: no recordings. The test asserts the bar and does not print the percentages (G-M5b-6) |
| Y8 | pass | 400 s | Debug numbers, load average 4.5 at the start: baseline 0.008 %; panel shown and still 0.008 % (0.000 over the baseline); tray resting on its sensor 0.000 % (−0.008); WindowServer 8.2–8.4 % beside each, for information. `idle-cpu.sh` resolves 0.008 % over 120 s |
| Y9 | pass | 2 s | every commit since `0ef22d6` signed off, none with `Co-Authored-By`; no changed `.swift` or `.sh` file at 800 lines or more; no personal or scratch path added; the shelf core imports only Foundation, `os` and `ZivletCore`; no `NSAlert` in `ZivletBox` |

Also run: `Scripts/m5a-exit.sh --only X7` (hygiene since the M5a baseline) passed. X6 stays with G-M5a-1 and was not
run.

## 3. Tests and coverage

18 test bundles, **1714 tests** (1240 at the plan's baseline), all passed in Y1. Line coverage from `make coverage`
(gate 80 % per module, 16 gated modules):

| Module | Lines | % | Module | Lines | % |
|---|---|---|---|---|---|
| ZivletCore | 645/655 | 98 | ZivletWheel | 956/986 | 96 |
| ZivletTrigger | 696/703 | 99 | ZivletActions | 668/732 | 91 |
| ZivletWheelCore | 360/361 | 99 | ZivletSettings | 253/261 | 96 |
| ZivletEngineKit | 845/868 | 97 | ZivletUI | 4168/4379 | 95 |
| EngineMedia | 1186/1211 | 97 | ZivletNotchCore | 503/510 | 98 |
| EngineImage | 1239/1292 | 95 | ZivletNotch | 1064/1108 | 96 |
| ZivletRuntime | 1680/1754 | 95 | **ZivletShelfCore** | 807/819 | 98 |
| ZivletTriggerHost | 403/432 | 93 | **ZivletBox** | 2798/2993 | 93 |

The script tests run the new scripts against stand-ins: no app is launched by them. The hygiene row is tested
against throwaway repositories (unsigned commit, `Co-Authored-By`, an 800-line file, a personal path, a
non-Foundation import in the shelf core, `NSAlert` in the box).

## 4. Screenshots

`make box-states` writes to `build/box-states/` (not tracked):

- Panel, each on glass, solid and contrast: `box-docked`, `box-collapsed`, `box-grid`, `box-list`, `box-selection`,
  `box-dropTarget`, `box-busy`, `box-attention`, `box-confirmTrash`, `box-confirmClear`, `box-empty`,
  `box-confirmEmpty`, `box-storageWarning` (39).
- Tray, each on glass, solid and contrast, at the notch and on a pill display: `tray-` and `pill-tray-` `dropTarget`,
  `toast`, `compact` (18).
- `box-grid-reduce-motion`, `tray-dropTarget-reduce-motion`; over white: `box-grid-white`, `box-docked-white`,
  `tray-dropTarget-white`, `pill-tray-dropTarget-white` (6).
- Log only: the hidden panel (`Box: hidden`) and the resting tray (`Island: sensor`).

Reviewed by the agent that ran stream E, with 19c open: no clipping, no misaligned rows, no unreadable text, no border
or divider; the contrast finish draws the round button backgrounds and the thin outline; the attention state shows
its three badges and the Remove missing button; the storage dot sits on the overflow symbol; no capture took focus.
The first full run showed another app's tooltip, left on screen under the menu bar, over the panel's header; the
Debug previews now sit in the middle of the display (§5), and the second run was clean. In the drop-target state the
"Add 3" chip sits over the middle cell, whose name shows on both sides of it at 0.4: as 19c §4.1 draws it.

**Not reviewed by the owner** (OS-M5b-3 open). Not seen at all: the real Reduce Transparency, Increase Contrast and
Reduce Motion settings (the flags stand in), Light mode, VoiceOver, a real external display (the pill is forced with
a flag), a full-screen Space, a real drag into or out of the panel or the tray.

## 5. Deviations from the plan

| Item | Plan | What was done, and why |
|---|---|---|
| Proximity constants | D-M5b-9: 40 pt, 100 ms, 800 pt/s | `NotchProximity.Config.provisional` is 30 pt, 240 ms, 600 pt/s, release 24 pt: the Swift generator's ten seeded sets gave 1–6 accidental opens per 200 everyday drags with the plan's values; the chosen point is the middle of the region with none in every set and detection ≥ 98 % (stream D, `3d755a5` … `89f41d1`). Made-up movement decided this; the recordings decide the real values |
| Y9 shelf-core imports | §7: "only Foundation" (E2: Foundation and `os`) | Foundation, `os` and `ZivletCore`: D-M5b-1 makes `ZivletCore` the shelf core's one dependency, and it is itself Foundation only. A UI framework still fails the row |
| A locked screen in the runner | not defined | the screenshot scripts exit 0 with "skipped: screen locked"; the runner shows such a row as **SKIP** and exits 1, so a skipped picture never reads as a pass |
| Extra captures | 19c §4 states | also `confirmEmpty` and `storageWarning` (Debug previews stream C added) and the pill drop target over white |
| Debug previews | the backdrop across the top middle; panel previews 120 pt under the top | the white or black backdrop covers the whole display (the docked tab sits on its edge), panel previews sit in the middle of the display, and tray previews use a temporary store as panel previews do, so a screenshot never loads the person's `boxes.json` (`52acc9d`) |
| E4 app change | add the `restored` line if B10 had not | not needed: B10 logs it |

## 6. C4: reads before and after a drop

The prototype's answer (16 §3.5): a drag's types, item count and URL strings caused no file-system access and no TCC
request; metadata reads and bookmarks without a security scope made only silent preflight checks in Downloads and
none for an evicted iCloud file or a disk image; a security-scoped bookmark raised a real Downloads prompt, so Zivlet
never makes one (D-M5b-2). `PreDropReadTests` hold the box and the tray to reading only the drag's types and count
before a drop. Y6 saw no request that could prompt during the demos. **C4a–C4d have not been run** (G-M5b-4).

## 7. Gaps

| ID | Gap | Next step |
|---|---|---|
| G-M5b-1 | Zip (P2-142) is not built: EngineArchive (P2-111) does not exist. A test holds that no Zip button exists | Add Zip with P2-111; P2-142 stays open for it |
| G-M5b-2 | The P2-197 bar is not measured: no recorded drags exist; the constants come from synthetic drags | OS-M5b-1 |
| G-M5b-3 | No owner row of `qa/drop-box.md` has been run: 200 items out to Finder, promises from Mail, Photos and Safari, a drop in a full-screen Space, an external display, AirDrop to a device, Quick Look, VoiceOver, the real accessibility settings, shake | OS-M5b-2 |
| G-M5b-4 | C4a–C4d (content reads after a relaunch, a USB drive, the real Finder pasteboard, Zivlet's existing folder access) | QA §C4; OP-M5b-3 if C4b shows a prompt |
| G-M5b-5 | `NotchHUDTimingTests` (50 ms) failed twice under `nice -n 10` at load about 3–4 (73 ms and 70 ms) and passed in three plain runs and in the second Y3. This repeats G-M5a-9 (72 ms once under load in M5a). Not profiled; whether M5b's island changes (D8, D9) add to it was not measured against `main` | Run X2 on a quiet Mac on `main` and on `m5b`; profile `NotchHUD.show` if `m5b` is slower |
| G-M5b-6 | Y7 asserts the bar for each synthetic set but does not print the detection and accidental-open numbers | Print them from the replay test, or run `zivlet-traces report` on an exported synthetic set |
| G-M5b-7 | Y8's numbers are Debug numbers on a loaded Mac; no Release measurement build includes the box previews | Measure on a quiet Mac; add a Release measurement like `notch-idle.sh CONFIG=release` if the owner wants Release numbers |
| G-M5a-1 | The fast-progress CPU item from M5a | Unchanged and untouched in M5b |

## 8. Owner steps

| ID | Step | State |
|---|---|---|
| OS-M5b-1 | Record 200 normal and 50 notch-bound drags with the Debug recorder, run `make drag-replay TRACES=…`, decide whether to commit the traces (QA §R) | open |
| OS-M5b-2 | The hardware rows of `qa/drop-box.md` (B, T, A, C4, S) | open |
| OS-M5b-3 | Review the `make box-states` pictures with 19c open | open (the agent's review is in §4) |
| OS-M5b-4 | Merge and push `m5b` | open |
| OP-M5b-1 | The panel stays dark in Light mode | open (built as recommended: dark) |
| OP-M5b-2 | The idle tray is an invisible sensor, not a visible tab | open (built as recommended: sensor) |
| OP-M5b-3 | What to do if thumbnails after a relaunch raise a folder prompt | open (waits for C4b) |
| OP-M5b-4 | Settings defaults: tray while dragging on, shake off, auto-clear off, drops to the most recent box | open (built as recommended) |
| OP-M5b-5 | Zip stays deferred | open (built as recommended: no Zip) |

## 9. Review

No code review of the branch has been run at the time of this record; stream E ended with the gates and the exit
rows. The review's findings and what is done with each belong here when it runs.
