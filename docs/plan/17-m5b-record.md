# 17 — M5b record: the notch Drop Box

Date: 2026-10-26. Status: **code complete on the local branch `m5b`, reviewed, review findings addressed; not merged,
not pushed**. Every task of streams A–E in [16](16-implementation-plan-m5b.md) is committed, and so are the fixes for
the branch review (§9: 59 findings, 52 fixed, 4 partly, 3 skipped with reasons). After the fixes the exit rows Y1–Y9
were run again (§2): all pass, Y3 only in its second run (the 50 ms notch HUD timing test under load, G-M5b-5).
**The P2-197 detection bar (≥ 95 % of 50 recorded notch-bound drags, 0 accidental opens over 200 recorded normal
drags) is not measured**: it needs the owner's recordings (OS-M5b-1), and Y7 runs on synthetic drags only. None of
the owner rows in [qa/drop-box.md](qa/drop-box.md) has been run, so M5b is not "complete" in the sense of 16 §7, and
the 05 rows P2-142 (Zip, G-M5b-1), P2-143, P2-197 and P2-55's hardware rows stay open.

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
| E — QA and exit (NB8) | `qa/drop-box.md`; `Scripts/m5b-exit.sh` (`make m5b-exit`); `Scripts/demo-box-states.sh` (`make box-states`); `Scripts/demo-box.sh` (`make box-demo`); `Scripts/box-idle.sh` (`make box-idle`); their script tests; this record | `da9cbe3`, `bf1cdf5`, `52acc9d`, `fffb09c`, `3537677`, `b246863` |
| Review (§9) | owned copies kept the box's own, destination-first intake, safe loading and saving of `boxes.json`, bounded promise waits, the tray resolving and loading its thumbnails, bulk actions on fresh targets one at a time, a panel that takes the keyboard on a click, thumbnails from the cells on screen, VoiceOver actions, entrance motion, the renamed BOX setting; `TriggerHost.stop`, the into-itself check, the undo store, Y6 and Y8 hardening, Y7's numbers; QA §V | `1e39423`, `c4af55a`, `bb2f458`, `90e70c0`, `022a536`, `321b89f`, `55711c1`, `9eb2058`, `fd3101d`, and this commit |

## 2. Exit rows

After the review fixes, at `fd3101d`: one full run of `Scripts/m5b-exit.sh` under `nice -n 10` (load average 14 → 2
during it), then Y3–Y6 again without `nice` (load about 2.5). The first run of stream E (before the review) passed
too, with the same Y3 story; its numbers are in the history of this file.

| Row | Result | Time | What the log shows |
|---|---|---|---|
| Y1 | pass | 194 s | 18 test bundles, 1771 tests, all passed; lint clean; coverage per module (§3), `ZivletShelfCore` 98 %, `ZivletBox` 93 %; `make app` built; release-check: "Release build contains no Homebrew path, no island preview, no Drop Box debug flag and no drag recorder"; "Licences OK: 13 components, 58 crates" |
| Y2 | pass | 186 s | `make script-test`, all PASS, among them the two new cases (Y6 on an empty TCC stream, the armed Y8 state) |
| Y3 | **fail**, then pass | 55 s, then 27 s | First run (under `nice`, load about 8): X2's `NotchHUDTimingTests` failed its 50 ms bound; X3–X5 passed. The rerun without `nice` passed X2–X5. G-M5b-5, unchanged |
| Y4 | pass | 12 s, 13 s | `Box: shown`, `Box: items 4`, the panel captured with real Quick Look thumbnails (now in icon mode), `Box: restored 4 items` after the relaunch; the scratch folder removed |
| Y5 | pass | 268 s, 267 s | 63 captures and 2 log-only checks; over white: panel 6.82:1 (glass luminance 0.060), docked tab 4.99:1 (0.107), tray drop target 5.55:1 (0.089), pill drop target 5.13:1 (0.102), each against 4.5:1 |
| Y6 | pass | 1 s, 1 s | no tccd request with `preflight=no` for Zivlet while Y3–Y5 ran (6,103 and 6,435 TCC lines read); no preflight check for Zivlet either. An empty stream would now fail the row |
| Y7 | pass | 8 s | 17 tests in 2 suites; each synthetic set now prints its numbers: on the recorded 14-inch display detection 98–100 % (49 or 50 of 50) with 0 accidental opens in 200 everyday drags, the same on the pill display, five seeds each. Synthetic drags only; the recorded-drag test was skipped (no recordings) |
| Y8 | pass | 532 s | Debug, load average 3.3 at the start: baseline 0.008 %; panel shown and still 0.000 % (−0.008 over the baseline); tray resting on its sensor 0.000 % (−0.008); **the armed demo box (real tray driver, live-sample hook and zone watch) 0.008 % (0.000 over)**; WindowServer 7.5–8.2 % beside each, for information |
| Y9 | pass | 2 s | every commit since `0ef22d6` signed off, none with `Co-Authored-By`; no changed `.swift` or `.sh` file at 800 lines or more; no personal or scratch path added; the shelf core imports only Foundation, `os` and `ZivletCore`; no `NSAlert` in `ZivletBox` |

Also run: `Scripts/m5a-exit.sh --only X7` (hygiene since the M5a baseline) passed. X6 stays with G-M5a-1 and was not
run.

## 3. Tests and coverage

18 test bundles, **1771 tests** (1714 before the review, 1240 at the plan's baseline), all passed in Y1. Line
coverage from `make coverage` (gate 80 % per module, 16 gated modules):

| Module | Lines | % | Module | Lines | % |
|---|---|---|---|---|---|
| ZivletCore | 645/655 | 98 | ZivletWheel | 956/986 | 96 |
| ZivletTrigger | 696/703 | 99 | ZivletActions | 689/768 | 89 |
| ZivletWheelCore | 360/361 | 99 | ZivletSettings | 253/261 | 96 |
| ZivletEngineKit | 845/868 | 97 | ZivletUI | 4168/4379 | 95 |
| EngineMedia | 1186/1211 | 97 | ZivletNotchCore | 503/510 | 98 |
| EngineImage | 1239/1292 | 95 | ZivletNotch | 1064/1108 | 96 |
| ZivletRuntime | 1709/1785 | 95 | **ZivletShelfCore** | 950/966 | 98 |
| ZivletTriggerHost | 405/434 | 93 | **ZivletBox** | 3251/3491 | 93 |

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

After the review, the states whose look changed were captured again (outside the repository, not tracked), then the
whole set by Y5: the attention state on glass, solid and contrast (the badges now sit inside their circles, the
offline drive with a margin), the busy state (only the title, the bar and Cancel), grid, list, selection,
collapsed and the tray's compact view (no visible change: the "+6" tile changes only on hover). Two demo captures
show real Quick Look thumbnails in icon mode: the four Y4 fixtures, and seven small `.txt` files, which now draw as
white pages with Finder's margins rather than full-bleed squares; they are still the brightest thing on the glass
(G-M5b-14). The entrance motion cannot be seen in a still; every capture waits past it.

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
| Busy layout (19c §4.1) | the progress bar under the header; only Cancel | the bar and Cancel take the action bar's place; since the review the header's commands are hidden while busy. No action drives the busy state yet (G-M5b-9) |
| Settings words (19c §5) | "New drops go to" | "BOX on the wheel adds to" (D-M5b-29) |
| Exit motion (D-BL12) | leaves with opacity | leaves at once (G-M5b-10) |

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
| G-M5b-2 | The P2-197 bar is not measured: no recorded drags exist; the constants come from synthetic drags. P2-141's shake "zero false positives on recorded non-shake traces" is likewise checked on synthetic traces only | OS-M5b-1 |
| G-M5b-3 | No owner row of `qa/drop-box.md` has been run: 200 items out to Finder, promises from Mail, Photos and Safari, a drop in a full-screen Space, an external display, AirDrop to a device, Quick Look, VoiceOver, the real accessibility settings, shake | OS-M5b-2 |
| G-M5b-4 | C4a–C4d (content reads after a relaunch, a USB drive, the real Finder pasteboard, Zivlet's existing folder access) | QA §C4; OP-M5b-3 if C4b shows a prompt |
| G-M5b-5 | `NotchHUDTimingTests` (50 ms) failed twice under `nice -n 10` at load about 3–4 (73 ms and 70 ms) and passed in three plain runs and in the second Y3; after the review it failed again in the `nice` run at load about 8 and passed in the plain rerun. This repeats G-M5a-9 (72 ms once under load in M5a). Not profiled; whether M5b's island changes (D8, D9) add to it was not measured against `main` | Run X2 on a quiet Mac on `main` and on `m5b`; profile `NotchHUD.show` if `m5b` is slower |
| G-M5b-6 | Y7 asserted the bar for each synthetic set but printed no numbers | **Closed** by the review: each set prints detection and accidental opens (`90e70c0`) |
| G-M5b-7 | Y8's numbers are Debug numbers on a loaded Mac; no Release measurement build includes the box previews | Measure on a quiet Mac; add a Release measurement like `notch-idle.sh CONFIG=release` if the owner wants Release numbers |
| G-M5b-8 | Still on the main thread: moving items and owned copies to the Trash (the review measured 0.63 ms a file, about 125 ms for 200), resolving the box at show (0.02 ms a present item, 0.14 ms a missing one) and making promise files into items | Move them off the main actor together with G-M5b-9, so the library, the card and Undo stay consistent |
| G-M5b-9 | The busy overlay (progress, Cancel, Esc) is drawn by the views but no action drives it, and the move executor cannot be cancelled; bulk actions are only kept to one at a time | Drive `.busyStarted`/`.busyEnded` around Move and Copy to…, make the executor check for cancellation, or drop the state |
| G-M5b-10 | The panel leaves at once; D-BL12's opacity exit is not built (the entrance and the thumbnail fade are) | Let the presentation wait for a fade before ordering out |
| G-M5b-11 | The selection fill has no inner padding and `GridSelection.focus` has no visible indicator (D-BL6's focus ring) | With the owner's look review (OS-M5b-3); it changes the grid's metrics |
| G-M5b-12 | VoiceOver: items have actions now, but the items' container has no list role (SwiftUI on macOS offers none) and nothing was tried with VoiceOver | QA V4 |
| G-M5b-13 | Most review fixes were tested with the fix rather than test-first (§9.1); only the panel's key test was seen to fail on the old code | Accepted for this round; noted so the record does not overstate TDD |
| G-M5b-14 | In Quick Look's icon mode, plain-text files are white pages: better than full squares, still the brightest thing on the glass | QA V7; the owner decides whether text keeps its type icon instead |
| G-M5a-1 | The fast-progress CPU item from M5a | Unchanged and untouched in M5b |

## 8. Owner steps

| ID | Step | State |
|---|---|---|
| OS-M5b-1 | Record 200 normal and 50 notch-bound drags with the Debug recorder, run `make drag-replay TRACES=…`, decide whether to commit the traces (QA §R) | open |
| OS-M5b-2 | The hardware rows of `qa/drop-box.md` (B, T, A, C4, S) | open |
| OS-M5b-3 | Review the `make box-states` pictures with 19c open | open (the agent's review is in §4) |
| OS-M5b-4 | Merge and push `m5b` (`git switch main && git merge --no-ff m5b`, then `git push`), once OS-M5b-1/2/5 and the quiet-Mac timing check (G-M5b-5) are done, or with them recorded as open | open |
| OS-M5b-5 | The review's hardware rows, QA §V (V1–V8): the click and the keyboard, an owned copy moved out, the accessibility settings while shown, VoiceOver actions, a slow or failing promise, the tray after a relaunch, many text files, scrolling to the selection | open |
| OP-M5b-1 | The panel stays dark in Light mode | open (built as recommended: dark) |
| OP-M5b-2 | The idle tray is an invisible sensor, not a visible tab | open (built as recommended: sensor) |
| OP-M5b-3 | What to do if thumbnails after a relaunch raise a folder prompt | open (waits for C4b) |
| OP-M5b-4 | Settings defaults: tray while dragging on, shake off, auto-clear off, drops to the most recent box | open (built as recommended) |
| OP-M5b-5 | Zip stays deferred | open (built as recommended: no Zip) |

## 9. Review

A code review of the branch ran after stream E, through six lenses (Swift, spec, security, look, performance and failure
handling): 37 actionable findings (6 HIGH, 31 MEDIUM) and 22 LOW. Each was checked against the
code before it was changed; none was found wrong, though several were the same defect seen through different lenses
(they are grouped below). The fixes are commits `1e39423` … `fd3101d` (9) and the update of this record.

### 9.1 How the fixes were tested

Honestly, not every fix went test-first. For the shelf core and the store (ownership, identity, owned paths, item
ids, destination ids, strays, read and decode errors) the tests were written before the code; they failed to build
until the new API existed, so the first red was a build failure, then they passed. For the box controller, the tray,
the intake and the promise collector the tests were written together with each fix. Only the panel's key test was
also run against the old code and seen to fail there (`becomesKeyOnlyIfNeeded = true` → `isKeyWindow` false). The
views (VoiceOver actions, scroll-to-focus, entrance motion, badge size, the tray tile) have no unit test: SwiftUI's
accessibility actions and animations cannot be read back in a test here; the badge, tile and busy header are seen in
the re-taken captures (§4), the rest is QA §V.

### 9.2 Decisions

| ID | Decision | Why |
|---|---|---|
| D-M5b-23 | An owned copy stays owned only while its file is inside `Box/`; moved or located elsewhere it becomes a reference. Before the Trash takes an owned copy, the box checks the file is the item's own: its path, its resolved status, its identity when both are known, and not a symbolic link | A moved-out clipping freed its name, the next clipping took it, and removing the first trashed the second |
| D-M5b-24 | A drop picks its box id first (the current box, or the id the new box will take) and the intake writes into that folder; owned copies the library does not take and stray promise files go to the Trash; a clean launch and Empty Box Storage sweep copies no item (and no pending Clear) points at; a lossy, damaged or unreadable load never sweeps | Copies landed in a folder no box owned and could never be tidied; a crash in Clear's undo window left copies behind |
| D-M5b-25 | `boxes.json`: a read error leaves the file and refuses saves; a decode error sets it aside under the first free `boxes.damaged[ N].json`; a lossy load keeps `boxes.before-repair.json`; each is told once. Saves skip an unchanged library and re-read the file only when its inode, size or date differ from the last write or read | A passing I/O error cost the person their boxes; every save re-decoded the whole file on the main thread |
| D-M5b-26 | Bulk actions resolve their targets' bookmarks when they run and leave out a file whose identity changed; one runs at a time. The busy overlay and Cancel stay unwired (G-M5b-9) | Trash and Move acted on a path cached from an earlier show, and a second press lost the first task |
| D-M5b-27 | The tray resolves the box when its compact view really shows (not while the island measures it at rest) and asks for its own 40 pt thumbnails | The strip could not be dragged out in a fresh session, and nothing may be resolved at rest (P2-141) |
| D-M5b-28 | A promise wait ends once: when every named file called back, 0.5 s after the last callback for unnamed promises, or at 15 s + 5 s per file (at most 120 s), the rest counted as failed and named "The app it came from didn't hand over the file." | A sender that called back fewer times than predicted left the drop hanging and the panel in "Add" |
| D-M5b-29 | "New drops go to" becomes "BOX on the wheel adds to": only the slice chooses; a drop on the panel or at the notch goes to the box it lands on | OWN-APP-1; the old words promised what two drop routes did not do |
| D-M5b-30 | Thumbnails are asked for by the cells on screen (`onAppear`/`onDisappear`), live only in the cache (its 400 bound holds), cost one redraw per turn however many arrive, and use Quick Look's icon mode | Up to 100 full redraws per show, unbounded images, and white squares for documents |
| D-M5b-31 | A text or image clipping larger than 20 MB is refused | Owned copies count toward 2 GB and a pasted text had no bound |
| D-M5b-32 | The card enters as D-BL12 says (0.96 → 1 and opacity in the island's expand spring; a 0.18 s fade under Reduce Motion) and a thumbnail fades in over 0.12 s; the card still leaves at once (G-M5b-10) | Motion was specified but unbuilt; the exit fade needs the panel's ordering-out to wait, which the presentation does not model yet |

### 9.3 Findings and what was done

F = fixed, P = partly, S = skipped (with the reason). Lenses: sw Swift, sp spec, se security, lk look, pf
performance, fl failure handling.

| # | Sev | Lens | Finding | Done | How |
|---|---|---|---|---|---|
| 1 | HIGH | sw | The tray never resolves the box or loads thumbnails; strip drags empty, no badges | F | D-M5b-27; `TrayRealBoxTests` over a real controller after a relaunch |
| 2 | HIGH | sw | An owned item keeps `.owned` after leaving storage; a later clipping gets trashed | F | D-M5b-23 |
| 3 | MED | sw | `receivePromises` can hang or drop files; receivers may be released early | F | D-M5b-28; receivers held with `withExtendedLifetime`; `PromiseCollectorTests` |
| 4 | MED | sw | Copies written before the library accepts them are orphaned; over-cap reported as duplicates | F | D-M5b-24; `AddOutcome.overCap`, "The box is full." |
| 5 | MED | sw | Thumbnails: a redraw per arrival, an unbounded image dictionary, cancelled items never asked again | F | D-M5b-30 |
| 6 | MED | sw | Two items with one id in `boxes.json` crash every render | F | De-dup by id in `Shelf.adding` (the decoder uses it); `uniquingKeysWith` in the view model and `reordering` |
| 7 | MED | sw | Synchronous I/O on every change: storage walk, store re-decode, tray model for `isEmpty` | F | Storage bytes from the items; D-M5b-25 save stamp and unchanged-skip; `trayCount`/`trayBytes` |
| 8 | MED | sw | Bulk actions unguarded and not cancellable; busy overlay dead | P | One at a time (`runBulk`, D-M5b-26); the overlay, progress and Cancel stay unwired and the move executor is not cancellable (G-M5b-9) |
| 9 | MED | sp | Owned copies in `Box/<throwaway UUID>/`; empty folders left | F | D-M5b-24 (`ShelfLibrary.destinationID`, `newID`) |
| 10 | MED | sp | `relocated` keeps ownership outside the owned root | F | As #2 |
| 11 | MED | sp | Relocation keeps a stale `FileIdentity`; re-dropping the file adds a duplicate | F | `relocated(to:bookmark:identity:storage:)`; identity read at every relocation |
| 12 | MED | sp | "New drops go to: A new box" ignored by the panel and the tray | F | D-M5b-29 (the words, not the routes) |
| 13 | MED | sp | Record: Zip missing, P2-197 and shake bar unmeasured, HW rows unrun, Y3 failed under load | F (record) | §7 and §8 keep P2-142 (Zip), P2-197, P2-143 and P2-55's hardware rows open; Y7 now prints its numbers (G-M5b-6 closed); the quiet-Mac timing check stays G-M5b-5 |
| 14 | MED | se | A moved-out owned copy makes `trashOwnedCopies` trash an unrelated file | F | As #2 (D-M5b-23) |
| 15 | MED | se | Trash and Move act on a path cached from an earlier resolution | F | D-M5b-26. A single ⌘⌫ still goes to the Trash without a question, as 17e §2.3 says |
| 16 | HIGH | lk | A click never makes the panel key: no keyboard table | F | `becomesKeyOnlyIfNeeded = false`; a test sends a real mouse-down and mouse-up |
| 17 | MED | lk | Documents render as full-bleed white squares | F | Icon mode (D-M5b-30). Text files now show as white pages with Finder's margins; whether that reads well on glass is QA V7 (G-M5b-14) |
| 18 | MED | lk | Reduce Transparency / Increase Contrast while shown do not change the panel | F | `BoxWiring` observes the notification; `displayOptionsChanged()` redraws; tested with a finish change |
| 19 | MED | lk | D-BL11 and D-BL12 motion unbuilt, unrecorded | P | D-M5b-32; exit fade not built (G-M5b-10) |
| 20 | MED | lk | VoiceOver cannot select or act on items | P | Each item is a button with a toggle action and named actions; no list role (SwiftUI on macOS offers none) and not tried with VoiceOver (G-M5b-12, QA V4) |
| 21 | MED | lk | Arrows and type-to-select leave the selection off screen; nothing shows more items below | F | `ScrollViewReader` scrolls to the focus; the indicator is always visible. The visible height was not changed to show a partial row |
| 22 | MED | pf | Every selected cell builds the whole drag payload in its body | F | `FileDragSource(provide:)`: the payload is worked out when a drag starts |
| 23 | MED | pf | A 200-item drag fans 200 images across 800 pt | F | Only the first 5 dragging items carry the image; the rest add their file only. Not measured on a live drag (not possible headless) |
| 24 | MED | pf | Bookmarks made on the main thread inside `performDragOperation` | F | `ReferenceMaker` runs on a detached task for file drops and the BOX slice. Promise files are still made into items on the main actor (a few per drop) |
| 25 | MED | pf | Moving to the Trash is synchronous on the main thread | S | G-M5b-8: doing it off the main actor needs the busy overlay and an asynchronous remove and undo, so the library, the card and Undo stay consistent; not attempted here |
| 26 | MED | pf | Thumbnails: prefix(100) not cells on screen, no cancel on dismiss, full redraws, unbounded memory | F | D-M5b-30; dismiss cancels the cell requests |
| 27 | HIGH | fl | No timeout or per-promise error log | F | As #3; errors logged by domain and code |
| 28 | HIGH | fl | Move to… of an owned item later trashes an unrelated clipping | F | As #2 |
| 29 | HIGH | fl | `start()` ignores dropped items and a damaged file; `moveAside` overwrites the backup | F | D-M5b-25; `BoxLoad.notice`, told through `onError` |
| 30 | MED | fl | A read error is treated as corruption and the healthy file moved aside | F | `BoxLoad.unreadable` (D-M5b-25); the decode error is logged by kind and coding path only |
| 31 | MED | fl | The tray reports drops differently: "Only items stored on this Mac" for duplicates; refusals vanish | F | The tray maps through `AddOutcome.actionResult` and shows the card for what was left out |
| 32 | MED | fl | Share drops missing items silently; a failing service is unreported | F | A card lists them; `SystemSharePicker` is the service's delegate and reports a failure |
| 33 | MED | fl | `follow()` ignores the items whose new bookmark failed | F | Their status is left, they are not cleared, and each gets a line |
| 34 | MED | fl | The tray's bulk commands act on stale paths and report false success | F | As #15: targets are resolved at the action |
| 35 | MED | fl | Owned copies orphaned by duplicates, the cap, too many boxes or a failed bookmark | F | As #4 and #9 |
| 36 | MED | fl | A failed promise reported as a bookmark failure; non-file pasteboard items vanish | F | `ShelfError.promiseFailed`; "N items couldn't be added: only files and folders on this Mac can go in a box." |
| 37 | MED | fl | `finishClear` loses refused copies; an invalid relative path is skipped silently | F | Refused copies come back into their box with a card; an invalid path is a failure line |
| L1 | LOW | sw | Intake into a random UUID folder | F | As #9 |
| L2 | LOW | sw | `inFlight` keyed by id only; caller cancellation does not reach Quick Look | F | Requests keyed by item and size, joined, cancelled through `withTaskCancellationHandler` |
| L3 | LOW | sw | `TriggerHost.stop()` never ends a live drag for the hooks | F | `1e39423` |
| L4 | LOW | sw | The tray timing test is a load-dependent wall-clock bound | F | Structure on every attempt, the budget on the best of three (`fd3101d`); not a signpost measurement |
| L5 | LOW | sp | A crash in Clear's window orphans copies | F | The sweep at a clean launch (D-M5b-24), not a persisted marker |
| L6 | LOW | sp | `refreshStorage` walks `Box/` on every change | F | As #7 |
| L7 | LOW | se | `isInsideFolder` accepts `.`, a box folder, nested paths | F | Exactly `<uuid>/<name>`; symbolic links are never trashed. A promised folder (a package) is still trashed when it is the item's own |
| L8 | LOW | se | Copies left when the shelf refuses them; clippings unbounded | F | As #4; D-M5b-31 |
| L9 | LOW | se | Clear's window and a crash | F | As L5 |
| L10 | LOW | se | Copy to… into a link to a subfolder recurses | F | `c4af55a` |
| L11 | LOW | lk | Busy layout differs from 19c §4.1 and the overflow stays usable | P | The header's commands are hidden while busy; the progress bar still replaces the action bar (recorded in §5); busy is not driven (G-M5b-9) |
| L12 | LOW | lk | The offline-drive badge spills out of its circle | F | The glyph is fitted into 9 pt inside the 16 pt circle; seen in the attention captures |
| L13 | LOW | lk | A missing row's size stays at full ink | F | The size dims with the row |
| L14 | LOW | lk | No inner padding in the selection fill; no focus indicator | S | G-M5b-11: it changes the grid's metrics and every capture; left for the owner's look review (OS-M5b-3) |
| L15 | LOW | lk | "+N" tile has no hover or pressed fill; strip thumbnails may split for VoiceOver | F | `BoxTileButtonStyle`; each thumbnail is one element |
| L16 | LOW | pf | `resolveIfNeeded` resolves on the main thread at show | S | G-M5b-8: the panel draws statuses on the show that resolves them; resolving in the background needs an "unresolved" redraw pass; volumes are still read per missing item |
| L17 | LOW | pf | `persist()` saves unconditionally; each save re-decodes the file | F | As #7 |
| L18 | LOW | pf | `rest()` builds a full model to test emptiness | F | `trayCount` |
| L19 | LOW | pf | Y8's tray row never builds the real driver | F | The `box-armed` state (`022a536`) |
| L20 | LOW | fl | Resolution failures and save errors not logged usefully; save errors repeated | F | Counts logged after each resolution; the save log names the kind; the same error is told once until a save works |
| L21 | LOW | fl | The undo log ignores its schema and is overwritten when unreadable | F | `bb2f458` |
| L22 | LOW | fl | Y6 passes on an empty TCC stream | F | `022a536` |

## 10. Verification (2026-10-26, clean clone at `e163191`)

A fresh `git clone` of the local repository with `m5b` checked out (77 commits on top of `main`), run under
`nice -n 10` with the owner's other work going (load average 2.2–5.5). The clone did not rebuild the vendor tree: the
ignored `Vendor/out` (FFmpeg stage, CWebP, CZivletSVG) was copied in, and each component's stamp matched the cache
key computed in the clone, so `ensure-native` and `ensure-media` printed "up to date".

| Gate | Exit | Numbers |
|---|---|---|
| `make test` | 0 | 18 test bundles, 1771 tests, 0 failures |
| `make lint` | 0 | swift-format strict and the log-privacy check clean |
| `make coverage` | 0 | every one of the 16 gated modules ≥ 80 %: ZivletCore 97, ZivletTrigger 99, ZivletWheelCore 99, ZivletEngineKit 97, EngineMedia 97, EngineImage 95, ZivletRuntime 95, ZivletTriggerHost 93, ZivletWheel 96, ZivletActions 89, ZivletSettings 96, ZivletUI 95, ZivletNotchCore 98, ZivletNotch 96, **ZivletShelfCore 98 (950/966)**, **ZivletBox 93 (3251/3491)** |
| `make release-check` | 0 | no Homebrew path, island preview, Drop Box debug flag or drag recorder in Release; 2 helpers, 7 libraries; 45.0 MB installed (limit 85 MB) |
| `make app` | 0 | `BUILD SUCCEEDED` |
| `make licence-gate` | 2, then 0 | The first run failed: "licence file missing" for Sparkle and resvg, and "cargo tree listed no crates". The gate reads `Vendor/src` and `Vendor/downloads`, which a clone does not have and the copied `Vendor/out` does not bring. With the fetched sources copied in, it passed: "Licences OK: 13 components, 58 crates" |
| `make script-test` | 0 | 28 of 28 PASS on the first run (the media stage was already in place) |

Exit rows (Y1 and Y2 are the gates above, X1 is the same set, and Y3 runs X2–X5):

| Row | Result | What the log shows |
|---|---|---|
| Y3 | **fail**, then pass | First run under `nice`, two failures. X2: `NotchHUDTimingTests` missed its 50 ms bound (G-M5b-5). X3: `build/fixtures/small/srgb.heic` does not exist in a fresh clone, because `demo-notch.sh` does not make the fixtures (unlike `demo-box.sh`, which made them later, in Y4). X4 and X5 passed. Rerun by name, `make notch-timing` passed (1 test). Then Y3–Y6 were run together without `nice` at load about 2.5, and X2–X5 all passed |
| Y4 | pass (both runs) | `Box: shown`, `Box: items 4`, the panel captured, `Box: restored 4 items` |
| Y5 | pass (both runs) | 63 captures. Over white: panel 6.82:1, docked tab 4.99:1, tray drop target 5.55:1, pill drop target 5.13:1 (need 4.5:1) |
| Y6 | pass (both runs) | 6,224 TCC lines read in the first run; no request with `preflight=no` and no preflight check for Zivlet. A run of Y3 and Y6 alone was refused as designed ("Y6 needs Y3, Y4 and Y5 in the same run") |
| Y7 | pass | 17 tests in 2 suites. Synthetic drags: detection 98–100 % (49 or 50 of 50), 0 of 200 accidental opens on both displays. Synthetic only; P2-197 is still unmeasured |
| Y8 | pass | Debug: baseline 0.008 %. Panel shown 0.000 % over baseline, tray sensor 0.000 % over, armed box −0.008 % over (limit 0.1 %) |
| Y9 | pass | signed off, no `Co-Authored-By`, no file ≥ 800 lines, no personal path, shelf-core imports, no `NSAlert` in `ZivletBox` |
| X6 | **fail** | 8 states, 6 pass. indeterminate +1.225 %, fast-progress +1.784 % over the 1 % limit (progress +0.884 %, pill-progress +0.909 %). G-M5a-1 is still open, as in 15 §10 |
| X7 | pass | hygiene since the M5a baseline |

In the working repository, `make app` failed once, then passed. The failure was an incremental build that could not
copy Sparkle's `Installer.xpc` into a framework whose `XPCServices` folder `trim-sparkle.sh` had removed; a plain
rerun passed. With the screen awake (load about 2.3–4), `Scripts/demo-box-states.sh` wrote its 63 captures and the
same four contrast numbers to a folder outside the repository, and `Scripts/demo-box.sh` wrote the relaunch demo
(4 items, restored). All 64 images were looked at. None caught a surface before it drew, none clipped text, and no
new defect was found. Points already on record still show: the selection fill sits right against the item names
(G-M5b-11), text files are the brightest thing on the glass (G-M5b-14), and on the glass finish the collapsed card
lets text behind it show through.

A leak scan of `main..m5b` (patches and messages) found nothing to fix:
- All 77 commits are signed off, with one author and committer identity (the same as on `main`). None has
  `Co-Authored-By`.
- No personal or scratch path. The only `/Users/` strings are the `/Users/u/…` test fixtures and the hygiene check's
  own patterns.
- No `docs/research`, and no keys or tokens.
- "Open-Tangerine" appears only in the three clean-room sentences, as on `main`. No other notch or shelf app is named.
- No binaries: 281 files (255 Swift, 11 shell, 10 Markdown, the Makefile), the largest 45 KB.

Not run: the owner rows in [qa/drop-box.md](qa/drop-box.md), Release idle CPU, and recorded drags (OS-M5b-1). The
real accessibility settings, a real external display and real drags were not tried either.
