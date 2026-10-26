# 18e — M6 Stream E: QA rows, exit runner, screenshots, record

Part of [18-implementation-plan-m6](18-implementation-plan-m6.md). Conventions: index §6. Exit rows: index §7
(Z1–Z11). Pattern: `Scripts/m5b-exit.sh` and [16f](16f-m5b-qa-exit.md). Swift and shell below are
specification-grade and were not run.

---

## Task E1 — QA rows

| Field | Value |
|---|---|
| Goal | New `docs/plan/qa/copy-text.md` and `docs/plan/qa/worker.md`; new rows in `docs/plan/qa/drop-box.md` for Stream A. Each row: ID, steps, expected result, automated (row name) or owner, status. No result is written until it is seen |
| Effort | S |

`qa/copy-text.md` rows (owner unless marked):

| ID | Row |
|---|---|
| CT1 | (Z7) One image with Hindi and English → clipboard text matches; the card shows three lines, the count, "Hindi and English" |
| CT2 | ⌥-drop → `photo Text.txt` beside the image, opens in TextEdit as UTF-8 with LF |
| CT3 | Three images → one text with `— name —` separators; ⌥ → three `.txt` files |
| CT4 | A blank image → "No text found", nothing written |
| CT5 | A PDF with a text layer (English) → the layer's text; a Hindi PDF made in Word, one made in Chrome (OS-M6-3) → text by OCR, read by the owner |
| CT6 | A PDF with copying disallowed → "This PDF doesn't allow copying its text." |
| CT7 | First Copy Text after a fresh install: "Preparing text recognition (one time)…", then the text; time written down |
| CT8 | Real Hindi photos and scans (OS-M6-4): text read by the owner; CER only if a ground truth is typed |
| CT9 | Files in Desktop, Documents, Downloads (OS-M6-5): no permission prompt, or one naming Zivlet |
| CT10 | VoiceOver: the card's buttons are announced with their labels; Show All's text is readable line by line (OS-M6-8) |
| CT11 | Reduce Transparency and Increase Contrast: the card and Show All keep a solid finish and ≥ 4.5:1 |
| CT12 | Setting "Text recognition": each choice changes the next result's languages; on a Mac without Hindi the Hindi choices are disabled with the help text |
| CT13 | macOS 26.x (OS-M6-2): languages listed, 12 fixtures, cold compile time |

`qa/worker.md` rows:

| ID | Row |
|---|---|
| WK1 | (Z5) Worker smoke on Debug |
| WK2 | (OS-M6-1) Worker smoke on a Developer ID Release: the team requirement is used (log line) |
| WK3 | Activity Monitor shows `ZivletWorker` during a conversion and not 60 s after the last job |
| WK4 | Quitting Zivlet during a conversion leaves no worker and no staging file |
| WK5 | A hostile image (a truncated HEIC, a huge-dimension PNG header) fails with a message and the app stays up |

`qa/drop-box.md` new rows: DB-A1 Move 200 items to a USB drive, Cancel part-way, Undo; DB-A2 Copy to… with Esc;
DB-A3 Trash 200 items, Cancel, Undo brings files and items back; DB-A4 hide the box with Reduce Motion on and off
(fade visible, no jump); DB-A5 show a box with 100 items on a disconnected drive: the panel draws at once, items
grey a moment later.

Commit `docs(qa): rows for Copy Text, the worker and the box follow-ups`.

---

## Task E2 — `Scripts/m6-exit.sh`

| Field | Value |
|---|---|
| Goal | Rows Z1–Z11 (index §7) in order, each in its own `bash` process with errexit (as `m5b-exit.sh` does), logs in `build/m6-exit/<row>.log`, one line per row: pass, fail or skip; exit 1 if any row failed or was skipped. `--only Z1,Z5`, `--list`. Env for tests: `ZIVLET_M6_EXIT_LOGS`, `ZIVLET_M6_LOG` (replaces `/usr/bin/log`), `ZIVLET_M6_BASE` (default `9cc6c69`). New modules for Z1's coverage check: `ZivletIPC ZivletWorkerCore EngineVision`. Z10 refuses to run without the demos of Z5–Z9 in the same run (like Y6). Z11's checks: `git log --format=%B` has `Signed-off-by` on every commit and no `Co-Authored-By`; `git diff --name-only $BASE..HEAD` files under 800 lines; no personal or scratch path added (the Y9 pattern); `grep -rn 'print(' Packages/ZivletKit/Sources App Worker` empty; `grep -rln 'import Vision' Packages/ZivletKit/Sources` only under `EngineVision`; the worker's entitlements empty (`codesign -d --entitlements - --xml` on the Release build); the cap lint's count lines copied into the log |
| Acceptance | `Scripts/tests/test-m6-exit.sh` with stub commands: every row passes; a failing row fails the run; a locked-screen skip makes the run fail with "skipped: screen locked"; `--list` prints 11 rows; an unknown row is refused |
| Effort | M |

**Files:** create `Scripts/m6-exit.sh`, `Scripts/tests/test-m6-exit.sh`; modify `Makefile` (`m6-exit`, `ocr-check`,
`worker-smoke`, `copy-text-demo`, `text-states`, `box-busy-demo` in `.PHONY`).

RED: `Scripts/tests/test-m6-exit.sh` fails (no script). Commit `test(scripts): the M6 exit runner`.

The box-busy demo (Z8) is built here because it only drives Stream A's code: a DEBUG flag `-ZivletBoxBusyDemo
<folder>` makes 50 files in `<folder>`, adds them to a demo box (never `boxes.json`, as Y4), moves them to a second
folder in `<folder>` (DEBUG destination, no open panel), cancels after 20, captures the busy overlay, checks the
partial result, runs Undo and checks the 20 are back. `Scripts/demo-box-busy.sh`, `make box-busy-demo`, its shell
test, and the flag in `check-release-paths.sh`. Commit `test(box): a cancelled bulk move with Undo, on screen`.

---

## Task E3 — Screenshots of the new UI

| Field | Value |
|---|---|
| Goal | With the screen awake (`ioreg -n Root -d1 -a \| grep -i CGSSessionScreenIsLocked` first): `make text-states` (text card at the notch, text card near the drop, Show All, the setting row), `make box-states` (adds busy with a fraction), `make demo MODE=tools` with an image (COPY TEXT on the wheel). Rerun a capture that caught a blank surface once before calling it a defect. As in M5b, the PNGs stay in `build/` (not tracked) and the record lists them by name and says what was reviewed |
| Acceptance | every state captured or the record says which were skipped and why (locked screen, load) |
| Effort | S |

No code and no commit.

---

## Task E4 — Exit run and record

| Field | Value |
|---|---|
| Goal | Run every gate in a fresh clone of `m6` (`make release-check` first for the media stage; copy `Vendor/src` and `Vendor/downloads` in for `licence-gate`), then `Scripts/m5a-exit.sh`, `Scripts/m5b-exit.sh`, `Scripts/m6-exit.sh`, under `nice -n 10`, rerunning a timing failure once by name. Measure the app size with `Scripts/size-gate.sh` before and after the worker (R5, OS-M6-9) and the PNG → JPEG time in-process vs worker (`make bench`). Write `docs/plan/19-m6-record.md` (next free number) in the pattern of `17-m5b-record.md`: what was built, exit rows with their output, tests and coverage per module, screenshots, deviations from this plan, gaps (carry G-M6-1 … G-M6-9 and add new ones), owner steps, and an honest list of what was not measured, not seen or tested with the fix rather than first |
| Acceptance | the record exists, every claim in it points at a command output from this run, and the branch is left unpushed for the owner |
| Effort | S |

Commit `docs: record M6`.
