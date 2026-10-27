# 19 — M6 record: box follow-ups, the cap rule, the worker and Copy Text

Date: 2026-10-27. Status: **code complete on the local branch `m6`; not reviewed, not merged, not pushed**. Every
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
| G-M6-13 | No branch review (the six-lens review M5b had) was run on `m6` | Run it before merging |
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
