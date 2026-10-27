# 19 — M6 record: box follow-ups, the cap rule, the worker and Copy Text

Date: 2026-10-27. Status: **code complete on the local branch `m6`; reviewed, with the review's findings handled in
§10; not merged, not pushed**. Every
task of streams A–E in [18](18-implementation-plan-m6.md) is committed. In a clean clone the exit rows Z1–Z11 all pass
(§2), Z3 only in its second run (the 50 ms notch HUD timing test under load, as in M5a and M5b), and Z1 only after
a box test hang found by the first run was fixed (`96fe438`, G-M6-10). The OCR acceptance of P2-104 (12/12 Hindi
and English fixtures within 1 % CER) passes on rendered fixtures on macOS 27.0; real scans, Word- and Chrome-made
Hindi PDFs and macOS 26.x are not measured (owner steps). Read QR, the rest of P2-51, waits for P2-30.

This is a record, not a plan. The plan is [18](18-implementation-plan-m6.md) with its parts 18a–18e. Owner rows are
in [qa/copy-text.md](qa/copy-text.md), [qa/worker.md](qa/worker.md) and [qa/drop-box.md](qa/drop-box.md) (DB-A1 to
DB-A5); none of them has been run.

Clean-room rule: unchanged. No code, assets or UI strings from any other app. The OCR fixtures are sentences written
for Zivlet, drawn at test time with fonts that ship with macOS; no scan or downloaded image is used or committed.

Machine for every number below: 14-inch MacBook Pro (Mac14,9), macOS 27.0, Xcode 27.0, with the owner's other work
running (load average 1.3–5 during the runs). Debug builds unless a row says Release.

---

## 1. What was built

| Stream | What is on `m6` | Commits |
|---|---|---|
| Plan | plan 18 and its parts 18a–18e | `a2a009f` |
| A — box follow-ups (G-M5b-8, -9, -10) | Move to… and Copy to… report progress and stop between items (`MoveExecutor` checks cancellation before each step, never inside one); the box's busy overlay with the bar, Cancel and Esc, a "Stopped. N items weren't moved." card, and Undo for what moved; Move to Trash off the main thread in `BoxTrasher`, cancellable, recorded as one undo batch whose Undo puts the items back; resolving the box at show and making promise files into items off the main thread; the panel fades out (the island's collapse settle, at most 0.6 s; 0.18 s under Reduce Motion) and a show during the fade keeps it; two test-rig fixes for answers that came before their wait | `4c79fd2` … `b875c65` (10), QA rows `06d41c8` |
| B — P2-100 cap rule | each tool marked visible by default or extra (every current tool stays visible, D-M6-17); every wheel list capped at 12 with a lint over the default lists that prints one count line per list; the mixed-family rule as data (`ToolSpec.accepts`) instead of READ QR's hard-coded exception, pinned by 30 mixed sets; reserved slots (TRANSCRIBE in audio and video) counted by the lint | `c87d541` … `fccf1bb` (4) |
| C — P2-01 worker | `ZivletIPC` (versioned Codable envelope, requests, replies, events, boundary validation, peer requirement from the running code's own signature); `ZivletWorkerCore` (`WorkerService` with cancel and a 60 s idle exit, `WorkerXPCHost`); `WorkerConnection` in the runtime (lazy session, crash detection, reopen, cancel forwarding); `RemoteEngine` with a parity suite; one serial retry after a crash, then "This file made the engine crash."; `WorkerSelection` (worker when present, signed and answering, else in-process, decided at the first job); the `ZivletWorker.xpc` target embedded in `Contents/XPCServices`, hardened runtime, no entitlements; signing and bundle checks; app wiring for image conversions; a worker smoke run (`make worker-smoke`) | `57baf45` … `2de7e22` (13) |
| D — P2-51 base, P2-103, P2-104 | `OCRTestSupport` (CER per D-M6-12, 12 rendered fixtures from a JSON manifest); `EngineVision` (languages: Hindi first for Hindi users, English last, no auto-detect; capability probe that hides Hindi where Vision lacks it; `RecognizeDocumentsRequest` with an `.accurate` `RecognizeTextRequest` fallback; PDF pages from the text layer unless it is unusable or Devanagari, else OCR at 300 DPI; copy-protected PDFs refused; assembly with `— name —` separators; warm-up once per OS build and language set); text jobs in the worker only (Vision never runs in the app, D-M6-8); the COPY TEXT slice; clipboard for this Mac only and `X Text.txt` (UTF-8, no BOM, LF); the text card near the drop and at the notch and the Show All window; the "Text recognition" setting; tests that the text is never logged or stored; `make ocr-check`, `make copy-text-demo`, `make text-states` | `450142c` … `c4d59a1` (17) |
| E — QA and exit | QA rows `qa/copy-text.md` (CT1–CT13) and `qa/worker.md` (WK1–WK5); `Scripts/m6-exit.sh` (`make m6-exit`, `make cap-lint`); the cancelled box move demo (`make box-busy-demo`); a fix for a box test hang the exit run found; this record | `a68e6a8`, `1cb0082`, `a61a7aa`, `96fe438`, this commit |

50 commits from `9cc6c69` to `96fe438`, plus this record; about 12,400 lines added before stream E's fix.

## 2. Exit rows

A `git clone` of the local repository with `m6` checked out, the vendor tree (`Vendor/out`, `Vendor/src`,
`Vendor/downloads`) copied in as M5b did, so `ensure-native` and `ensure-media` printed "up to date" and nothing was
rebuilt from source. Everything under `nice -n 10` with the owner's other work going (load average 1.3 to 13).

**First attempt, at `a61a7aa`:** `make release-check` passed (73 s, "Release build contains no Homebrew path, no
island preview, no Drop Box debug flag, no drag recorder and no worker debug request", 52.4 MB installed). Z1 then
stalled: the `ZivletBoxTests` helper sat at 0 % CPU for over nine minutes in `aSecondRequestHitsTheCache`, after its
cache-hit expectation (line 127) had failed; `manyArrivalsInOneTurnDrawOnce` failed in the same run. A sample of the
hung helper showed the main thread idle in its run loop. The helper was stopped, Z1 failed, and every later row that
needs the Debug app failed with it. The cause and the fix are G-M6-10 (`96fe438`); after the fix the box bundle
passed four times in a row in the working repository (265 tests each). The clone was then fast-forwarded to
`96fe438` and the runners were started again.

**Second attempt, at `96fe438`:** `Scripts/m6-exit.sh` (938 s), then `Scripts/m5a-exit.sh --only
X2,X3,X4,X5,X6,X7` and `Scripts/m5b-exit.sh --only Y3,Y4,Y5,Y6,Y8,Y9` (X1, Y1 and Y2 are the same gates as Z1 and Z2;
Y7 runs inside Z3), then Z3 again by name.

| Row | Result | Time | What the log shows |
|---|---|---|---|
| Z1 | pass | 269 s | 21 test bundles, 2040 tests, all passed; lint clean; coverage (§3) with measured lines for `ZivletIPC` 100 %, `ZivletWorkerCore` 93 %, `EngineVision` 87 %; `make app` built; release-check clean (53.8 MB installed, §6); "Licences OK: 13 components, 58 crates in zivlet-svg's tree" |
| Z2 | pass | 232 s | `make script-test`, every script test PASS, the new `test-m6-exit.sh` and `test-box-busy-demo.sh` among them |
| Z3 | **fail**, then pass | 61 s, then 327 s | First run: X2's `NotchHUDTimingTests.aDropShowsTheIslandWithin50ms` missed its 50 ms bound at load about 13 (G-M5b-5, unchanged), so the M5b rows did not run. X3–X5 passed. Rerun by name at load about 2: X2–X5 and Y4, Y5, Y7 passed. X2 also passed inside the separate `m5a-exit.sh` run in between |
| Z4 | pass | 0 s | release-check had run in Z1; `ZivletWorker.xpc` in `Contents/XPCServices`, `Identifier=app.zivlet.Zivlet.Worker`, `flags=0x10002(adhoc,runtime)`, no entitlement keys |
| Z5 | pass | 40 s | worker pid 2477, app pid 2472 (first message 37 ms); PNG to JPEG in the worker 32 ms; cancel visible in 0 ms, the worker's single-frame encode ran on to 1891 ms (cancel is checked between frames); a killed worker relaunched in 48 ms and the job was saved; killed twice: "This file made the engine crash." and the next job saved (9.2 s: launchd's relaunch delay after repeated crashes); idle exit after 5.1 s (the smoke sets 5 s); no worker crash report |
| Z6 | pass | 16 s | Vision lists 33 languages, `hi-Deva` and `mr-Deva` among them; all 12 fixtures CER 0.000, 58–294 ms each (the model was already compiled from earlier runs, so no cold compile was timed); English only: Devanagari lost in 10 fixtures (the language-order trap the default avoids); stress set (printed, never scored) clean up to 30 % noise at 30 px and 20 % at 22 px; PDFs: English layer, Hindi, mixed, a scan and a WebKit-made Hindi PDF all CER 0.000 |
| Z7 | pass | 9 s | through the drop path: clipboard CER 0.000; with Option, `05_mixed Text.txt` and `mixed Text.txt`, UTF-8, no BOM, LF, CER 0.000; "No text found" for the blank image |
| Z8 | pass | 2 s | held at 20 of 50 with the overlay captured (`box-busy.png`); "Moved 20 items" and "Stopped. 30 items weren't moved."; after Undo the script counted 50 files back in `source`, 0 in `moved`, no hidden copy ("Moved back.") |
| Z9 | pass | 299 s | 68 captures: the five Copy Text states and every box and tray state; island text card 10.88:1 for white text at 0.8; over white: panel 6.82:1, docked tab 4.99:1, tray drop target 5.55:1, pill drop target 5.13:1 (need 4.5:1) |
| Z10 | pass | 1 s | 5,985 TCC lines read since Z5 started; no request with `preflight=no` and no preflight check for Zivlet or its worker |
| Z11 | pass | 9 s | every commit since `9cc6c69` signed off, none with `Co-Authored-By`; no changed `.swift` or `.sh` file at 800 lines or more; no personal or scratch path added; no `print(` in `Sources`, `App` or `Worker`; no added `NSAlert`; `import Vision` only in `EngineVision`; the Release worker has no entitlements; the cap lint's count lines are in the log (the fullest lists: mp4, mov and mkv single tools 10/12 with 1 reserved; pdf, rtf, rtfd and text clipping conversions 9/12) |

Earlier rows in the same round:

| Row | Result | What the log shows |
|---|---|---|
| X2–X5 | pass | in `m5a-exit.sh` (X2 15 s) |
| X6 | **fail** | Debug idle CPU over a 0.025 % baseline: hidden 0.000, collapsed −0.008, card-still −0.025, pill-progress +0.875, pill-progress-solid +0.808 pass; progress +1.075, indeterminate +1.250 and fast-progress +1.700 fail the 1 % limit. G-M5a-1, not worked on in M6 (the brief says so). Progress passed in the M5b record (+0.884); this run had WindowServer at 34 % beside it and load about 2–5; not compared on a quiet Mac |
| X7 | pass | hygiene since the M5a baseline |
| Y3–Y6 | pass | Y4 restored 4 items; Y5 the same four contrast numbers as Z9; Y6 no request that could prompt |
| Y8 | pass | Debug: baseline 0.017 %; panel shown, tray sensor and armed box each +0.008 % (limit 0.1 %) |
| Y9 | pass | hygiene since the M5b baseline |

## 3. Tests and coverage

21 test bundles, **2040 tests** in Z1 (1773 at the plan's baseline in 18 bundles), all passed. The
working repository's `make test` at `c4d59a1`, before stream E, ran 2039 tests in 21 bundles, all passed. Line
coverage from `make coverage` (gate 80 % per module, 19 gated modules, three of them new):

| Module | Lines | % |
|---|---|---|
| ZivletCore | 743/753 | 98 |
| ZivletTrigger | 696/703 | 99 |
| ZivletWheelCore | 362/362 | 100 |
| ZivletEngineKit | 859/868 | 98 |
| EngineMedia | 1186/1211 | 97 |
| EngineImage | 1240/1292 | 95 |
| ZivletRuntime | 2311/2442 | 94 |
| ZivletTriggerHost | 405/434 | 93 |
| ZivletWheel | 956/986 | 96 |
| ZivletActions | 778/856 | 90 |
| ZivletSettings | 283/291 | 97 |
| ZivletUI | 4614/4861 | 94 |
| ZivletNotchCore | 503/510 | 98 |
| ZivletNotch | 1067/1111 | 96 |
| ZivletShelfCore | 953/969 | 98 |
| ZivletBox | 3520/3777 | 93 |
| **ZivletIPC** (new) | 159/159 | 100 |
| **ZivletWorkerCore** (new) | 311/333 | 93 |
| **EngineVision** (new) | 349/400 | 87 |

Not in the numbers: the app target (`App/`, including the XPC transport `XPCSessionFactory` and the DEBUG demos) and
`Worker/main.swift`, which `swift test` cannot load (R7); Z5, Z7 and Z8 exercise them. The real-Vision tests run
only in `make ocr-check` (D-M6-13), so EngineVision's 87 % is with a fake recognizer.

## 4. Screenshots

With the screen awake, in the working repository at `a61a7aa`: `make text-states`, `make box-states`, the
busy demo and a tools wheel for an image. The pictures stay outside the repository (in `build/`, not tracked), as in
M5b. Looked at by the agent that ran stream E:

- `text-notchToast`, `text-notchCard` (the island's text card: three preview lines, "64 characters · Hindi and
  English", three symbol buttons), `text-hudCard` (the card near the drop), `text-showAll` (the Show All window,
  title "Text from ticket.png"), `text-setting` (Settings › General with the "Text recognition" row and its picker).
- `box-busy-glass`, `-solid`, `-contrast` (the longest verb, "Moving 200 items to the Trash", fits on one line;
  the bar at 40 % and the stop button; the contrast finish draws the button background) and `box-busy` from the
  demo ("Moving 50 items", the bar at 38 %).
- The tools wheel for `ticket.png`: COPY TEXT at the top, then COMPRESS, METADATA, EDIT, ANNOTATE, ADD BG, CROP,
  REDACT (8 slices).

No clipping, no misaligned rows, no unreadable text, and no capture took focus. Two notes: the first `make demo
MODE=tools` capture is full-screen and shows a video's tools (the demo's default file), so the image wheel was
captured with `-ZivletDemoFiles ticket.png` and cropped; and the full-screen capture caught the owner's other
windows behind the wheel, so it was deleted and not kept. Z9 in the clone wrote the same set again (68 files); its
busy capture was looked at too. **Not reviewed by the owner** (OS-M6-7). Not seen at all: the real Reduce
Transparency, Increase Contrast and Reduce Motion settings (flags stand in), the exit fade in motion, Light mode,
VoiceOver, the "Preparing text recognition (one time)…" line on a real first run, and a real drag onto COPY TEXT.

## 5. Deviations from the plan

| Item | Plan | What was done, and why |
|---|---|---|
| Reduce Motion exit (A5) | the brief: instant; D-BL12: 0.18 s fade | 0.18 s fade (D-M6-3); the choice stays with the owner (OS-M6-6) |
| Fixture 07's font (D1) | no font fallback in any fixture | ITF Devanagari has no Latin letters, so fixture 07 names Times New Roman as its one allowed fallback (CoreText's own choice); without it 07 could not be drawn (`450142c`) |
| Fixture geometry (D4) | — | the first real run read 10/12 ("ko" as "Ko", "Office" as "Offce"); the renderer then took the prototype's bitmap geometry and an opaque bitmap and the run read 12/12. It shows how little margin fixtures 02 and 06 have (`36a7805`) |
| "Match my languages" on this Mac | — | this Mac has no Hindi language or keyboard, so the default reads English only (the P2-103 rule) and the first Copy Text demo read the Devanagari as Latin letters (CER 0.396); the demo now pins "Hindi and English" for its run only (`786319d`). A person on a Mac like this one gets English-only recognition unless they change the setting |
| Same-family image mixes (D9) | — | a mix such as HEIC + WebP + AVIF now shows COPY TEXT alone where it showed READ QR: the P2-100 rule (shared tools first), recorded in the table (`8781072`) |
| Busy overlay demo (E2) | the demo "cancels after 20" | the app holds after the 20th file until the script has captured the overlay, then presses Cancel; the overlay shows the bar at 19 of 50 drawn (38 %) because item 20's progress is reported after the hold |
| WK2 (E1) | `make worker-smoke CONFIG=release` | the smoke mode exists only in Debug builds, so the row asks for a Debug build signed with the Developer ID for the full smoke, and a Developer ID Release for the TeamIdentifier and log check |
| Z4 in the runner (E2) | `make release-check` again | skipped when Z1 passed in the same run (Z1 already ran it); `--only Z4` still builds |
| Z11's NSAlert check (E2) | "no NSAlert in new code" | any added Swift line with `NSAlert` since `9cc6c69` |
| PNG → JPEG time in-process vs worker (E4) | `make bench` | **not measured**: `make bench` has no worker mode. The worker smoke gives the relaunch and cancel times instead (§2 Z5). G-M6-11 |
| App size before the worker (E4) | `size-gate.sh` before and after | not rebuilt at `9cc6c69`; compared with the M5b record's 45.0 MB at `e163191` (§6) |
| Box thumbnail store (found in E4) | — | a new `ThumbnailStoring` port (`96fe438`), see §7 G-M6-10 |

## 6. Size

| Build | Installed | Notes |
|---|---|---|
| M5b record, `e163191` | 45.0 MB | from 17 §10 |
| `m6`, first `make release-check` in the clone (`a61a7aa`) | 52.4 MB | `Contents/MacOS` 14.2 MB, `libav*` 29.8 MB, Sparkle 1.3 MB, Helpers 0.6 MB, Resources 0.6 MB; the worker bundle 5.8 MB (its binary 5.8 MB) is in the total only |
| `m6`, release-check inside Z1 (`96fe438`) | 53.8 MB | the same, except Sparkle measured 2.8 MB; why the Sparkle line differs between the two builds was not looked into |

So the worker adds about 5.8 MB, mostly the image engines linked a second time (R5); the app's own binary did not
shrink because the in-process fallback keeps them (D-M6-9). Well under the 85 MB limit; the choice is OS-M6-9. No
build of `9cc6c69` was made for a same-day comparison.

## 7. Gaps

| ID | Gap | Next step |
|---|---|---|
| G-M6-1 | EngineMedia stays in-process (D-M6-5) | A later task moves it with PID events and orphan reaping across XPC |
| G-M6-2 | Read QR (the P2-51 tool and its results window) is not built (D-M6-6); P2-51 is only partly done (the EngineVision base) | With P2-30 |
| G-M6-3 | History (P2-145) is absent; only "nothing stores the text" is tested | With P2-145 |
| G-M6-4 | Hindi on macOS 26.x is unverified; this Mac runs 27.0 | OS-M6-2 |
| G-M6-5 | Word- and Chrome-made Hindi PDFs are not in the fixtures; only CoreText- and WebKit-made PDFs were read | OS-M6-3 |
| G-M6-6 | Real scans and phone photos are not measured (P2-191) | OS-M6-4 |
| G-M6-7 | Whether the worker shares Vision's compile cache with other processes was not measured beyond Z6's first-call time | — |
| G-M6-8 | The full ordered language list of 17c §1.1 is not built (D-M6-14) | After the owner uses the picker |
| G-M6-9 | `SubprocessRunnerTests.aChildIgnoringSIGINTIsKilledAfterTheGrace` finished too early once in the baseline (0.41 s). Not investigated in M6 | Look at the child's signal set-up before SIGINT is sent |
| G-M6-10 | The box bundle hung in the first exit run: `NSCache` dropped a test image under memory pressure, so a gated request was never finished. Fixed with a store port (`96fe438`); the hang was diagnosed from the log and a sample of the hung process, and the fix was **not** seen to stop a reproduced hang (four box-bundle runs after it passed; none before it hung on demand). A hung helper from an earlier session (10 hours old, same bundle) was also found and stopped | Watch the box bundle in later runs; `flaky-watch.sh` if it recurs |
| G-M6-11 | PNG → JPEG time in-process vs in the worker was not measured | Add a worker mode to `make bench` |
| G-M6-12 | `size-gate.sh` does not print `Contents/XPCServices` as its own line (the worker's 5.8 MB is only in the total) | Add the line |
| G-M6-13 | No branch review (the six-lens review M5b had) was run on `m6` | **Closed**: run after `857dfab`; findings in §10 |
| G-M6-14 | Copy Text has no fallback in the app when the worker is unavailable (D-M6-8): it says "Text recognition isn't available right now." | By design; revisit if the worker is ever absent in practice |
| G-M5a-1 | The fast-progress CPU item from M5a | Unchanged and untouched |

## 8. Owner steps

| ID | Step | State |
|---|---|---|
| OS-M6-1 | Developer ID build: worker smoke and the same-team requirement (QA WK2) | open |
| OS-M6-2 | macOS 26.x: Hindi listed, 12 fixtures, cold compile time (QA CT13) | open |
| OS-M6-3 | Two Hindi PDFs of your own words, from Word and from Chrome, read with `make ocr-check PDFS=<folder>` (QA CT5) | open |
| OS-M6-4 | Real Hindi scans and phone photos, private (QA CT8) | open |
| OS-M6-5 | Copy Text and a conversion on files in Desktop, Documents and Downloads with the worker on (QA CT9) | open |
| OS-M6-6 | Reduce Motion exit of the Drop Box: keep the 0.18 s fade or make it instant | open |
| OS-M6-7 | Look review of the text card, Show All and the setting row (the pictures in §4) | open |
| OS-M6-8 | VoiceOver on the text card and Show All (QA CT10) | open |
| OS-M6-9 | App size: keep the image engines linked into both the app and the worker, or plan a shared framework (§6) | open |
| OS-M6-10 | Merge and push `m6` | open |
| OS-M6-11 to -13 | Added by the review round | see §10.7 |

## 9. Not measured, not seen, not tested first

- **Not measured:** PNG → JPEG in the app vs in the worker (G-M6-11); a cold Vision compile in this round (Z6's
  model was warm; stream D measured 46.6 s once); the P2-104 Word and Chrome PDFs; real scans; macOS 26.x; Release
  idle CPU; anything on a quiet Mac.
- **Not seen:** any owner row in `qa/copy-text.md`, `qa/worker.md` or `qa/drop-box.md` DB-A1 to DB-A5; a Developer
  ID build (only ad-hoc, so the same-team peer requirement never ran); Copy Text on files in Desktop, Documents or
  Downloads (the hard limits forbid it here); VoiceOver; a real drag; the exit fade in motion.
- **Tested with the fix rather than first:** stream E's own tests went red first (`test-m6-exit.sh` with no script,
  `test-box-busy-demo.sh` with no Makefile target, `test-release-flags.sh` on the new flag, the thumbnail store as a
  build failure), but the DEBUG busy demo's Swift (`App/BoxBusyDemo.swift`) has no unit test: it is covered only by
  Z8. The box hang fix was not seen to stop a reproduced hang (G-M6-10). For streams A–D this record relies on the
  commit messages; it did not re-check that each of their tests was seen to fail first.
- **Not reviewed:** no branch review (G-M6-13). The `pkill`/`osascript quit` in the older demo scripts would also
  quit a Zivlet the owner had open; the runs here started with none open.
- **Leak scan of `9cc6c69..96fe438`:** 50 commits, one author and committer identity, all signed off, none with
  `Co-Authored-By`; no personal or scratch path (the only home-folder strings are a `/Users/me/…` test value and the
  hygiene check's own patterns; temporary paths are generic test values such as `/private/tmp/out`); no research
  notes referenced; no other app named; no binary file.

---

## 10. Review round (after `857dfab`)

A branch review of `m6` (six lenses: Swift, spec, look, failure, security, performance) gave 19 actionable findings
(one HIGH, 18 MEDIUM) and 28 LOW ones. Each was checked against the code first; where behaviour changed, a test was
written first and run against the old code to see it fail, except where §10.6 says otherwise. This closes G-M6-13.

### 10.1 Commits

16 commits from `857dfab` to `ff7450c` (plus this update), about 1,850 lines added and 350 removed:

| Commit | What |
|---|---|
| `aeae7b7` | worker: a cancel that comes before its job is remembered (64 at most) and the job is answered cancelled without starting; the text warm-up runs as a tracked step under its own job id (protocol version 3); failed text jobs and warm-ups log their kind |
| `fe72477` | runtime: the cancel goes on the session its request used, never a new one; `close()` latches (later calls throw `.cancelled`); a channel dropped for a crash is closed; the warm-up is cancellable; events are documented and tested as best-effort |
| `6a59d3d` | a line wrap in a test (typed `style:`, which is not one of the owner's commit types; left as is, since history is not rewritten) |
| `16c41c0` | ui: `ActionResult.working(WorkingStatus)`; the island draws a working action with the ring and stop.circle, counts it as running, never closes it with Escape, updates it in place and swaps it for its result in one board change; near the drop: line, bar, Cancel and Escape; a cancelled result removes the line; the app's `WorkingLine` keeps the task and its Cancel stops it |
| `9cf89ec` | tools: per-file skipping (`RecognizedText.skipped`), notes on the text card for files not read, a refused clipboard ("Text found") and `.txt` files not saved; saving goes on past a failure and runs off the main thread; `tooManyFiles`; "No text found. Hindi isn't available on this Mac."; failure and cancel logging; one warm-up at a time |
| `e06359b` | vision: an empty documents result falls back to the accurate request; a photo's decoded area is capped at 25 MP |
| `d6ed971`, `cac3079` | ui: Show All answers ⌘C and ⌘A, follows Reduce Transparency and Increase Contrast live (solid with a 1 pt outline); the near-drop text card's buttons get the 28 pt round hit area and a Close with Escape |
| `5799187` | runtime: the worker choice logs its cause; an unreachable worker is tried again after 60 s on a new session |
| `2ed0d27` | box: a refused Move to Trash says why (no permission, read-only disk, gone) and logs the kind |
| `3ad008b` | scripts: Z6 needs its 12 fixture lines, 5 PDF lines and a warmed first recognition (new test, at most 3 s); Z11 fails on an unknown base or no commits; honest fixture comments |
| `aa47ecc` | ci: `make ocr-check` in the nightly workflow |
| `a7cd961`, `ff7450c` | scripts: the M6 demos quit only the app they launched (`Scripts/app-process.sh`) and delete only their own folder; the busy demo reports the bar it drew; the text states demo captures the working line |
| `4eae944` | lint: the new loggers use allowed categories |
| `a0764e2` | QA rows CT14–CT16 and a wider CT11 |

### 10.2 Decisions

| ID | Decision |
|---|---|
| D-M6-20 | P2-103's "determinate 'Preparing text recognition (one time)…'" is **not** determinate: during a job the one-time compile happens inside Vision's first request, which reports no progress, so the line has no percent until the first page or file is read and then shows "Recognising text… N%". The background warm-up's three images are measurable, but they are not what a waiting job shows. A deviation from the task list's wording, recorded here |
| D-M6-21 | Show All keeps `NSGlassEffectView` (an AppKit window around an `NSTextView` in the system appearance); recorded as 19b D-NL14, the one exception to D-NL2 |
| D-M6-22 | Worker events are best-effort: XPC sends a reply on the request's own reply port, so an event may arrive after its step's reply and is then dropped; the reply carries the outcome. A late `.spawned` can only name a process whose step already ended |
| D-M6-23 | Cancels are sticky in the worker: one that arrives before its job is kept (64 at most, oldest dropped) and the job, when it comes, is answered cancelled without starting |
| D-M6-24 | A Copy Text drop is no longer all-or-nothing: a file-level error (unreadable, locked, copying not allowed, too large, too many pages, recognition failed) skips that file and names it; a cancel, a missing engine or a crashing worker still stop the job |
| D-M6-25 | An unreachable worker is not final for the launch: the first job 60 s later tries again on a new session. Missing and damaged stay final |

### 10.3 Gates

In the clone, fast-forwarded to `a0764e2` (`Vendor/out`, `src` and `downloads` as before, nothing rebuilt from
source), under `nice -n 10`, load average 2.5–5:

| Row | Result | What the log shows |
|---|---|---|
| Z1 | pass, 227 s | 21 bundles, **2081 tests**, all passed; lint clean; coverage of all 19 modules over 80 % (below); app built; release-check clean, 54.1 MB installed (MacOS 14.4, libav* 29.8, Sparkle 2.8, Helpers 0.6, Resources 0.6 MB); "Licences OK: 13 components, 58 crates in zivlet-svg's tree" |
| Z2 | pass, 229 s | every script test PASS |
| Z3 | **fail**, then pass | first run: `NotchHUDTimingTests.aDropShowsTheIslandWithin50ms` over its 50 ms bound at load about 5 (G-M5b-5); rerun by name at `ff7450c`: X2–X5 and Y4, Y5, Y7 pass (324 s) |
| Z4 | pass | the Release worker: identifier, hardened runtime, no entitlements |
| Z5 | pass, 39 s | worker pid 53727 (first message 28 ms); PNG → JPEG 34 ms; cancel visible in 0 ms, the single-frame encode ran on to 1893 ms; crash retry, relaunch 51 ms; crash twice: "This file made the engine crash." and the next job saved (9.2 s); idle exit 5.1 s; no crash report |
| Z6 | pass, 17 s | 12/12 fixtures CER 0.000 (53–322 ms); warmed first recognition 85 ms; English only loses Devanagari in 10 fixtures; PDFs english, hindi, mixed, scan and webkit CER 0.000. Stress set, printed and never scored: **8 of 12 cells above 1 %** (16 px: 0.024, 0.071, 0.381, 1.000 at 10, 20, 30, 45 % noise; 22 px: 0.024, 0.000, 0.048, 0.429; 30 px: 0, 0, 0, 0.071). So 12/12 says the clean fixtures read exactly, not how phone photos or scans read. The models were already compiled: no cold compile was timed |
| Z7 | **fail**, then pass | first run: the new folder guard refused the clone's `build/copy-text-demo`, left by a run from before the marker; fixed (`ff7450c`: the default folder is the script's own) and rerun: pass, 10 s |
| Z8 | pass, 2 s | "held at 20 of 50, the bar drawn at 19 of 50"; "Moved 20 items", "Stopped. 30 items weren't moved."; after Undo 50 back, 0 left |
| Z9 | pass, 313 s | 70 captures, the two new working states among them; island text card 10.88:1; over white 6.82, 4.99, 5.55 and 5.13:1 |
| Z10 | pass | 6,804 TCC lines since Z5; no request with `preflight=no` |
| Z11 | pass, again at `ff7450c` | hygiene since `9cc6c69`, now with a checked base |
| X6 | **fail**, 1194 s | G-M5a-1, untouched: over a 0.025 % baseline, hidden −0.008, collapsed −0.017, card-still −0.017, progress +0.842, pill-progress +0.850, pill-progress-solid +0.867 pass; indeterminate +1.117 and fast-progress +1.708 fail the 1 % limit (M5b: +1.225 and +1.784; the review: +1.108 and +1.717) |
| X7 | pass | hygiene since the M5a baseline |
| Y3–Y6 | pass | Y6 first failed because Y4 and Y5 were not in the same run (the row needs them); rerun as `--only Y3,Y4,Y5,Y6`: all pass |
| Y8 | pass, 531 s | baseline 0.017 %; panel, tray sensor and armed box each +0.008 % (limit 0.1 %); no run of another session quit the app this time |
| Y9 | pass | hygiene since the M5b baseline |

The working repository's `make test` at `4eae944` also passed (2081 tests in 21 bundles, 56 s incremental).

Coverage (gate 80 %): ZivletCore 98, ZivletTrigger 99, ZivletWheelCore 99, ZivletEngineKit 98, EngineMedia 97,
EngineImage 95, ZivletRuntime 94 (2379/2512), ZivletTriggerHost 93, ZivletWheel 96, ZivletActions 91, ZivletSettings
97, ZivletUI 94 (4892/5161), ZivletNotchCore 98, ZivletNotch 96, ZivletShelfCore 98, ZivletBox 93, ZivletIPC 100,
ZivletWorkerCore 94 (351/371), EngineVision 86 (377/435, with a fake recognizer).

Screenshots of the changed states, looked at by the agent with the screen awake: `text-notchWorking` (the ring,
"Recognising text… 40%", stop.circle), `text-hudWorking` (the line, the bar at 40 %, Cancel), `text-hudCard` (the
round buttons and the new Close), `text-showAll`, `text-notchCard`, `text-notchToast` and `box-busy`. Copies stay
outside the repository, as before. No clipping or unreadable text seen. Not seen: the working line during a real job,
a press of Cancel on screen, Show All under the real Increase Contrast setting, the notes on a real card.

### 10.4 Findings

| # | Finding | Outcome |
|---|---|---|
| F1 | Cancel not sticky; it can overtake its request | **fixed** (`aeae7b7`, `fe72477`, D-M6-23) |
| F2 | A cancel reopens a dead worker; `close()` does not latch | **fixed** (`fe72477`) |
| F3 | ActionHUD keeps the working line on `.cancelled` | **fixed** (`16c41c0`) |
| F4 | P2-104 "CI fixture fails if Devanagari is lost" runs only in Z6 | **fixed** in the workflow (`aa47ecc`); the nightly job has **not run** (no runner here) |
| F5 | P2-103's "determinate" preparing line | **partly**: recorded as deviation D-M6-20, not made determinate |
| F6 | Events and replies are not ordered; two flaky tests | **fixed** as best-effort (D-M6-22), tests relaxed; no event count was added |
| F7 (HIGH) | Copy Text cannot be cancelled from the UI | **fixed** (`16c41c0`): stop.circle on the island, Cancel and Escape near the drop |
| F8 | The working line draws as done | **fixed** (`16c41c0`) |
| F9 | The island hides between the line and the result | **fixed** (`16c41c0`). Also found while fixing it: the island's toast kept the *first* line; later percents never reached it |
| F10 | "Preparing…" for the whole first job | **fixed** (`16c41c0`): the percent from the first progress event |
| F11 | Show All: no ⌘C or ⌘A | **fixed** (`d6ed971`); confirmed by a test against the old code (both keys did nothing) |
| F12 | The warm-up cannot be cancelled | **fixed** (`aeae7b7`, `fe72477`); cancelling a cold compile was not timed |
| F13 | A failed Copy Text never logs why | **fixed** (`9cf89ec`, `aeae7b7`) |
| F14 | = F3 (failure lens) | **fixed** |
| F15 | ⌥ saving stops at the first failure and loses the card | **fixed** (`9cf89ec`) |
| F16 | A refused clipboard drops the result | **fixed** (`9cf89ec`) |
| F17 | A multi-file job is all-or-nothing and the file is not named | **fixed** (`9cf89ec`, D-M6-24) |
| F18 | An empty documents result skips the fallback; the first error is lost | **fixed** (`e06359b`): the fallback runs and the first error's type is logged |
| F19 | Z11 passes on a missing base | **fixed** (`3ad008b`) |
| L1 | A channel dropped for a crash is never closed | **fixed** (`fe72477`); the strong capture in the session's cancellation closure was left |
| L2 | = F12 | **fixed** |
| L3 | One unstructured task per progress event | **partly**: progress only moves forward and is drawn once per percent (`16c41c0`); no AsyncStream |
| L4 | `reachWorker` never cancels the loser; the decision is cached for the launch | **partly** (`5799187`): the timer is cancelled, causes are logged, unreachable is retried after 60 s; the ping itself cannot be cancelled, and `choice()` still ignores its caller's cancellation |
| L5 | Unbounded polls, a 100 ms wall-clock bound, no cancel-before-register test | **fixed** for the M6 tests; older polls (`OrphanReaperTests`, `DecodeBudgetTests`) left as they were |
| L6 | Z6 passes with no measurements; no 3 s check | **fixed** (`3ad008b`) |
| L7 | The fixture comments overstate; 12/12 quoted without the stress set | **fixed** (comments in `3ad008b`; stress numbers in §10.3) |
| L8 | P2-100 reserved slots, and `accepts` for actions | **skipped**: no Combine PDF, Reel, archive or lock action, or TRANSCRIBE exists yet; to be added with them (G-M6-15) |
| L9 | P2-01, P2-51 and P2-104 clauses partly met | **recorded**: the task list has no status column, so status stays here: P2-01 partly (MediaEngine in-process, G-M6-1), P2-51 partly (the base only, G-M6-2), P2-104 partly (History, G-M6-3) |
| L10 | Demos quit any Zivlet | **fixed** for the M6 demos (`a7cd961`); `box-idle.sh` and `notch-idle.sh` (pre-M6) still quit every Zivlet (G-M6-16) |
| L11 | X6 fails (G-M5a-1) | **skipped**: not M6 work |
| L12 | = F1 | **fixed** |
| L13 | No aggregate bound per text job; header limit 200 MP | **partly**: Cancel now stops a huge job and a photo decodes to 25 MP at most; no total page or byte budget, header limit unchanged (G-M6-17) |
| L14, L22 | The Copy Text demo deletes any folder it is given | **fixed** (`a7cd961`, `ff7450c`) |
| L15 | Show All reads Reduce Transparency once, ignores Increase Contrast, uses NSGlassEffectView | **fixed** (`d6ed971`, D-M6-21) |
| L16 | The text card's buttons are small; no Close or Escape | **fixed** (`d6ed971`) |
| L17 | The busy demo's picture is one item behind its claim | **fixed** (`a7cd961`): hold.json and the row report the drawn bar (19) |
| L18 | The worker is launched at every app launch for the warm-up check | **skipped**: measured cheap by the review (30–51 ms, 12 MB, exits after 60 s idle); avoiding it needs the capabilities stored beside `text.warmed` (G-M6-18) |
| L19 | No area cap for photos | **fixed** (`e06359b`, 25 MP); accuracy on small text in large photos not measured |
| L20 | `.txt` files written on the main actor | **fixed** (`9cf89ec`, `@concurrent`) |
| L21 | The warm-up is partly silent and not serialised | **fixed** (`9cf89ec`) |
| L23 | Over 200 files reported as "damaged"; the type not checked in the app | **partly**: `tooManyFiles` with its own sentence; the type check stays in the worker (an unsupported file is now named as not read) |
| L24 | Hindi dropped silently | **fixed** for "No text found" (`9cf89ec`); a result *with* text gets no note |
| L25 | The worker choice drops its causes and never retries | **fixed** (`5799187`) |
| L26 | A failed cancel send is ignored | **fixed** (`fe72477`): logged; the worker remembers early cancels |
| L27 | The Trash error is dropped | **fixed** (`2ed0d27`) |

### 10.5 Gaps added

| ID | Gap | Next step |
|---|---|---|
| G-M6-15 | P2-100: actions carry no `accepts` data and the slice builder does not hold reserved slots back (no list is over 10/12 today) | With Combine PDF, Reel, archive or lock, or TRANSCRIBE, plus a builder test |
| G-M6-16 | `box-idle.sh` and `notch-idle.sh` still quit every Zivlet | Move them to `Scripts/app-process.sh` |
| G-M6-17 | No total page or byte budget per Copy Text job; a large image under the 200 MP header limit is decoded in full before it is scaled | A job budget in the validator and `TextReader`, measured on large photos |
| G-M6-18 | The app contacts the worker at each launch to check the warm-up record | Store the capabilities beside `text.warmed` |
| G-M6-19 | A blank page now costs two Vision requests (documents, then accurate) | Measure on long scans with blank pages |
| G-M6-20 | Escape on the near-drop working line works only once the panel is key (the panel never takes the keyboard on its own, D-M4-16) | As for every HUD card |

### 10.6 Tested first, or not

Seen to fail against the old code before the fix: the cancel-before-register worker test, the warm-up `cancelAll`
test, four of the five connection tests (the fifth, a cancel right after the call starts, passed already), the first
five working-line tests (the HUD after a cancel, the island's ring, closable, toast line, one board change), the
skipped-file reader test, the empty-documents fallback test, the area cap test, ⌘A and ⌘C in Show All, the Z6 and
Z11 runner cases, and the nightly workflow check. Written against the new API, so they could only fail to compile
against the old code: Cancel on both presenters, the list row, the delivery and note tests, the decode-side
function, Show All's live display options, the selection retry, the Trash refusal and `tooManyFiles`. Not run against
the old code on purpose: the Copy Text demo's folder guard (the old script would have deleted the test's folder). The
new 3 s test ran only in Z6, with warm models.

### 10.7 Owner steps added

| ID | Step | State |
|---|---|---|
| OS-M6-11 | Press Cancel on a long Copy Text at the island and near the drop, and check the worker's CPU falls (QA CT14) | open |
| OS-M6-12 | Confirm the nightly OCR job runs on the self-hosted runner (macOS with Hindi) | open |
| OS-M6-13 | Look at the working line pictures and the text card's Close | open |

Merge and push stay with the owner (OS-M6-10): `m6` is local, ahead of `main` (`9cc6c69`), and not pushed.

## 11. Verification (after `2b2522c`)

A fresh `git clone` of the local repository with `m6` at `2b2522c` checked out, and `Vendor/out`, `src` and
`downloads` copied in, so nothing was rebuilt from source. Everything ran under `nice -n 10` with the owner's other
work going (load average 1.2–3.6). The gates ran in this order, each once:

| Gate | Exit | What the log shows |
|---|---|---|
| `make test` | 0, 107 s | 21 bundles, **2081 tests**, all passed |
| `make lint` | 0, 4 s | clean (swift format strict, log privacy) |
| `make coverage` | 0, 116 s | all 19 modules over 80 %, the numbers below |
| `make release-check` | 0, 73 s | no Homebrew path, island preview, Drop Box debug flag, drag recorder or worker debug request; 52.6 MB installed (limit 85) |
| `make app` | 0, 30 s | Debug build succeeded |
| `make licence-gate` | 0, 5 s | "Licences OK: 13 components, 58 crates in zivlet-svg's tree" |
| `make script-test` | 0, 238 s | 33 of 33 script tests PASS |
| `Scripts/m5a-exit.sh` | **1**, 1345 s | X1 **fail**: `WorkerRetryTests.aCrashIsRetriedOnceAndEveryJobOfTheBatchSucceeds` (below). X2–X5 and X7 pass. X6 **fail**: G-M5a-1, untouched; over the baseline, indeterminate +1.100 and fast-progress +1.709 fail the 1 % limit; hidden, collapsed, card-still, progress (+0.842), pill-progress (+0.850) and pill-progress-solid (+0.809) pass |
| `Scripts/m5b-exit.sh` | **1**, 1373 s | Y1 (2081 tests, all passed), Y2 and Y4–Y9 pass (Y8: panel, tray sensor and armed box within 0.1 %). Y3 **fail**: X2's 50 ms notch HUD timing test (G-M5b-5) |
| `Scripts/m6-exit.sh` | **1**, 931 s | Z1 pass (2081 tests, all passed), Z2 pass, Z3 **fail** (X2's 50 ms timing test again), Z4–Z11 pass. Z5: crash retry relaunched in 52 ms, crash twice named the file, idle exit 5.1 s, no crash report. Z6: 12/12 fixtures CER 0.000, 5 PDFs CER 0.000, warmed first recognition 85 ms. Z7: clipboard and both text files CER 0.000, "No text found" for the blank image. Z8: held at 20 of 50, 20 moved and 30 left, 50 back after Undo. Z9: 70 captures, island text card 10.88:1, over white 6.82, 4.99, 5.55 and 5.13:1 |

Each failure was run again once by name. `Scripts/m6-exit.sh --only Z3` then passed (X2–X5 and Y4, Y5, Y7, 344 s),
so Z3 failed on timing only, as in M5a and M5b. **The retry test did not pass again.** Run alone it failed 16 times in
20 runs (and in 2 of 2 separate runs before that). Inside a full `make test` it passed 3 times out of 4. When it fails, files that were not the
crashing one (`a.png`, `b.png`, `e.png`) end as `[queued, preparing, retrying, cancelled]` instead of being saved, and
`maxConcurrentRetries` is 2 to 4. The loopback counts a retried prepare until its verify, so the cancelled retries
inflate that count. At `857dfab` it passed 10 of 10. At `aeae7b7` ("remember a cancel that comes before its job") it
failed 8 of 8, so that commit brought the failure in. The test's loopback keeps one `WorkerService` across its
simulated crashes. A cancel sent for a job lost in the crash is remembered, and that job's retry, which keeps its
`JobID`, is answered as cancelled. In the real app the crash ends the worker process and its list of remembered
cancels, and Z5's crash retry passed. So this may only happen in the test rig, but nobody has shown that. Not fixed
here: **G-M6-21** (open). Fix the rig, or the remembered-cancel path, so a retry is never matched to a cancel from
before the crash. Then make the test pass alone 20 runs in a row.

Coverage (gate 80 %): ZivletCore 98 (743/753), ZivletTrigger 99, ZivletWheelCore 99, ZivletEngineKit 98, EngineMedia
97, EngineImage 95, ZivletRuntime 94 (2380/2512), ZivletTriggerHost 93, ZivletWheel 96, ZivletActions 91 (794/872),
ZivletSettings 97, ZivletUI 94 (4892/5161), ZivletNotchCore 98, ZivletNotch 96, ZivletShelfCore 98 (971/988),
ZivletBox 93 (3528/3785), ZivletIPC 100 (159/159), ZivletWorkerCore 94 (351/371), EngineVision 86 (377/435, with a
fake recognizer).

Pictures: in the working repository at `2b2522c`, with the screen awake, `make app`, then `demo-text-states.sh`,
`demo-box-busy.sh`, `make copy-text-demo` (PASS: clipboard CER 0.000, two text files, "No text found") and
`demo-box-states.sh`, all exit 0. That made 71 images: 7 text states, `box-busy`, and 63 box and tray states. The
agent looked at every one; the 63 box and tray states were checked on labelled contact sheets. No clipping,
overlapping or unreadable text, and no blank surface. Things to know, none of them a defect in the app: some island
and tray crops are wider than the island, so a few pixels of the desktop behind show at the edges. The glass and Show
All are blurred over whatever windows were behind them. Settings › General cuts off at "Progress and results", which
is reached by scrolling. Only the near-drop text card has Close; the island's card has none, as `d6ed971` intends.
**Not reviewed by the owner** (OS-M6-7, OS-M6-13).

Leak scan of `main..m6` (68 commits, 238 files: 135 added, 103 changed). Every commit is signed off. None has
`Co-Authored-By`; the string only appears in hygiene scripts, their tests and the plan. There are no personal, home or
scratch paths: the only `/Users/` strings are the `/Users/me/…` test value and the hygiene pattern itself. No
`docs/research`, no secrets, and no names of other apps in the patches or the messages. No binary files at all: the
OCR fixtures are drawn at test time and only `ocr-fixtures.json` (2.6 KB) is committed. The biggest added file is
plan 18 (41 KB).

Result: every gate passes in a clean clone except the `WorkerRetryTests` failure (G-M6-21), the 50 ms timing test that
passes when run again (G-M5b-5) and X6's idle CPU (G-M5a-1). Merge and push stay with the owner.

## 12. G-M6-21 fixed (after `68d179e`)

Commit `28d9014` `fix(worker): keep each step under the session that sent it`. G-M6-21 is **closed**.

Cause, read from the code. §11's guess was close but not exact.
- The rig's simulated crash failed every waiting call, so the scheduler could start its retries at once. Only then did a separate task send `.cancel(job)` for each job it had seen running. A retry that keeps its `JobID` could already be running by then, and it was cancelled with the lost steps. A cancel that landed just after a step ended was remembered instead, and the retry's next step was answered as cancelled.
- The real worker had a related gap. When a session ended, the worker called `cancelAll()` on its one `WorkerService`, which stops every running step in the process. If a session broke while the process lived (for example, an unreadable reply), the old session's end could stop a retry already started on the new session. This path was not seen to happen; it was found by reading the code.

Fix.
- A new `WorkerSessionID` keys each step and each remembered cancel by session as well as job.
- `cancelAll()` became `endSession(_:)`, which stops only that session's steps and forgets its early cancels.
- `WorkerXPCHost` gives each incoming session its own ID.
- In the loopback, each channel is a session, and a crash ends that session. A request that reaches a closed channel now fails with `.workerCrashed` instead of starting, as a dead session's calls do.
- Callers that pass no session use `.single`, so other `handle` calls are unchanged.

Tests.
- New `WorkerSessionTests` (3 tests): ending a session stops only its own steps; a cancel reaches only its own session's job; an ended session forgets its early cancels.
- These three were seen to fail only by not compiling, since the API is new. The behaviour they guard was seen failing through the existing retry test.
- `WorkerRetryTests.aCrashIsRetriedOnceAndEveryJobOfTheBatchSucceeds` run alone: 20 of 20 pass (16 of 20 failed before).

Gates in the working repository, under `nice -n 10`.
- `make test`, `make coverage` and `make app` passed (ZivletWorkerCore 94 %, 367/387).
- `make lint` first failed on one long line. After that fix it passed, and the 44 ZivletWorkerCore tests were run again and passed.
- **Not rerun** after this fix: the clean clone, `make release-check`, `make licence-gate`, `make script-test` and the three exit scripts (Z5's real-worker crash retry among them).
