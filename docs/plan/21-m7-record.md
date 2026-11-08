# 21 — M7 record: reliable tests, the tool window, passwords, qpdf and PDF lock

Date: 2026-11-07, with the review follow-up of 2026-11-08 in §15. Branch `m7`, made from `m6` at `5107be7`; not
pushed, `main` and `m6` untouched. Plan:
[20](20-implementation-plan-m7.md) and its parts [20a](20a-m7-reliability.md)–[20g](20g-m7-qa-exit.md). Each part
ends with its stream's execution notes; this record sums them up, adds stream F, and gives the exit run. Nothing here
is claimed that was not run; what was not run, not measured or not seen says so.

---

## 1. Summary

Every task of streams R, A, B, C, D, E and F is committed. M7 delivers: tests that judge behaviour instead of wall
time, with real-time budgets judged only in a timing target below a stated load (P1-40, NFR-9 measured there); the tool
window (P2-30) and READ QR (P2-51); the password sheet and its policy (P2-101, P2-102); qpdf 12.4.2 with
libjpeg-turbo 3.2.0, built once, static, in the worker only, through a shim of our own (P2-13); PDF pre-flight,
limits and verify (P2-105); LOCK · UNLOCK with change password (P2-106) and locked PDFs in Copy Text and Read QR
(P2-107, without conversions, which wait for P2-12). Stream F adds the owner's QA rows, `Scripts/m7-exit.sh`, the
demos and captures of the new UI, and this record.

**Exit run** (§3, §4): in a fresh clone, the gates passed (2541 tests in 23 bundles, 21 modules at or over 80 %) and
`Scripts/m7-exit.sh` passed V1, V2 and V5–V13. V4 was **not judged** in the run (load 4.9). Its rerun by name was
judged at load 2.81: every budget met, NFR-9 again shown as a known issue (§5). V3 was **not run**, and neither were the earlier runners' rows that quit every Zivlet: a Zivlet this run had not
launched was open (D-M7-59). Their last results, at `a7ad58c` in the same clone, are in §4. The exit run found one more
defect: `make tool-states` left each state's app open, 49 per run. It is fixed (`ed6c756`) and V11 passed again.
**Open for the owner:** §12.

**Review follow-up (§15, 2026-11-08).** A review of M7 raised 20 findings and 10 LOW ones. 13 commits (`3c29e88`..
`1bc0829`) fix 18 of the 20 and part of one (NFR-9: a hard ceiling now fails, the 1 s budget stays the owner's), and
9 of the 10 LOW ones, the tenth in part (P2-107's conversions wait for P2-12). One more defect was found and fixed on
the way: a Change written decrypted (F-21). The licence finding is fixed as far as an agent may go: qpdf's MD5 notice
is declared and shipped, and a release refuses it until the owner decides (OS-M7-15). The one finding skipped is the
rerun of the rows that quit every Zivlet: a Zivlet this session did not launch was open again.

---

## 2. Scope delivered, per stream

| Stream | Rows | Commits | Detail |
|---|---|---|---|
| R — tests under load | G-M5b-5, G-M6-9, the ffmpeg cancel and the card linger | R1 `af8f8f3`, R2 `625cb21`, R3 `6ef9ffe`, R4 `29e21e8` `90b4f87`, R5 `a738638`, R6 `8bf0930` `5d2c092`, R7 `4954de5`, then `fa9c851` | [20a](20a-m7-reliability.md) execution notes |
| A — tool window, Read QR | P2-30, P2-51 | A1 `0ae81bd`, A2 `d528e99`, A3 `05468d1`, A4 `7a09962`, A5 `ee101d3`, A6 `74b5dbf`, A7 `d47da18`, A8 `fc53159`, A9 `d82bf8a`, A10 `7178823`, fixes `d27555b` `f092c3b` | [20b](20b-m7-tool-window.md) |
| B — password sheet and policy | P2-101, P2-102 | B1 `0a4d6e2`, B2 `c93e2cb`, B3 `1b95579`, B4 `13d9a65`, B5 `6814ef1`, B6 `73f6b60`, fixes `e4f62ed` `a8f69f7`, B7 `f0f3cf4` `2b68988` `3a39e3a` | [20c](20c-m7-password-sheet.md) |
| C — qpdf | P2-13 | C1 `d6f12fc`, C2 `8535435` `8dcfe1c` (with `c47b5df` `2b5b237` `2ae546a`), C3 `bb424f3`, C4 `fb79e0f`, C5 `d14151c` (with `8460320`), C6 `b266f41` `239840f` `3559f48` | [20d](20d-m7-qpdf.md) |
| D — pre-flight and verify | P2-105 | D1 `22b56e4`, D2 `06967d8`, `770ce0f`, D3 `91b5df7`, D4 `e2bf319`, D5 `5aaea0d`, `9c6931d`, attempt 2 `f349846` `47b1288` | [20e](20e-m7-pdf-preflight.md) |
| E — lock, unlock, change; locked inputs | P2-106, P2-107 | E1 `616a273`, E2 `b08e5e3`, E3 `1344f77`, E4 `a15b591`, E5 `524e463`, E6 `d5b437b`, E7 `ab91b89`, E8 `a3a23dc`, E9 `c81de3d`, E10 `bdaf472`, E11 `abe050a`, `6f643dd`, `6d73e67` | [20f](20f-m7-pdf-lock.md) |
| F — QA, exit runner, demos, record | — | F1 `5ab5ac3`, F2 `5138cf0` and `a7ad58c`, F3 `9dcf587`, the island card fix `b9b7af6`, the tool states quit fix `ed6c756`, F4 this record | §9 |

Each stream's record commit (`363ff97`, `3483d2b`, `4eedbf6`, `db6e2e2`, `56663fb`, `ed489f0`, `81db377`, `695c5cc`,
`3b9a3ba`) holds its gates, its deviations and what it did not do.

---

## 3. Exit rows V1–V13 (`Scripts/m7-exit.sh`)

Run in the fresh clone at `a7ad58c`, `nice -n 10`, screen awake, `--only` every row but V3 (D-M7-59): 20:52 → 21:27,
load 6.5 → 4.6 (1-minute; up to 16.5 during V1). The runner exited 1 (V4 skipped). V11 and V13 were run again at
`ed6c756` after the fix found here.

| Row | Result | What it showed |
|---|---|---|
| V1 | pass, 486 s | `make test`: 2541 tests in 23 bundles, none failed; lint; coverage, all 21 modules ≥ 80 % (§6); app; release-check, 57.1 MB; licence gate, 15 components |
| V2 | pass, 371 s | `make script-test`: 42 script tests and the PDF-writes check |
| V3 | **not run** | D-M7-59. At `a7ad58c` in this clone earlier the same day, every row it repeats passed: X2 (judged at load 2.94; the app's drop 16.7 ms of 50), X3, X4, X5, Y4, Y5, Y7 (inside M6's Z3) and Z4, Z5, Z7, Z8; Z4 again at `ed6c756` (§4) |
| V4 | **skip, not judged** | `timing: not judged (load 1m 4.88 > 3.0)` after the 10-minute wait; the rerun by name, §5 |
| V5 | pass, 166 s | both signatures; CQPDF arm64 only, minos 26.0, native crypto, no OpenSSL or GnuTLS, no build paths; the Release worker links no crypto, TLS, qpdf or JPEG library; qpdf in the worker only; both licence texts in the bundle, both tarballs at their pins; the worker 8.46 MB, at most 2.31 of 4.5 MB added |
| V6 | pass, 92 s | 24 checks in the real worker: lock, lock with restrictions, unlock, unlock that needs the owner password, change, a wrong password retried, the legacy AES and RC4 inputs, a form's fields kept; each locked output opens with its password and refuses another; 18 samples of the app's and the worker's command lines: no password, no child process; every secret file deleted |
| V7 | pass, 24 s | `make password-policy`: 49 tests in five bundles; `check-secrets.sh` |
| V8 | pass, 19 s | 11 checks: lock, unlock and change through the drop path, each output checked by PDFKit with the passwords on stdin |
| V9 | pass, 15 s | three codes from two images and a PDF, payloads equal, Open only beside the web link; the results window captured by its number |
| V10 | pass, 12 s | one password sheet, then the text with CER 0.000; the secret file deleted |
| V11 | pass, 273 s; **again at `ed6c756`** | 49 captures, 45 contrast readings, the lowest 11.17:1. It left the 49 apps it launched open (§8, fixed in `ed6c756`). Run again after the fix: 48 captures right the first time; one caught its window before it was drawn and passed when run again (G-M7-34); never more than one app at a time, none left |
| V12 | pass, 2 s | 6090 TCC lines since V6 began; no request with `preflight=no` from Zivlet or its worker |
| V13 | pass, 19 s | hygiene since `5107be7`, cap counts listed; the record's own commit was scanned before it was made (§14) |

---

## 4. Gates in a fresh clone

One clone of the local repository, made at `a7ad58c` with `Vendor/out`, `Vendor/src` and `Vendor/downloads` copied in;
nothing was rebuilt (`ensure-native.sh`: CWebP, CZivletSVG and CQPDF "up to date"; media "up to date"). Everything ran
under `nice -n 10` with the screen awake. The first pass ran on 2026-11-07 from 14:31 and was cut off at 16:53, when
the session running it ended (SIGTERM). This session kept its logs and continued from there with §3 and the rows below.
Load is the 1-minute average before → after.

| Step | Commit | Result | Time, load |
|---|---|---|---|
| `make test` | `a7ad58c` | pass: 2541 tests in 23 bundles, none failed | 140 s, 6.1 → 19.5 |
| `make lint` | `a7ad58c` | pass | 11 s, 19.5 → 16.8 |
| `make coverage` | `a7ad58c` | pass, 21 modules ≥ 80 % (§6) | 142 s, 16.8 → 23.7 |
| `make app` | `a7ad58c` | pass | 56 s, 23.7 → 14.7 |
| `make release-check` | `a7ad58c` | pass, 57.1 MB of 85 (§7) | 83 s, 14.7 → 14.3 |
| `make licence-gate` | `a7ad58c` | pass, 15 components, 58 crates | 6 s, 14.3 → 13.4 |
| `make script-test` | `a7ad58c` | pass, 42 tests and the PDF-writes check | 317 s, 13.4 → 4.5 |
| `make timing` | `a7ad58c` | **not judged**, load 4.44 > 3.0 after 10 minutes (exit 3) | 603 s, 4.5 → 4.4 |
| `Scripts/m5a-exit.sh` | `a7ad58c` | exit 1. X1, X3–X5, X7 pass. X2 **skip** (not judged, load). X6 **FAIL**, idle CPU (G-M5a-1, not worked on): `collapsed` 0.108 % over 0.1 %, `progress` 1.100 %, `indeterminate` 1.367 % and `fast-progress` 1.808 % over 1 %. X7 again at `ed6c756`: pass. X6 not run again (D-M7-59) | 3254 s, 4.4 → 4.7 |
| `Scripts/m5b-exit.sh` | `a7ad58c` | exit 1. Y1–Y7 and Y9 pass (Y3 with X2 judged). Y8 **FAIL**: `panel-still` 0.275 % over 0.1 %, started at load 13.4 (G-M7-21). Y9 again at `ed6c756`: pass. Y8 not run again (D-M7-59) | 2032 s, 4.7 → 22.7 |
| `Scripts/m6-exit.sh` | `a7ad58c` | cut off in Z9. Z1–Z8 pass (Z3: X2 judged at load 2.94, X3–X5, Y4, Y5, Y7). Z9 wrote the Copy Text states (contrast 11.63:1) and was stopped in `box-states`; Z10 and Z11 not reached. At `ed6c756`: Z4 and Z11 pass; Z3, Z9 and Z10 not run (D-M7-59) | from 16:22 |
| `Scripts/m7-exit.sh` | `a7ad58c` | §3 | 2081 s, 6.5 → 4.6 |
| `make timing`, rerun by name | `ed6c756` | **judged at load 2.81, every budget met**; NFR-9 a known issue (§5) | 182 s, 6.9 → 2.75 |

Not done, against F4's plan: each failure rerun once by name. `make timing` was rerun (§5). X6 and Y8 were not: both
quit every Zivlet, and one this run had not launched was open (D-M7-59). Both had failed before, with the reasons
recorded (G-M5a-1, G-M7-21).

---

## 5. Real-time budgets (`make timing`, D-M7-3)

`make timing` ran three times in the clone. At `a7ad58c` in the first pass (14:44) and as V4 (21:07), it was **not
judged**: the load stayed above 3.0 for the whole 10-minute wait (4.44 and 4.88 at the end). The rerun by name at
`ed6c756` (21:42, started at load 6.9) was **judged at load 2.81** (2.75 after), with 12 tests in 5 suites: **every
budget met**, and NFR-9 shown as a known issue, not hidden. `ed6c756` changes only a demo script, so the timing suites
are the same code as at `a7ad58c`.

| Budget | Suite | Reading (judged at 2.81) | Verdict |
|---|---|---|---|
| P1-40: a drop shows the island ≤ 50 ms, warm drops | `NotchHUDTiming` | 19 warm drops: p50 3.2 ms, p95 5.4 ms, slowest 5.4 ms | met |
| P1-40, the cold first drop of a process (G-M7-10) | `NotchHUDTiming` | 36.3 ms | met this time; it has measured 23–94 ms (OS-M7-12) |
| P1-40 in the app, X2's `drop→island` signpost | m5a X2 | 16.7 ms, judged at load 2.94 (Z3, first pass) | met |
| NFR-9: an ffmpeg cancel's process group gone ≤ 1 s | `MediaCancelTiming` | cancel → SIGINT 0.0 ms; SIGINT → exit 1068.8 ms (SIGKILL at the grace); exit → return 0.5 ms | **missed by 69 ms**, a known issue (G-M7-3, OS-M7-7); the budget is unchanged |
| P1-20: subprocess teardown within the 1.5 s bound (1 s grace) | `SubprocessTiming` | a child ignoring SIGINT 1063.6 ms; a group with a background member 1.7 ms; beside 80 children 1067.9 ms | met |
| FR-107: pre-flight of a 100-page PDF ≤ 50 ms | `PreflightTiming` | plain p95 2.0 ms; AES-256 with its password p95 27.8 ms | met |
| none: a 10,000-page PDF at the page limit | `PreflightTiming` | 103.8 ms, one read | printed, not judged |

Earlier readings for comparison: stream R judged at 2.54 (every budget met), stream D's pre-flight at 2.92 (1.7 and
21.3 ms), stream R's split of the ffmpeg cancel at 1066–1074 ms.

---

## 6. Coverage per module

`make coverage` in the clone (load 16.8 → 23.7): 21 modules, every one at or over 80 % (the gate fails below). V1's
own run matched it but for one line each in two modules: ZivletCore 888/900 and ZivletIPC 266/266 (100 %).

| Module | Lines | % | Module | Lines | % |
|---|---|---|---|---|---|
| ZivletCore | 889/900 | 98 | ZivletUI | 6614/7172 | 92 |
| ZivletTrigger | 696/703 | 99 | ZivletNotchCore | 503/510 | 98 |
| ZivletWheelCore | 379/380 | 99 | ZivletNotch | 1067/1113 | 95 |
| ZivletEngineKit | 940/947 | 99 | ZivletShelfCore | 971/988 | 98 |
| EngineMedia | 1186/1211 | 97 | ZivletBox | 3528/3785 | 93 |
| EngineImage | 1240/1292 | 95 | ZivletIPC | 265/266 | 99 |
| ZivletRuntime | 2708/2896 | 93 | ZivletWorkerCore | 469/487 | 96 |
| ZivletTriggerHost | 405/434 | 93 | EngineVision | 531/590 | 90 |
| ZivletWheel | 956/986 | 96 | **EnginePDF** | 862/876 | 98 |
| ZivletActions | 794/872 | 91 | **CZivletPDF** (the shim, C++) | 471/512 | 91 |
| ZivletSettings | 302/312 | 96 | | | |

The app target (`App/`) and the worker's `main.swift` are not measured by `coverage.sh`; the DEBUG demos of §9 run in
the exit rows instead.

---

## 7. Size and qpdf

| Measure | Value |
|---|---|
| Installed, `m6`'s first clone (`a61a7aa`, [19](19-m6-record.md) §6) | 52.4 MB, the worker bundle 5.8 MB |
| Installed, `m7` in this clone (`make release-check`) | **57.1 MB** (limit 85): `Contents/MacOS` 16.2, `libav*` 29.8, Sparkle 1.3, Helpers 0.6, Resources 0.7, the worker 8.5 |
| Release worker binary without qpdf (`8460320`, 20d C6) | 6,150,560 bytes |
| Release worker binary, this clone | 8,464,208 bytes |
| Growth since then | 2.31 MB: an upper bound of what qpdf and libjpeg-turbo add, as it also holds streams D and E's worker code. Stream C measured qpdf and libjpeg-turbo alone at 1.74–1.76 MB (20d). Both are inside 10 §9's 4.5 MB, so OS-M7-9 is not needed |
| qpdf build | Once, on 2026-10-29: 30 s at load 3.3 → 8.8 (G-M7-1); nothing was rebuilt since, in the repository or the clone (`ensure-native.sh`: "CQPDF up to date") |

The Release worker links only system libraries (no crypto, TLS, qpdf or JPEG library), holds qpdf's code, and the app's
own binary holds none (`check-bundle.sh` in `release-check`, and V5).

---

## 8. Screenshots of the new UI

`make tool-states` wrote 49 PNGs into `build/tool-states/` (not tracked; copies and contact sheets in the session's
scratch folder): the ten password sheet states and Read QR's results window, each in glass, Reduce Transparency
(`-ZivletIslandFinish solid`) and Increase Contrast (`contrast`); the lock, unlock, change and wrong-password cards
opened on the island in the three finishes, and near the drop in glass. `make qr-demo` captured the real results
window of its run.

**What they show.** The sheets: Lock empty with its reason "Type a password" (G-M7-13's disabled reason, seen), the
mismatch reason "Passwords don't match", Suggest filled and revealed with "Strong", the Devanagari password with the
Preview warning, the restrictions with "Owner password — shown once" and its Copy, Unlock after a wrong password ("That
password didn't work.", white, with Change password… and the no-recovery line), the batch with "Use the same password
for all 3 files", the retry sheet listing two files, Change with three named fields, and the owner-needed sheet. Read
QR: three rows from two files with their file headings, Open only beside the web link, "Page 2 · Not a web link"
beside the mail link, and Close and Copy All. The cards: "Locked with AES-256", "Unlocked", "Password changed" over the
file and its sizes with Undo, Reveal, Open and Copy; "That password didn't work." with Retry and Close. Under Increase
Contrast the windows gain a thin outline and the buttons a filled circle.

**Contrast.** Over a text-free box of each tool window (lower left, inside the padding) and each island card (as
`demo-text-states.sh`), white text at 0.8: 45 readings, all at least 4.5:1. In glass, 12.27:1 over the tool windows
(surface luminance 0.005) and 12.11:1 over the island cards (0.006). In both fallbacks, 11.17:1 over every surface
(0.012), the lowest. The exit run's V11, and its run after `ed6c756`, read the same values. These are Zivlet's own
surfaces drawn alone: a window capture has no backdrop behind the glass (D-M7-54), so a light desktop behind the glass
was not measured.

**Defects found and fixed:** the island's opened card said "Saved Budget 2026 Locked.pdf" for a lock (`b9b7af6`,
D-M7-58). `make tool-states` left every app it launched open, 49 per run (`ed6c756`, §9). Nothing was clipped,
misaligned or unreadable, and no capture took focus from the frontmost app.

**V11 after the fix** (`ed6c756`, in the clone, load 5.3): the agent looked at contact sheets of all 49 again. Two
captures were wrong the first time and right when run again, so they are not counted as defects (G-M7-34).
`password-lockSuggested-solid` came out as a blank 340 × 32 pt strip of the right window, caught before it was drawn.
`password-change-contrast` showed Suggest, Cancel and Change dimmed and no focus ring, as in a window that is not key;
run again, it matched the earlier run. What took key from the window at that moment was not found (QA TW5).

**Looked at** by the agent that ran this stream (contact sheets of all 49 and the Read QR demo's window), **not by a
person** (OS-M7-6). **Not seen:** typing in the sheet, VoiceOver, the system's Suggest, the real accessibility
settings (flags stand in), Light mode, the glass over a real backdrop, the cards near the drop in the two fallbacks,
the working lines of a protect batch, the island's one-line toast for a protect batch (only its opened card), the
bipolar slider and the timecode field (no tool uses them yet).

---

## 9. Stream F, as executed

**Baseline.** `make test` on `3b9a3ba` (stream E's record, the tree clean): 2537 tests in 23 bundles, all passing,
load 4.5 → 5.8.

**F1 — QA rows (`5ab5ac3`).** `docs/plan/qa/tool-window.md` (TW1–TW6), `password.md` (PW1–PW4), `pdf-lock.md`
(PL1–PL4) and `read-qr.md` (QR1–QR3), in `copy-text.md`'s form with a Status column, every row `open`. There is no
`qa/README`; the index (§7) links them. Each expected result uses the app's own words, checked against the code (for
example Read QR shows no caption for a QR code, and "Not a web link" only for a link of another kind).

**F2 — the exit runner (`5138cf0`, `a7ad58c`).** `Scripts/m7-exit.sh` with its rows in `Scripts/m7-exit-rows.sh`
(split to stay small), and `Scripts/tests/test-m7-exit.sh`. The runner was written before its test; the test was then
run with the runner moved aside and failed with "No such file", and passed with it. As planned, plus: V4 prints the
load line of `timing.sh` in its SKIP; V5 also checks the licence texts in the bundle, both tarballs against their pins
(what `source-bundle.sh` copies) and qpdf's code in the worker and not in the app's binary; V13 also refuses an added
binary file, an added PDF and another app's name. `make password-policy` (`Scripts/password-policy.sh`) runs eight
policy suites by name and the grep's own test, and fails when no suite ran (a `--filter` that matches nothing passes):
49 tests in five bundles. `a7ad58c`: the runner's test planted another app's name as a literal, which V13 would have
refused in its own diff; found by this record's leak scan before the exit run reached V13.

**F3 — demos and captures (`9dcf587`, `b9b7af6`).** `make pdf-smoke` (V6), `make lock-demo` (V8), `make qr-demo`
(V9), `make locked-input-demo` (V10) and `make tool-states` (V11), with `Scripts/demo-lib.sh`, `Scripts/pdf-check.swift`
(PDFKit, everything on stdin) and five script tests on stand-ins (`Scripts/tests/demo-stubs.sh`): a locked screen
skips with nothing run or captured, a missing PNG fails, a secret file left behind fails, and no recorded command line
holds a password. In the app (DEBUG only, refused in Release by `check-release-paths.sh`, whose test failed first):
`ProtectDemo` now runs a `steps.json`; `LockedInputDemo`, `QRDemo` (through a DEBUG observer on `CodeWiring`) and
`ToolShots` are new; `PasswordShots` logs its window. The inputs are drawn at test time by `ProtectDemoInputTests` and
`ToolDemoInputTests`, in our own words. Deviations:

- `make pdf-smoke` is built here: V6 named it, but no task of the plan made it (D-M7-57).
- The passwords' file is `<folder>/secret`, not `-ZivletDemoSecrets <file>` (D-M7-53).
- Captures are by window number, after a region capture took another app's window (below, D-M7-54).
- The protect cards are made-up batches in `tool-states`; near the drop in glass only (D-M7-55). The error red is not
  judged as text, because the sheet draws no red text (D-M7-56).
- TDD: each script was drafted before its test; each test was then seen to fail with its script moved aside ("No
  such file") and to pass with it. Two bugs were found by the first real runs, not by a test: the password maker ended
  the script with SIGPIPE under `pipefail`, and a Swift Testing trait that named its own suite would not compile.
- The island card's "Saved" (`b9b7af6`): found in the captures, the test written and seen to fail first.
- Not done: G-M7-22's Flate bomb in `pdf-smoke`. A bomb's stream is decoded to nowhere (D-M7-45), so it never passes
  the memory ceiling and would not stop the worker; G-M7-22 stays open.

**An incident.** The first version of `demo-qr.sh` cropped the screen region the app logged for its results window,
as the M5 and M6 demos do. That region showed another app's window, not Zivlet's. The file was deleted at once and
not kept; every M7 capture since is of one Zivlet window by its number. Why the results window was not on top there
(another Space, or not yet drawn) was not determined (G-M7-30). The M5 and M6 demos still crop regions (G-M7-29,
OS-M7-13); none of their captures from this session's runs was opened.

**Seen in the Debug app, in the working repository** (screen awake, load 3–6): `make pdf-smoke` passed every step
and check (18 samples of the app and one worker, no password in a command line, no child); `make lock-demo` passed;
`make locked-input-demo` passed with CER 0.000 and one sheet; `make qr-demo` passed with three codes; `make
tool-states` wrote 49 captures, and all 45 contrast readings passed (§8).

**F4 — the exit run, resumed.** The session running F4 stopped partway through `Scripts/m6-exit.sh` (§4). This record
was then uncommitted, with its tables still to be written. The next session read it and the first pass's logs, kept
both, and ran what was missing in the same clone (§3, §4).

- A Debug Zivlet that this run had not launched was open the whole time: started from the working repository with no
  arguments, after the first pass had ended. The M5 demos quit every Zivlet (`pkill -x Zivlet`, G-M6-16), so V3 and
  the earlier runners' rows that call them were not run (D-M7-59). That Zivlet was not touched.
- **Defect: `make tool-states` left its apps open.** After V11, 49 Debug apps from the clone were still running, one
  per state. `capture` ran inside `$(...)`, so the app id that `launch_app` recorded was lost with the subshell, and
  every later quit, the final one included, had nothing to quit. The 49 were ended (SIGTERM, matched on the clone's
  own path). The test now uses a stand-in app that runs until it is signalled. With two states it failed first
  ("expected [0], got [2]") and passed after the fix: `capture` runs in the script's shell and returns its frame in
  `FRAME` (`ed6c756`). A watcher beside V11 at `ed6c756` saw at most one app at a time and none afterwards. The first
  pass ran the same code in the working repository, so it most likely left its 49 apps open too. None was running
  when this session began, and how they ended is not known.
- The M6 `demo-text-states.sh` (Z9) has the same `$(capture ...)` form. Reading the code says it leaves its six
  states' apps open; that was not counted. It has no stand-ins to test it with, so it is not changed in M7 (G-M7-33).

---

## 10. Decisions

D-M7-1 to D-M7-52 are in the index (§4), each with the part that explains it. Stream F adds D-M7-53 to D-M7-59 (index
§4). The review follow-up (§15) adds D-M7-60 to D-M7-70: each sheet's answer keeps its own job (60); the Open sheet
for locked inputs (61); no accent in the sheet's choices (62); RSA-MD declared and pending the owner, refused by a
release (63); a hard ceiling beside NFR-9 (64) and beside the cold first drop (65); a crash retry alone in the
worker (66); Read QR results waiting for the open window (67); the tool window's editing keys and growth (68);
reveal per field (69); the PDF engine's free-disk guard and a rewrite's cause (70).

---

## 11. Gaps

Status at the end of M7; the full text of each is in the index (§10) or the part named.

| ID | Status |
|---|---|
| G-M7-1 | Closed: qpdf built in 30 s (load 3.3 → 8.8), the library API through the shim (20d) |
| G-M7-2 | Closed by E11 (`abe050a`) |
| G-M7-3 | **Open.** An ffmpeg cancel ends the process group 1066–1074 ms after the cancel, about 70 ms over NFR-9's 1 s; the budget is unchanged (OS-M7-7). §5 has this run's reading. Since §15, P1-20's 1.5 s is a hard ceiling for it (D-M7-64) |
| G-M7-4 | Open: focus, Secure Input with typing, VoiceOver and full-screen spaces are owner rows TW2–TW6 |
| G-M7-5 | Recorded, best effort: the typed `String`, `WireSecret`'s `Data`, XPC's and qpdf's copies are freed, not zeroed (D-M7-14) |
| G-M7-6 | Open: P2-12 and P2-57 (§13, OS-M7-8) |
| G-M7-7 | Open: the S-PDF-LOCK matrix (QA PL1, OS-M7-5) |
| G-M7-8 | Open: Suggest's system generator never called by automation (QA PW1, OS-M7-4) |
| G-M7-9 | Open: unit tests outside stream R that still assert wall time (20a) |
| G-M7-10 | Open: the cold first drop of a process, 23–94 ms in the test process (OS-M7-12); since §15 it fails past 150 ms (D-M7-65) |
| G-M7-11 | Closed (`6d73e67`) |
| G-M7-12 | Open: READ QR accepts SVG, which ImageIO does not decode |
| G-M7-13 | Partly closed: the disabled reason is on screen in `tool-states` (§8); the bipolar slider and the timecode field have no user yet |
| G-M7-14 | Closed for this run: `aRealClickOnItsContentMakesItKey` ran and passed in the clone's `make test` (screen awake) |
| G-M7-15 | Recorded: no process's environment is visible on this macOS; children are checked at their spawn request, and V6 samples command lines only |
| G-M7-16 | Open: VoiceOver labels checked through the view's own strings (OS-M7-6, OS-M7-10) |
| G-M7-17, -18, -19, -25 | Closed (20d, 20e, 20f); OS-M7-1 still asks the owner to confirm the qpdf build was meant |
| G-M7-20 | Closed for this run: the three frame-driven tests passed in the clone with the screen awake |
| G-M7-21 | Open: Y8 has no guard for a person using the Mac |
| G-M7-22 | **Open:** the watchdog's stop has still not fired in the XPC worker; no Flate bomb was added (§9) |
| G-M7-23 | Open: Copy Text and Read QR say "larger than Zivlet's safety limit" for an oversized PDF |
| G-M7-24 | Open: PDFKit rendering in Copy Text and Read QR has no time budget or memory ceiling |
| G-M7-26 | Open: a ceiling stop reaches the person through the crash rule; not seen with a PDF |
| G-M7-27 | Open: a certificate-locked PDF is called "locked" by Copy Text and Read QR |
| G-M7-28 | Partly closed: a locked PDF in Copy Text through the app (V10) and lock, unlock, change and legacy inputs in the real worker (V6, V8). Still not seen: a locked PDF in Read QR in the app, a non-ASCII password through the app, other readers, typing and VoiceOver |
| G-M7-29 | **New.** The M5 and M6 demos (`demo-text-states`, `demo-box-states`, `demo-notch-states`, `demo-box`, `demo-box-busy`) crop screen regions, which hold whatever window is on top there; an M7 region capture once held another app's window (§9). OS-M7-13 |
| G-M7-30 | **New.** In that run the region the app logged for Read QR's results window did not show the window; whether it was on another Space or not yet drawn was not determined (QA TW6) |
| G-M7-31 | **New.** The PDFKit checker cannot tell R6 or AES-256 (PDFKit does not say); V6 checks opening, refusing, permissions, fields and no encryption, and the R6 write is checked by the engine's verify through qpdf (D-M7-23) and its unit tests |
| G-M7-32 | **New.** V6's watch samples every 0.2 s (18 samples in a 4 s run): a password shown between two samples would not be seen |
| G-M7-33 | **New.** The M6 `demo-text-states.sh` (Z9) captures inside `$(...)`, as `demo-tool-states.sh` did before `ed6c756`, so by reading it leaves each state's app open (six per run; not counted). It has no stand-ins for a test. Next: the same fix with a stand-in test, as `ed6c756` |
| G-M7-34 | **New.** V11 waits a fixed 1.2 s after a window's line. In two of 49 captures that was not enough: one caught the window before it was drawn, one caught it while it was not key. Each was right when run again, so neither counts as a defect. What took key that moment was not found (QA TW5) |
| G-M7-35 | **New (§15).** The licence gate trusts each component's declared SPDX; it does not read the headers of the sources that are linked. A one-time scan of CQPDF's 212 members found only MD5 undeclared |
| G-M7-36 | **New (§15).** Paste, growth, reveal, the Open sheet and the owner password's VoiceOver value are checked by unit tests and captures, not by a person with a keyboard or VoiceOver (QA TW7, TW8, PW5–PW8, QR4, QR5) |
| G-M7-37 | **New (§15).** `make tool-states` reads contrast over a text-free box only; the selected Printing segment's 21:1 is computed from its colours by a unit test and was read once by hand from the three captures (§15.3), not by the script |

---

## 12. Owner steps

| ID | Step | Status |
|---|---|---|
| OS-M7-1 | Confirm the qpdf and libjpeg-turbo build of 2026-10-29 was meant to run | Open |
| OS-M7-2 | Confirm the tool window does not activate Zivlet (D-M7-10) | Open (QA TW5) |
| OS-M7-3 | A mixed Lock drop: lock the plain files and list the locked ones (built so, D-M7-50) | Open for a yes or no |
| OS-M7-4 | Try Suggest once by hand | Open (QA PW1) |
| OS-M7-5 | The S-PDF-LOCK interop matrix | Open (QA PL1) |
| OS-M7-6 | Look review and VoiceOver of the tool window, the sheet, Read QR and the cards; the captures of §8 | Open (QA TW1–TW6) |
| OS-M7-7 | NFR-9: the ffmpeg cancel's 70 ms over 1 s (G-M7-3) | Open |
| OS-M7-8 | Schedule P2-12 and P2-57 | Open |
| OS-M7-9 | The qpdf contribution against 4.5 MB | Not needed: at most 2.31 MB (§7) |
| OS-M7-10 | Run `ResultCardUITests` and `ToolWindowUITests` | Open |
| OS-M7-11 | Merge and push `m7` | Open (owner only) |
| OS-M7-12 | The cold first drop (G-M7-10) | Open |
| OS-M7-13 | Window captures for the M5 and M6 demos, or run them with nothing private on screen (G-M7-29) | New, open |
| OS-M7-14 | With no other Zivlet open, run `Scripts/m7-exit.sh --only V3` and `Scripts/m6-exit.sh --only Z3,Z5,Z6,Z7,Z8,Z9,Z10` (Z10 checks what Z5–Z9 asked for, so they run together), and `Scripts/m5b-exit.sh --only Y8`. Or say that an exit run may quit the Zivlet you have open (D-M7-59). Still open after §15: the same Zivlet was open | New, open |
| OS-M7-15 | Decide qpdf's RSA-MD MD5 notice (D-M7-63): accept it (move RSA-MD from `PENDING` to `ALLOWED` in `Scripts/licence-gate.sh`, with the reason, for example RSA's statement on code derived from RFC 1321, if you rely on it) or have `libqpdf/MD5_native.cc` replaced by a public-domain or Zivlet-written MD5 as a documented patch (one qpdf rebuild). Until then every release refuses the gate | New (§15), open |

---

## 13. P2-12 and P2-57 (reported, not built)

| Row | Status |
|---|---|
| P2-12 PDF → JPG, PNG, TXT, MD | **Not built.** M-sized (page scale, the multi-page folder naming, the text layer, four matrix pairs); not tiny, so outside M7. `EnginePDF`, the worker and the pre-flight it needs now exist. E11 (`abe050a`) stops the wheel offering PDF conversions until it lands, and P2-107's "then converts" waits for it (D-M7-24). OS-M7-8 |
| P2-57 Beta channel | **Not built.** `make-appcast.sh` writes stable items only and Settings › Updates has no opt-in; S-sized, needs the release pipeline and Sparkle's channels, independent of M7. OS-M7-8 |

---

## 14. Leak scan of `m6..m7`

Scanned on the 84 commits `77e181c`..`ed6c756`, plus this record and the plan edits in its commit, before that commit
was made. V13 (`5107be7..a7ad58c`) and Z11, X7 and Y9 (at `ed6c756`) check much of the same by script (§3, §4).

| Check | Result |
|---|---|
| Signed off | all 84, by the one author; no `Co-Authored-By` |
| Personal or scratch paths in added lines | none. The only home-folder paths are made up (`/Users/me/…`, `/Users/x/…` in tests) or are the patterns of the checks that look for such paths. No path into the session's scratch folder or to private notes |
| Names of other apps | none in added lines (V13's check, and this scan of the whole diff) |
| Binary files, PDFs, images, archives added | none (`git diff --numstat`, added names); every test PDF and image is drawn at test time |
| Files at or over 800 lines | none of the 313 changed files; this record is under 400 |
| Shipped sources | V13: no `print(`, no new `NSAlert`, Vision only in EngineVision, qpdf headers only in CZivletPDF, no Keychain item API, no `--password`, no worker entitlements |
| Downloaded files | the two tarballs and their signatures stay in `Vendor/downloads`, which git ignores; none is tracked |

---

## 15. Review of M7 and what it changed (2026-11-08)

A review of `m6..9c48ab0` raised 20 findings (5 HIGH, 15 MEDIUM, counting two pairs that name one defect twice) and
10 LOW ones. Each was checked against the code first; the defects were reproduced by a failing test before the
fix, run against the old code. Where the test needed an API that did not exist yet, the old code was driven through
its own API in a temporary test (deleted after), or the red was a build failure; both are said below. One more
defect of the same kind was found while fixing them (F-21). Commits `3c29e88`..`1bc0829` (13), on `m7` after
`9c48ab0`; nothing was pushed.

### 15.1 Findings

| # | Finding (severity) | Result | Commit, test, decision |
|---|---|---|---|
| F-1 | The PDF watchdog kills the shared worker, so a file on its retry can be blamed for another file's stuck call (MEDIUM) | **Fixed**, as the review's second option: a retry holds the worker alone (D-M7-66). Reproduced first: `anotherFilesCrashBesideARetryDoesNotBlameTheRetriedFile` (a loopback worker; `slow.png` on its retry, `bad.png` crashing beside it) failed on the old code with `slow.png` blamed. The stuck job's id is still not reported: the worker dies at once | `4c8eb3f`; `WorkerIsolationTests` (4) |
| F-2 | NFR-9 under `withKnownIssue` only, so no gate fails a slow ffmpeg teardown (MEDIUM) | **Partly.** A hard ceiling now fails `make timing`: P1-20's bound (1 s grace + 500 ms) for the group's end and the task's return (D-M7-64); seen to fail with the ceiling at 1 ms. NFR-9's 1 s is still missed (1074.3 ms, not judged, load ~6) and stays the owner's (OS-M7-7). The review's point that no gate fails a slow *child* teardown was not right: `SubprocessTiming` judges P1-20's bound strictly | `bcca4b4` |
| F-3 | The cold first drop is judged only as a known issue (MEDIUM) | **Fixed** with a stated ceiling of 150 ms, not the suggested 100 ms: the cold drop has measured 23–94 ms, and 100 ms would leave 6 % over the slowest reading (D-M7-65). Seen to fail at 1 ms; the 50 ms line stays a known issue (OS-M7-12) | `bcca4b4` |
| F-4 | Gates not green at `m7`: X6, Y8, Z3, Z9, Z10, V3 (MEDIUM) | **Skipped, with the reason unchanged.** X6 is G-M5a-1 (not worked on, by the task). Y8, Z3, Z9, V3 and Z10 (which needs Z9) run the M5 demos, which quit every Zivlet; a Debug Zivlet this session did not launch was open the whole time (pid 28412, started 20:32 on 2026-11-07), so D-M7-59 kept them out again. The other M7 rows were run, V4 not judged (§15.2, §15.5); of the earlier runners, only their hygiene rows. OS-M7-14 stays open | — |
| F-5 | qpdf's MD5 code is under RSA-MD, undeclared (HIGH) | **Fixed, the decision left to the owner.** Declared `Apache-2.0 AND MIT AND RSA-MD`; RSA's notice reproduced in `qpdf.txt` from `MD5_native.cc`; the acknowledgements page names the MD5 code as derived from RSA's algorithm. RSA-MD is not on the allow-list: it is *pending*, named on every gate run and refused by the release path (D-M7-63, OS-M7-15). A one-time scan of CQPDF's 212 members found no other undeclared licence header (G-M7-35). qpdf was not rebuilt | `2a64ed4`; `test-licence-gate.sh`, `test-workflows.sh` (seen to fail first) |
| F-6 | The IJG sentence a binary needs is missing (MEDIUM) | **Fixed**: on the acknowledgements page and in THIRD_PARTY_NOTICES; the test checks the exact sentence in `index.html` | `2a64ed4` |
| F-7, F-18 | Per-file sheets lose their own mode and restrictions (HIGH, MEDIUM) | **Fixed**: each answer keeps its own job, submitted in groups of one spec (D-M7-60). Four combinations tested; all failed on the old code | `3c29e88`; `ProtectBatchAnswerTests` |
| F-8, F-17 | A wrong current password in Change can never be corrected (HIGH, HIGH) | **Fixed**: the retry shows a Change sheet (D-M7-60); failed on the old code with modes `[.unlock, .unlock]` | `3c29e88` |
| F-9 | ⌘V and the other editing keys do nothing in the tool window (HIGH) | **Fixed**: the window sends ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z and ⇧⌘Z up the responder chain (D-M7-68). Tested with a responder stand-in; failed on the old code. Pasting into the real `SecureField` with a keyboard was not seen (QA TW7, G-M7-36) | `ddf7338` |
| F-10, F-20 | `try?` in the locked-input attempts shows every error as a wrong password (MEDIUM, MEDIUM) | **Fixed**: only "still locked" asks again; other errors become the file's line; a cancel ends the job; a cancelled task asks nothing more (D-M7-61). Red through a temporary old-API test | `25074e4` |
| F-11 | The batch checkbox of the retry and owner-needed sheets does nothing (MEDIUM) | **Fixed** (D-M7-60); failed on the old code | `3c29e88` |
| F-12 | Reveal is one flag for every field; Suggest shows Change's current password (MEDIUM) | **Fixed**: per-field reveal; Suggest reveals the new pair only (D-M7-69); failed on the old code through the controls' labels | `cde08cf` |
| F-13 | Growing content pushes the window below the screen (MEDIUM) | **Fixed**: the window stays inside the visible frame it was placed in (D-M7-68). The first test passed on the old code because its window was never shown; shown off-screen, it failed | `ddf7338` |
| F-14 | The selected Printing segment is white on the accent at 3.89:1 (MEDIUM) | **Fixed**: Zivlet's own segmented choice, selected segment white with black text (21:1), and white checkboxes (D-M7-62). The red was a build failure (new tokens); the defect was the capture's reading. The script still reads only a text-free box (G-M7-37); the new captures were read by hand: 21.00:1 in all three finishes (§15.3) | `cde08cf` |
| F-15 | Copy Text and Read QR offer "Change password…" for a locked input (MEDIUM) | **Fixed**: the Open sheet (D-M7-61); `demo-locked-input.sh` now expects `["open"]` and refuses `["unlock"]` (its test failed first) | `25074e4` |
| F-16 | VoiceOver reads the owner password's caption twice and never the password (MEDIUM) | **Fixed**: caption as the label, the password as the value, the separate caption hidden. Checked through the view's own strings (red: a build failure); VoiceOver not run (QA PW7) | `cde08cf` |
| F-19 | `.unavailable` is treated as Cancel (MEDIUM) | **Fixed**: the batch outcome says so and the HUD shows "Finish the open window first"; locked inputs stop asking. In today's app it cannot happen: one prompter serves every sheet and makes asks wait their turn, and Read QR's results give way to a sheet | `3c29e88`, `25074e4` |
| F-21 | *Found while fixing F-7:* a Change on a restricted file opened by its user password went through the owner-needed sheet, whose job is Unlock, and was written **decrypted** | **Fixed**: only Unlock answers go to the owner-needed sheet; the Change keeps its failure line and its Retry asks for Change again. Failed on the old code | `1bc0829` |

LOW findings:

| # | Finding | Result |
|---|---|---|
| L-1 | 20f clause status: P2-107 conversions and owner rows | **Partly**: QA PL5 tracks a locked PDF on a conversion, blocked until P2-12; new owner rows TW7, TW8, PW5–PW8, QR4, QR5 (`1c35b83`). P2-12 itself is not built (§13) |
| L-2 | The PDF engine ignores the free-disk limit | **Fixed** (D-M7-70, `6633fae`); failed on the old code. ENOSPC inside the shim still reads as a write failure |
| L-3 | SOURCES.md does not name CQPDF | **Fixed** (`2a64ed4`); the test reads the guide out of the bundle |
| L-4 | Read QR results are lost behind another tool window | **Fixed**: they open when it closes, as the HUD now says (D-M7-67, `25074e4`); failed on the old code |
| L-5 | The window's VoiceOver title is not updated | **Fixed** (`ddf7338`); failed on the old code |
| L-6 | The segmented control is centred, off the leading edge | **Fixed** with F-14: the segments span the row |
| L-7 | "Locked with AES-256 2 of 3 files" | **Fixed**: "Locked 2 of 3 files", and per mode (`0659574`); failed on the old code |
| L-8 | Copy Text matches locked files by name | **Fixed**: by position in the drop (`25074e4`); a two-files-of-one-name test failed on the old code. Read QR was already by position |
| L-9 | `merge`'s doc comment took `body(of:)`'s line | **Fixed** (`25074e4`) |
| L-10 | Every rewrite failure reads as a failed check | **Fixed**: the cause is kept, only damage and failed checks read so (D-M7-70, `6633fae`; red: a build failure, the mapping function being new) |

### 15.2 Gates after the fixes

A fresh clone of the local repository (`m7` at `1c35b83`, then fast-forwarded to `1bc0829`), with `Vendor/out`,
`Vendor/src` and `Vendor/downloads` copied in; nothing was rebuilt (`ensure-native.sh`: CWebP, CZivletSVG and CQPDF
"up to date"; media "up to date"). Everything ran under `nice -n 10`. The Mac was on battery, mostly asleep (its
power log shows maintenance sleeps through the night), and very busy when awake: load 7 to 35. The Debug Zivlet of
D-M7-59 (pid 28412) was open throughout and was not touched.

| Step | Commit | Result | Time, load |
|---|---|---|---|
| V1: `make test lint coverage app release-check licence-gate` | `1c35b83` | **pass.** 2573 tests in 23 bundles, none failed; lint; coverage, all 21 modules ≥ 90 % (below); app; release-check 57.3 MB of 85 (`Contents/MacOS` 16.4, `libav*` 29.8, Sparkle 1.3, Helpers 0.6, the worker 8.5, Resources 0.7); licence gate 15 components, 58 crates, with the line `pending owner decision: qpdf (RSA-MD)` | 383 s, 7.1 → 17 |
| V2: `make script-test` | `1c35b83` | **pass**: 42 script tests and the PDF-writes check | 322 s |
| V4: `make timing` | `1c35b83` | **not judged.** Stopped by this session at 04:49 after 2 h 36 min in its first load wait: the load never fell to 3.0 while the Mac was awake, and the wait's timers stop while it sleeps. The two new ceilings were seen to fail at 1 ms in an unjudged run at load ~6 (cold drop 55.2 ms, cancel 1074.3 ms, both under the real ceilings) | — |
| The bundles changed after `1c35b83`: `ZivletUITests`, `ZivletRuntimeTests` | `1bc0829` | **pass**: 487 and 252 tests (working repository) | 07:52 |
| `make lint` | `1bc0829` | **pass** (working repository) | about 30 min at load 24–35 |
| V1 again | `1bc0829` | **not finished**: stopped by this session after 90 min, still building, at load 27–32 on battery | — |
| V3 | — | **not run** (D-M7-59; OS-M7-14) | — |
| V5–V12 | `1bc0829` | **pass**, every row (§15.5) | 07:37 → 11:37, load 26 → 4 |
| V13, m5a X7, m5b Y9, m6 Z11 (hygiene) | `c647119`, the record's commit | **pass** (§15.5) | — |

Coverage at `1c35b83` (lines covered of lines, %): ZivletCore 889/900 98, ZivletTrigger 696/703 99, ZivletWheelCore
379/380 99, ZivletEngineKit 938/947 99, EngineMedia 1186/1211 97, EngineImage 1240/1292 95, ZivletRuntime 2840/3027
93, ZivletTriggerHost 405/434 93, ZivletWheel 956/986 96, ZivletActions 794/872 91, ZivletSettings 302/312 96,
ZivletUI 6836/7408 92, ZivletNotchCore 503/510 98, ZivletNotch 1067/1113 95, ZivletShelfCore 971/988 98, ZivletBox
3528/3785 93, ZivletIPC 266/266 100, ZivletWorkerCore 469/487 96, EngineVision 559/619 90, EnginePDF 871/885 98,
CZivletPDF 471/512 91.

Not run in the follow-up, beyond V3: the earlier runners' rows that quit every Zivlet (m5a X2–X4, X6; m5b Y3–Y5, Y8;
m6 Z3, Z9, and Z10, which needs Z9), for the reason of D-M7-59, and Z5–Z8 for time. Their last results are in §4.

### 15.3 Screenshots

The screen was awake at 01:58 and 02:01, locked by 02:59 and still at 04:49 and 08:53; nothing tried to wake it. It
was awake again when V11 reached it, so V8–V11 ran, with the Debug app built at 02:06 from `1c35b83` (every fix
but `1bc0829`, which no capture shows). `make tool-states` wrote **55 captures**, and all 51 contrast readings passed,
the lowest 11.17:1 (the fallbacks' surface, 0.012); copies are in `m7-shots/after-review/` in the session's scratch
folder.

**Looked at** by this session, not by a person: Lock with restrictions in glass and Increase Contrast, the Open
sheet after a wrong password, Change asked again, and the batch Unlock. The Printing choice spans the row from its
leading edge, its selected segment black on white; the checkboxes are white; the Open sheet is titled and applied
"Open", with no "Change password…"; the second Change sheet lists the file and asks for Current, New and Confirm,
with "That password didn't work.". **Read from the captures** with a small pixel reader: the selected segment's
text against its fill is **21.00:1** in glass, solid and Increase Contrast. The other 50 captures were not opened.
**Not seen:** pasting, the window growing at the bottom of a screen, a per-field reveal while typing, VoiceOver, and
the island's partial card ("Locked 2 of 3 files"), which `make tool-states` does not capture.

### 15.4 Merge and push (owner only)

`m7` is at this record's commit, 98 commits ahead of `main` (`5107be7`, the owner's M6 sign-off): a fast-forward. It
was not pushed; `main` and `m6` were not touched. `m8` (not touched here) branched from `m7` at `a7ad58c` and holds 4
commits; `m7` has 15 since (`ed6c756`, `9c48ab0` and the 13 of §15), so `m8` needs them merged or rebased before it
lands. Before a release, OS-M7-15 must be decided: the release path refuses the gate until then.

### 15.5 Rows run by name at `1bc0829` and on the record's commit

| Row | Result | What it showed |
|---|---|---|
| V5 | pass, 9116 s | qpdf provenance, the Release worker's links, qpdf in the worker only, both licence texts, both tarballs at their pins, the size against 4.5 MB (the Release app rebuilt at `1bc0829`, under load 26–36) |
| V6 | pass, 4955 s | 24 checks in the real worker: lock, lock with restrictions, unlock, unlock with the owner password, change, a wrong password, legacy RC4 and AES, a form's fields; each locked output opens with its password and refuses another; 18 samples of the app's and the worker's command lines, no password, no child process; every secret file deleted |
| V7 | pass, 22 s | `make password-policy` and `check-secrets.sh` |
| V8 | pass, 17 s | lock, unlock and change through the drop path |
| V9 | pass, 16 s | Read QR through the drop path |
| V10 | pass, 12 s | a locked PDF in Copy Text: one sheet, now `["open"]` |
| V11 | pass, 292 s | 55 captures, 51 contrast readings, the lowest 11.17:1 (§15.3) |
| V12 | pass, 2 s | no request with `preflight=no` from Zivlet or its worker while V6–V11 ran |
| V13 | pass, 2178 s (it waited for V6's SwiftPM lock) | hygiene since `5107be7`, this record's commit included |
| m5a X7, m5b Y9, m6 Z11 | pass, 14 s, 11 s, 17 s | each runner's hygiene since its own base |

V6, V8, V9 and V10 used the Debug app built at 02:06 from `1c35b83`; the one later code change, `1bc0829`, is checked
by its unit test and by V1's bundles at HEAD (§15.2).
