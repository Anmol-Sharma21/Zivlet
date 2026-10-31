# 20 — M7 implementation plan: reliable tests, the tool window, passwords and PDF lock (TDD)

Date: 2026-10-27. Status: in execution (the qpdf build ran on 2026-10-29; OS-M7-1 asks the owner to confirm it). Branch: `m7`, made from `m6`
at `5107be7` (`main` is at `9cc6c69`; the owner may fast-forward it to `m6` meanwhile, which changes nothing here).
Order: [design/17-feature-roadmap](../design/17-feature-roadmap.md) §4.2, wave 2A steps 6–7, with a reliability stream
first. Acceptance: the 05 rows P2-30, P2-51 (the Read QR tool left by D-M6-6), P2-101, P2-102, P2-13 (with its 05 §9.1
changes), P2-105, P2-106 and P2-107, and the M6 load failures (G-M5b-5, G-M6-9 and two more). Design:
[design/17a](../design/17a-pdf.md) §2–§3.2, [design/17b](../design/17b-lock.md) §2–§3 and §9,
[design/13](../design/13-image-pdf-engine.md) §4.4, [design/10](../design/10-tech-strategy.md) §9–§10,
[02-architecture](02-architecture.md) §4 and §7, [01b](01b-prd-additions.md) FR-92, FR-96, FR-97, FR-101, FR-107,
[01-prd](01-prd.md) FR-63, §5.7 and NFR-9, [00-decisions](../design/00-decisions.md) OWN-LK-1, OWN-PDF-1, OWN-PDF-5,
OWN-SIZE-1/2, OWN-PLAN-7. Look: OWN-UI-1, [design/19b](../design/19b-notch-look.md), [design/19c](../design/19c-drop-box-look.md).

This file is the index: verification status, scope, the gap audit, the prototypes, decisions, streams and order,
conventions, exit rows, owner steps, risks and gaps. The tasks are in seven parts, each under 800 lines:

| Part | Stream | Tasks |
|---|---|---|
| [20a](20a-m7-reliability.md) | **R** — tests under load | R0 baseline · R1 `coverage.sh` shows failures · R2 rows make their fixtures · R3 the timing target and load guard · R4 the 50 ms notch test · R5 the SIGINT grace test · R6 the ffmpeg cancel test and NFR-9 · R7 the result card's linger · R8 proof under load |
| [20b](20b-m7-tool-window.md) | **A** — P2-30, Read QR | A1 window state · A2 the panel · A3 bipolar slider, timecode · A4 options per tool · A5 window tools from the wheel · A6 `-UITestFixture` tools mode · A7 `CodeReader` · A8 the worker's code job · A9 results window · A10 READ QR wiring |
| [20c](20c-m7-password-sheet.md) | **B** — P2-101, P2-102 | B1 `JobSecret` · B2 password rules · B3 sheet states · B4 sheet view · B5 Suggest · B6 prompting · B7 policy tests and CI grep |
| [20d](20d-m7-qpdf.md) | **C** — P2-13 | C1 pins and keys · C2 build `CQPDF` once · C3 `verify-native.sh` · C4 the shim and `EnginePDF` · C5 worker only · C6 licences, notices, size |
| [20e](20e-m7-pdf-preflight.md) | **D** — P2-105 | D1 pre-flight · D2 limits for hostile PDFs · D3 verify · D4 the qpdf-first rule · D5 the 50 ms budget |
| [20f](20f-m7-pdf-lock.md) | **E** — P2-106, P2-107 | E1 the slot · E2 the job and names · E3 secrets on the wire · E4 lock · E5 unlock · E6 change · E7 batches · E8 results · E9 slice to jobs · E10 locked inputs in Copy Text and Read QR · E11 conversions per pair |
| [20g](20g-m7-qa-exit.md) | **F** — QA, exit, record | F1 QA rows · F2 `m7-exit.sh` · F3 demos and screenshots · F4 exit run and record |

Naming: "M7" is this branch's slice of wave 2A (steps 6–7 plus reliability), not a 05 milestone; 05 is not changed by
this plan. The record will be `21-m7-record.md` (task F4).

Clean room: unchanged. No code, assets, sounds or UI strings from any other app; prior art is described in our own
words only. Every string quoted in the parts is Zivlet's own or quoted from Zivlet's design docs; new ones are marked
*new*. Every test PDF and code image is made at test time by our own code (CoreGraphics, PDFKit, Core Image, or the
qpdf library through our shim), with text written for Zivlet (D-M7-25); nothing is downloaded.

---

## 0. Verification status of this plan

| Check | Result |
|---|---|
| Baseline tests | The four load-sensitive tests, by name (this session, `m7` = `5107be7`): five runs at load 3.7–9.3, all passed (a first run at load about 12 also passed; its output was cut to the last suite). `cancellingARunningEncodeStopsFFmpegQuickly` took 1.459–1.490 s against its 1.5 s bound every time (20a). `make test`, `lint`, `coverage`, `app` and the release gates were **not** run for this plan (docs only); R0 runs them first |
| Code read | `Package.swift`, `Makefile`, `project.yml`, `.gitignore`; `ZivletCore/Catalog/*`, `Jobs/JobRequest.swift`, `JobError.swift`, `JobIdentity.swift`; `ZivletIPC/*`; `ZivletWorkerCore/WorkerXPCHost.swift`, `WorkerService.swift` (logging); `Worker/main.swift`; `ZivletRuntime/ConversionService.swift`, `JobPipeline.swift`, `JobRecordStore.swift`, `Diagnostics.swift`, `StagingDirectory.swift`; `ZivletWheelCore/SliceBuilder+Convert.swift`, `WheelContent.swift`; `EngineImage/ImageEngine.swift`; `EngineVision/PDFTextSource.swift`, `TextError.swift`; `ZivletEngineKit/SubprocessRunner.swift`, `SubprocessSpawn.swift`, `Engine.swift`, `ExecutionPlan.swift`; `ZivletUI/HUD/ResultHUD.swift`, `TextPreviewWindow.swift`, `UITestFixture.swift`; `ZivletNotch/MonotonicClock.swift`; `App/AppDelegate.swift`, `ToolWiring.swift`; the four tests of Stream R; `Scripts/coverage.sh`, `env.sh`, `m5a-exit.sh`, `m6-exit.sh` (head), `demo-notch.sh`, `demo-box.sh`, `check-log-privacy.sh`, `licence-gate.sh`, `flaky-watch.sh`; `Vendor/versions.lock`, `signatures.lock`, `build-native.sh`, `xcframework.sh`, `fetch.sh`, `verify-sources.sh`; qpdf 12.4.2's public headers, `libqpdf/QPDFJob.cc` (check and show-encryption), `libqpdf/QPDF_encryption.cc` (which password matched), `libqpdf/qpdf-c.cc` (check), `job.yml` (limits) — read as data, nothing of it copied |
| Prototypes | Run on this Mac on 2026-10-27, outside the repository, under the hard limits (files the prototypes made in a scratch folder only; no Desktop, Documents, Downloads, iCloud Drive, Photos, removable volumes, bookmarks or Keychain). (a) the qpdf build: **not run**, refused by the session's permission check (§3.1, OS-M7-1); (b) the PDFKit half run, the qpdf half written but not compiled; (c) the password over XPC and the field in a non-activating panel: run; (d) the window's shape: rendered. Results in §3 |
| Downloads | qpdf 12.4.2 and libjpeg-turbo 3.2.0 tarballs in `Vendor/downloads/<name>-<version>/` (ignored by git), SHA-256 computed and upstream signatures verified (20d) |
| Code in the parts | Swift, C++ and shell in the parts are specification-grade and were **not** compiled. Each RED step names the expected compile error or assertion, not a recorded one |
| Hardware | 14-inch MacBook Pro (Mac14,9, M2 Pro, 6 P + 4 E cores), macOS **27.0** (26A428), Xcode 27.0 (27A266a), Swift 6.4, SDK MacOSX27.0. Load during this session 2.6–12 |

---

## 1. Scope

| In M7 | Row | Stream |
|---|---|---|
| `coverage.sh` prints the failing tests; every exit row makes its own fixtures; real-time budgets judged only in a timing target below a stated load; the four load-sensitive tests made deterministic | G-M5b-5, G-M6-9, M6 re-verify | R |
| The tool window: chrome at the wheel's place, Apply/Cancel, disabled reasons, bipolar slider, editable timecode, options per tool, keyboard, `-UITestFixture` tools mode | P2-30, FR-63 | A |
| Read QR: Vision barcodes on images and PDF pages (200 DPI) in the worker, results window with Copy, Copy All and safe Open | P2-51 (tool) | A |
| The password sheet (Lock, Unlock, Change; Suggest; strength; batch; NFC/NFD retry; VoiceOver) | P2-101, FR-96 | B |
| Password policy: never logged, stored, in settings, diagnostics, records, names, argv or env; bytes wiped; XPC only for its job; CI grep | P2-102, NFR-21 | B |
| qpdf 12.4.2 + libjpeg-turbo 3.2.0 static, native crypto, worker only, through our C++ shim; licences, notices, source bundle, size | P2-13 | C |
| PDF pre-flight, limits for hostile files, verify every output, the qpdf-first rule | P2-105, FR-107 | D |
| PDF Lock / Unlock / Change password (R6 AES-256) on one LOCK · UNLOCK slot; locked PDFs in Copy Text and Read QR; conversions offered per pair | P2-106, P2-107, FR-97, FR-101 | E |
| QA rows, `Scripts/m7-exit.sh`, screenshots of every new state, the record | — | F |

Not in M7: P2-12 (PDF → jpg/png/txt/md) and P2-57 (beta channel) — status in §2.10; P2-108…P2-114 (Office, ZIP, lock
any file, the label refinement); G-M5a-1 (idle CPU); the owner's hardware QA rows; History (P2-145, G-M6-3).

---

## 2. Gap audit (what exists on `m7` at `5107be7`, verified by reading code and running tests)

### 2.1 Stream R

| Item | Exists today | Missing | Task |
|---|---|---|---|
| `coverage.sh` hides a failing run | `swift test --enable-code-coverage >/dev/null` under `set -euo pipefail` (env.sh): a failing test exits 1 with **no output at all** | keep the log, print failing tests and issues, no coverage table from a failed run | R1 |
| X3 needs X2's fixtures | `demo-notch.sh` refuses without `build/fixtures/small/srgb.heic`; only X2's `demo_file` runs `make fixtures`. `demo-box.sh` makes its own; `demo-copy-text.sh` renders its own | the notch demo makes its fixture; a script test runs X3 alone | R2 |
| `aDropShowsTheIslandWithin50ms` | wall clock around `prepare` + `show` in `make test`; failed in every M5a/M5b/M6 exit run under load, passed by name | structural + CPU-time checks in the unit test; 50 ms judged in the timing target and from the in-app signpost | R3, R4 |
| `aChildIgnoringSIGINTIsKilledAfterTheGrace` | a fixed 300 ms sleep before cancel; under load SIGINT can arrive before `trap ''` runs (0.41 s seen, G-M6-9) | readiness line, short injected grace, lower bound only | R5 |
| `cancellingARunningEncodeStopsFFmpegQuickly` | 1.5 s wall bound; measured 1.459–1.490 s here at every load; NFR-9 says the group is gone ≤ 1 s | behaviour-only test; timing split measured against NFR-9 (G-M7-3) | R6 |
| `anUndoThatChangedNothingKeepsTheButtons` | `ResultHUD` on `SystemClock`; the 4 s linger can expire before the check | `ManualClock` (exists in `NotchTestSupport`) | R7 |

### 2.2 P2-30 tool window (and FR-63)

| Clause | Exists | Missing | Task |
|---|---|---|---|
| Shared chrome opens at the wheel location | nothing: `.editor` tools fall through `AppDelegate.handle` to a DEBUG note. `TextPreviewWindow` is a non-activating `NSPanel` pattern with glass/solid switching to reuse | `ToolWindow`, placement | A1, A2 |
| Apply / Cancel; disabled-state reasons | — | buttons, `DisabledReason` | A1, A2 |
| Bipolar sliders fill from centre; editable timecodes | — | `BipolarValue`, `Timecode` and views | A3 |
| Options remembered per tool; keyboard operable; Apply admits a job like a drop | — | `ToolOptionsStore`, Esc/Return, coordinator | A2, A4, A5 |
| XCUITest `-UITestFixture <dir>` | the flag exists for the result card only (`UITestFixture.swift`, `UITests/ResultCardUITests.swift`, owner-run) | a tools mode and a tool-window UI test | A6 |

### 2.3 P2-51 Read QR (applicable: D-M7-2)

| Clause | Exists | Missing | Task |
|---|---|---|---|
| Vision barcode detection, all symbologies | `ToolID.qrScan`, the READ QR slice (`.instant`, accepts images, GIF, PDF); `EngineVision` base, `PageRenderer`, Vision only in the worker | a `DetectBarcodesRequest` reader; a worker request | A7, A8 |
| PDF pages at 200 DPI | `PageRenderer` (caps 8192 px / 16 MP) | the 200 DPI scale for codes | A7 |
| Results window, Copy / Copy All, Open only for http(s), full URL, never auto-opened | — (a drop shows the DEBUG note) | results variant of the tool window, `CodeLink` | A9, A10 |

### 2.4 P2-101 password sheet

| Clause | Exists | Missing | Task |
|---|---|---|---|
| `SecureField` ×2 + eye, strength hint | no password UI anywhere | sheet model and view | B2–B4 |
| Suggest via `SecCreateSharedWebCredentialPassword` + Copy (`.currentHostOnly`, concealed/transient) | — (the SDK has it, macOS 11+) | suggester behind a protocol | B4, B5 |
| Unlock shakes on wrong, no attempt limit; NFC → NFD retry | — | `failure` state, `variants` | B2, B3, E5 |
| Batch "same password for all n", failures re-listed | — | toggle, retry sheet | B3, B6, E7 |
| Per-family notes (non-ASCII PDF warning); VoiceOver "Wrong password"; Return = Lock; footer; Change mode | — | notes, announcements, modes | B3, B4 |

### 2.5 P2-102 password policy

| Clause | Exists | Missing | Task |
|---|---|---|---|
| Not in os_log, History, crash fields, `UserDefaults`, argv/env | log privacy script for paths and recognised text (`check-log-privacy.sh`); no password exists to leak yet | `LeakProbe` tests over a real lock/unlock run; grep for `password` in log lines | B7 |
| Held as bytes, zeroed after use (best effort) | — | `JobSecret` (prototype §3.2: two copies remain that Swift and XPC cannot zero) | B1 |
| Plaintext staging 0700, removed on cancel and at next launch | `StagingDirectory` makes `.zivlet-<job>` 0700 (G-16); `OrphanReaper` cleans at launch | pinned for an unlock job | B7 |
| CI grep fails on `--password ` argv | — | `check-secrets.sh` (also Keychain item APIs and logged secrets) | B7 |
| Worker gets it over XPC only for its job; never in settings or diagnostics | `Envelope`/`WorkerRequest` carry no secret today | `secrets:` on the job's own requests, validator, a secret type that is not `Codable` except through the wire wrapper | B1, E3 |

### 2.6 P2-13 qpdf

| Clause | Exists | Missing | Task |
|---|---|---|---|
| Pinned version and SHA-256 (+ signature) | tarballs downloaded and verified this session (untracked) | lock entries, keys, provenance | C1 |
| Static, arm64, minos 26.0, native crypto, no OpenSSL/GnuTLS, `-ffile-prefix-map` | nothing built (§3.1) | the build, its cache, the checks | C2, C3 |
| Used inside the worker through the library API, never a command line with a password | worker hosts `ImageEngine` and text only | `CZivletPDF` shim, `EnginePDF`, worker-only linking | C4, C5 |
| Smoke: rewrite a PDF; decrypt RC4 and AES-256 fixtures; `otool -L` no libcrypto | — | smoke tests on generated files (RC4-40 and AES-128 from CoreGraphics, AES-256 from the shim) | C3, C4 |
| Licences, notices, source bundle, size ≤ 4.5 MB, release-check, licence-gate | 13 components in `licenses.json`; gates exist | two entries, `IJG` on the allow-list, texts, size row | C6 |

### 2.7 P2-105 pre-flight and verify

| Clause | Exists | Missing | Task |
|---|---|---|---|
| Encryption, AcroForm, signatures, StructTreeRoot, EmbeddedFiles, JavaScript, pages; ≤ 50 ms / 100 pages | no `EnginePDF`; Copy Text reads page counts with PDFKit (500-page cap) | `PDFPreflight` from the shim; the timing row | D1, D5 |
| Page and size limits for hostile PDFs (brief) | `PDFTextSource.pageLimit` 500, `PageRenderer` pixel caps | size, page and qpdf parser limits, watchdog | D2 |
| Check every output + re-open; PDFKit writes rewritten through qpdf | — | `PDFVerify`, `PDFRewrite` (image → PDF in the worker), a lint | D3, D4 |

### 2.8 P2-106 lock / unlock / change

| Clause | Exists | Missing | Task |
|---|---|---|---|
| A wheel tool per the catalog (one slot, caps, P2-114 later) | PDF lists have 6 tools each, no lock | `ToolID.protect`, 7 per list | E1 |
| R6 AESv3, password never in argv; RC4/AES-128 never written; verify `/Encrypt` R6 | — | lock path, verify | E4, D3 |
| Restrictions with a random 24-character owner password shown once | — | generator, sheet section | E4, B4 |
| Unlock rule (owner matched, or all permissions, or user = owner); restrictions-only needs owner; Change needs owner when restricted | — | unlock and change paths | E5, E6 |
| `X Locked.pdf` / `X Unlocked.pdf`; non-ASCII warning + "opens on Mac" result; forms stay live | `OutputNamer` (suffix rules) | names, notes, form checks | E2, E4, E8 |
| S-PDF-LOCK matrix recorded (P2-192) | — | owner row PL1 | F1 |

### 2.9 P2-107 encrypted inputs

| Clause | Exists | Missing | Task |
|---|---|---|---|
| One prompt per encrypted input per job, password for that job only | Copy Text refuses a locked PDF with `TextError.pdfLocked` | prompt and resubmit | E10 |
| Outputs keep protection except Unlock; never owner = user | no PDF → PDF tool exists except E's | Change keeps or upgrades (E6); later tools reuse preserve mode | E6 |
| Permission bits (OWN-PDF-5); public-key → `unsupportedEncryption` | Copy Text refuses copy-protected PDFs (`.copyingNotAllowed`) | owner-password override, pre-flight kind | E10, D1 |
| A locked PDF dropped on a conversion asks, then converts (brief) | **the convert wheel offers PDF → JPG and PNG, but no engine handles a PDF source, so the drop fails with `pairNotSupported`** (read from `ConversionService.unavailableTargets`, `ImageEngine.handles`, `JobPipeline.selectEngine`; not run in the app) | conversions need P2-12; E11 hides them meanwhile (G-M7-2) | E11 |

### 2.10 P2-12 and P2-57 (report only)

| Row | Status | Note |
|---|---|---|
| P2-12 PDF → jpg/png/txt/md | **not built.** No engine handles a PDF source; the catalog lists the pairs and the wheel shows JPG/PNG for a PDF (G-M7-2) | M-sized (QZR scale formula, multi-page folder naming D-5, text layer, 4 matrix pairs). Not tiny, so not built here; E11 hides the broken slices. Natural next step after M7, since EnginePDF and the worker's page renderer exist then (OS-M7-8) |
| P2-57 Beta channel | **not built.** `make-appcast.sh` writes stable items only ("Stable is Sparkle's default channel"); no Settings › Updates opt-in | S-sized; needs the release pipeline and Sparkle's channel API; independent of M7's streams (OS-M7-8) |

---

## 3. Prototypes (outside the repository, 2026-10-27)

### 3.1 (a) qpdf for arm64, minos 26, native crypto — not run

- The two tarballs were downloaded into `Vendor/downloads/`, their SHA-256 computed, and both upstream OpenPGP
  signatures verified in a throwaway keyring (20d's table). They were extracted into the scratch folder.
- A build script was written (libjpeg-turbo static, then `libqpdf_static` with `REQUIRE_CRYPTO_NATIVE=ON`,
  `USE_IMPLICIT_CRYPTO=OFF`, `-arch arm64 -mmacosx-version-min=26.0`, `-ffile-prefix-map`, Homebrew paths ignored).
  **Running it was refused by the session's permission check** (building downloaded code). It was not retried or
  worked around. Build time and library size are therefore **not measured** (G-M7-1, OS-M7-1). 10 §9's estimate stays
  the plan's figure: 4.5 MB expected, 6 MB worst.
- A C++ harness for (b) was written against the 12.4.2 headers (R6 encrypt with user + owner passwords read from
  stdin, inspect R/V/methods and which password matched, a wrong password refused, decrypt, change password, check);
  it was **not compiled**. The planned `ps -E -ww -o command=` check during its run was therefore not done.
- Read from the sources instead (data only): `--check` calls `showEncryption`, which prints the user password when the
  owner password matched; the job JSON can carry a recovered user password; the C API lacks `ownerPasswordMatched`;
  for R6 both flags are set when user = owner (`QPDF_encryption.cc`); qpdf 12.x has global parser limits. These drive
  D-M7-16 and D-M7-18.

### 3.2 (b, PDFKit half) and (c1) — run

PDFKit and CoreGraphics on our own two-page PDFs (macOS 27.0 SDK, deployment 26.0):

| Fact | Result | Used by |
|---|---|---|
| CoreGraphics key length 128 | writes **AES-128** (`/V 4 /R 4`, `/CFM /AESV2`), not RC4 | fixtures (D-M7-25) |
| CoreGraphics key length 40 | writes **RC4-40** (`/V 2 /R 3`) | the RC4 smoke fixture (05 §9.1's "RC4-128 PDFKit-made" cannot be made here; RC4-128 comes from the shim's test helper if needed) |
| CoreGraphics with a Devanagari password | **refuses**: the context is nil | non-ASCII fixtures come from the shim |
| PDFKit on user ≠ owner | locked; wrong → `unlock` false; user → `permissionsStatus` 1 (user), `allowsCopying` true for that file; owner → 2 (owner) | D3 verify can tell which password opened it |
| PDFKit on a restrictions-only file | opens unlocked with status 1; `allowsCopying` false; owner password → status 2, copying allowed | E5, E10 (OWN-PDF-5) |

The password over XPC (c1): a random password made into a `String`, copied into an own allocation, sent inside a
Codable request over a real anonymous `XPCListener`/`XPCSession` in one process, wiped by the receiver and freed
(wiped) by the sender. Copies of its bytes found by scanning the process's own readable and writable memory: 1 (the
`String`) → 2 (+ own buffer) → 3 (after the round trip) → **2 after both own buffers were wiped**: the `String` and
one buffer inside XPC's message. Encoding straight from the own buffer without a `Data` copy gave the same count, so
the copy is XPC's. Same result in 4 runs. `ps -E -ww` showed the password in neither argv nor environment. In the real
app the worker holds the equivalent on its side, plus qpdf's internal copies. Conclusion: P2-102's "zeroed after use"
is met for Zivlet's buffers only; the record must say "best effort: the typed string and the XPC buffer are freed, not
zeroed" (D-M7-14).

### 3.3 (c2) The field in a non-activating panel — run

A titled `NSPanel` with `.nonactivatingPanel` and `.fullSizeContentView`, `canBecomeKey == true`, placed far off screen, hosting
a SwiftUI `SecureField` focused through `@FocusState`; an accessory-policy process; then a sheet of that panel with
another field. Measured 0.4 s after each was shown:

| | Panel key | Zivlet frontmost | First responder | Secure Event Input |
|---|---|---|---|---|
| Inline field | yes | **no** (the app the owner was using stayed frontmost) | the secure field's editor | **on** |
| Sheet of the panel | yes | no | the secure field's editor | on |
| After closing | — | — | — | off |

`NSApp.isActive` read `true` while another app stayed frontmost. No prompt or alert appeared. Not measured: typing
(no synthetic keys were sent), VoiceOver, a real wheel drop, full-screen spaces (OS-M7-2, QA TW2–TW6). This supports
D-M7-10 (no activation) and D-M7-15 (the password is the window's content).

### 3.4 (d) The window's shape — rendered

Five states (Lock, Unlock, wrong password, Change with a disabled reason, Read QR results) rendered off screen with
`ImageRenderer` on the solid surface (Liquid Glass does not render there), light and dark: header (symbol, name, file
line), fields with an eye button, one caption line, the footer with Cancel and the named Apply. 340 pt wide; 166 pt
(Unlock) to 269 pt (Lock) tall. The light rendering showed why the window forces the dark scheme: the system red error
line on a light surface is about 3.5:1, under the 4.5:1 rule; `#FF453A` on `#1C1C1C` is 5.0:1. Pictures are in the
scratch folder only; F3 takes the real screenshots.

---

## 4. Decisions

| ID | Decision | Where |
|---|---|---|
| D-M7-1 | `m7` from `m6` at `5107be7`; nothing on `main` or `m6`; never pushed; history never rewritten | — |
| D-M7-2 | Read QR is in M7 (it waited only for the tool window and EngineVision) | 20b |
| D-M7-3 | Unit tests never judge wall time; budgets are judged in `ZivletTimingTests` by `make timing` below a 1-minute load of 3.0 (half the P-cores; may be lowered, never raised past the P-core count), after waiting up to 10 min; otherwise "not judged", exit 3, reported as skip | 20a |
| D-M7-4 | The 50 ms notch test checks the pre-warmed host, the frame, main-thread CPU < 50 ms and the signpost; the wall budget is judged in the timing target and from the in-app `drop→island` signpost | 20a |
| D-M7-5 | Subprocess tests wait for the child's `ready` line, use a 300 ms grace, check the lower bound and the group's end; the upper bound is a timing test | 20a |
| D-M7-6 | The ffmpeg cancel test checks behaviour; the timing target splits the wall time and judges it against NFR-9 (1 s), which M7 does not change | 20a |
| D-M7-7 | HUD tests run on `ManualClock` unless they test real sleeping | 20a |
| D-M7-8 | `coverage.sh` keeps the log, prints failing tests and issues, and reports no coverage from a failed run | 20a |
| D-M7-9 | Every exit row and demo makes its own fixtures | 20a |
| D-M7-10 | The tool window: borderless non-activating `NSPanel`, key without activating Zivlet, the Drop Box's finish and fallbacks, centred on the wheel and clamped; a deviation from PRD §5.7's "app activated" (OS-M7-2) | 20b |
| D-M7-11 | Bipolar slider and timecode built now (P2-30 names them); first users in 2B | 20b |
| D-M7-12 | `-UITestFixture <dir> -UITestMode tools -UITestTool <toolID>` runs the named tool on fixture files (no wheel keyboard mode exists; changed in execution); the XCUITest stays owner-run | 20b |
| D-M7-13 | Read QR stays instant; results in the window's results variant; Open only for http(s) with a host, shown in full, never automatic | 20b |
| D-M7-14 | Passwords are `JobSecret`s: own buffer, wiped, redacted, not `Codable` (only `ZivletIPC`'s `WireSecret` puts them on the worker wire), carried only by their job's requests, held by the batch for the job's life (incl. one retry), then wiped; the `String` and XPC's buffer remain best effort | 20c |
| D-M7-15 | Password entry is the tool window's content (no window to attach a sheet to); during a batch it opens at the HUD's or island's place | 20b |
| D-M7-16 | qpdf static in `CQPDF.xcframework`, worker only, through our C++ shim `CZivletPDF` (C header; Swift without C++ interop); no in-process PDF fallback; never `--check`/`--show-encryption`/`--json` with a password; no qpdf child process | 20d |
| D-M7-17 | qpdf 12.4.2 and libjpeg-turbo 3.2.0 (latest stable; 10 §10's 3.1.x moves to 3.2.0), pinned by hash and signature, built once, cached in `Vendor/out` | 20d |
| D-M7-18 | Pre-flight from the shim's inspect; limits 512 MB, 10,000 pages (structural) / 500 (rendering), qpdf parser limits, > 100 warnings = damaged for writes, PDF watchdog 30 s + 1 s per 10 MB | 20e |
| D-M7-19 | One `ToolID.protect` slot labelled `LOCK · UNLOCK`; the mode comes from the worker's pre-flight after the drop; mixed drops lock the plain files and list the locked ones (OS-M7-3) | 20f |
| D-M7-20 | Lock writes only R6 AES-256; owner = user without restrictions; with restrictions a random 24-character owner password made in the app, shown once, never stored | 20f |
| D-M7-21 | Unlock decrypts only when the owner password matched or every permission is granted; else asks for the owner password; no attempt limit; silent NFC/NFD retry | 20f |
| D-M7-22 | Change keeps restrictions and the owner password when it was typed; upgrades legacy inputs to R6 | 20f |
| D-M7-23 | Every PDF output: the shim's check and re-open with expectations, plus a PDFKit re-open in the worker; a non-ASCII password PDFKit can't use is a note, not a failure | 20e |
| D-M7-24 | P2-107 in M7 = Copy Text and Read QR on locked PDFs, plus Lock/Change; conversions from PDF wait for P2-12; E11 hides them meanwhile | 20f |
| D-M7-25 | Test PDFs and code images are made at test time by our own code; nothing downloaded | 20f |
| D-M7-26 | `Scripts/m7-exit.sh` follows `m6-exit.sh`, rows V1–V13, skip ≠ pass | 20g |
| D-M7-27 | Suggest calls `SecCreateSharedWebCredentialPassword` behind a protocol; automation uses a fake | 20c |
| D-M7-28 | The strength hint is local, three words | 20c |
| D-M7-29 | Media and CWebP keys hash only their own pins; the media build's date comes from its own pins; a COMMON-script change that cannot alter an output is followed by one checked re-stamp, recorded with old and new keys (added in execution) | 20d |
| D-M7-30 | libjpeg-turbo in its own prefix; the qpdf build in `Vendor/build-qpdf.sh` (added in execution) | 20d |
| D-M7-31 | qpdf's manifest licence is `Apache-2.0 AND MIT` (added in execution) | 20d |
| D-M7-32 | Every shim call holds one lock, because qpdf's limits and default logger are process-wide; a limit qpdf counts as hit during a call makes the call fail with `.limit`; outputs are created with `O_EXCL` and removed when a write fails (added in execution) | 20d |
| D-M7-33 | The "prints nothing" test runs the shim in `zivlet-pdf-probe`, a process of its own, because other tests in the test process print their own progress (added in execution) | 20d |
| D-M7-34 | A plan's `PDFStage` (source, keep or remove encryption, page count) carries no password; the worker protocol is version 5; `PDFEngine` handles no conversion pair until P2-12 or stream E's protect job (added in execution) | 20d |
| D-M7-35 | `check-bundle.sh` tells qpdf's presence by a message string of its reader, not by symbols, so a stripped Release worker is still checked; `coverage.sh` leaves `Vendor/` headers out and gates `CZivletPDF` at 80 % (added in execution) | 20d |
| D-M7-36 | Pre-flight answers for a file it cannot open: a locked file with no password (or an empty one) and a file whose handler cannot be read give a `PDFPreflight` that is "shut" (`isShut`), with the encryption, permissions and version known and the rest 0 or false. A wrong password still throws. E9 picks Lock or Unlock from this (added in execution) | 20e |
| D-M7-37 | Structure and hostile test PDFs are typed through `PDFFixtures.raw`, not a test-only `ZIVLET_PDF_TESTING` C++ file: SwiftPM builds a target once, so a test target's define never reaches `CZivletPDF` (added in execution) | 20e |
| D-M7-38 | Widgets on pages count as fields when the catalog has no `/AcroForm`: PDFKit writes forms that way on this SDK, and viewers show them as live. `hasAcroForm` still says what the catalog says (added in execution) | 20e |
| D-M7-39 | 512 MB is 512,000,000 bytes, as Finder counts, so the refusal's words match what a person sees (added in execution) | 20e |
| D-M7-40 | `PDFWatchdog` is the per-job watchdog 10 §8.3 describes, which did not exist: a qpdf step past its budget stops the worker with SIGKILL, and the app's crash rule retries once and then blames the file. Steps take turns and a budget starts when the turn comes, because qpdf runs one call at a time (D-M7-32). It lives in `EnginePDF`, as the worker does not link `ZivletRuntime` (added in execution) | 20e |
| D-M7-41 | The qpdf-first rewrite is the last step of `execute`, in a wrapper engine (`PDFRewritingEngine`), not in `verify`: verify then judges the published bytes, and the app gets the final size. `ZivletWorkerCore` is in the app's product and must not link qpdf, so `WorkerService` has no hook (added in execution) | 20e |
| D-M7-42 | `JobSecret`'s lock is recursive: one secret may be both user and owner (D-M7-20), and a caller lends both together (added in execution) | 20e |
| D-M7-43 | A limit outranks what qpdf did next: the shim reports `ZV_PDF_LIMIT` when qpdf counted a limit error, whether the call then succeeded or ended in damage (added in execution) | 20e |

---

## 5. Streams and order

| Order | Task | Depends on | Size |
|---|---|---|---|
| 1 | R0 baseline | — | S |
| 2 | R1, R2, R3 → R4, R5, R6, R7 → R8 | R0 | S + S + M + M + S + M + S + S |
| 3 | A1 → A2 → A3, A4 → A5 → A6 | R8 | S + M + S + S + M + S |
| 4 | B1 → B2 → B3 → B4 → B5 → B6 (B7's grep part here) | A2 | S + S + M + M + S + S |
| 5 | C1 → (OS-M7-1) → C2 → C3 → C4 → C5 → C6 (parallel with 3–4) | R0 | S + M + S + M + S + S |
| 6 | D1 → D2 → D3 → D4 → D5 | C4 | M + M + M + S + S |
| 7 | A7 → A8 → A9 → A10 | A5 | M + M + M + S |
| 8 | E1 → E2 → E3 → E4 → E5 → E6 → E7 → E8 → E9 | B6, D3 | S + S + M + M + M + S + M + S + M |
| 9 | E10, E11; B7's leak tests | E9, A10 | M + S + M |
| 10 | F1 → F2 → F3 → F4 | all | S + M + M + M |

Estimate (one engineer, ESTIMATE): R 4–5 days, A 7–9, B 5–6, C 4–6 (the build time is unknown), D 4–5, E 8–10,
F 3–4.

---

## 6. Conventions

| Item | Rule |
|---|---|
| Environment | `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before every `swift`, `xcodebuild`, `make`. Prefix heavy commands with `nice -n 10`; long ones run in the background with long timeouts. Never a clean `make vendor` rebuild of existing components; CQPDF is built once (C2) and cached |
| TDD | Each task: write the failing test → run it and **see** the stated failure → implement the minimum → green → refactor → commit. The record says where a test was not seen to fail first |
| Commands per task | RED/GREEN: `cd Packages/ZivletKit && nice -n 10 swift test --filter <Suite>`; then `nice -n 10 make test lint`; `nice -n 10 make coverage` when a gated module changed; `nice -n 10 make app` after A2, A5, A10, B4, C5, E9, E10; `nice -n 10 make release-check` after C5, C6; `make timing` after R3–R6 and D5 |
| Gates (M7 exit) | `make test`, `make lint` (with `check-secrets.sh` and `check-pdf-writes.sh`), `make coverage` (80 % per module; **20 modules** with `EnginePDF`, plus the shim's lines), `make app`, `make release-check`, `make licence-gate`, `make script-test` (needs the media stage: run `make release-check` first in a fresh clone; `licence-gate` in a clone needs `Vendor/src` and `Vendor/downloads` copied in), `make timing`, `Scripts/m5a-exit.sh`, `Scripts/m5b-exit.sh`, `Scripts/m6-exit.sh`, `Scripts/m7-exit.sh` |
| Commits | Conventional, `git commit -s`, **no** `Co-Authored-By`; scopes `scripts`, `timing`, `notch`, `enginekit`, `media`, `ui`, `tools`, `settings`, `core`, `ipc`, `worker`, `runtime`, `vision`, `pdf`, `catalog`, `wheel`, `app`, `vendor`, `licences`, `qa`, `docs`. Only on `m7` |
| Code rules | Immutable values (edits return new values), files < 800 lines (aim 200–400), functions < 50 lines, nesting ≤ 4, no `print` (dev tools write through `FileHandle`), typed errors with Zivlet's own copy, validation at boundaries: worker requests (paths, sizes, secrets), drops, PDF limits and permissions, settings, the secrets file of demos |
| Tests | Swift Testing. File-system tests use `TestSupport.TempDir`; nothing outside temporary folders. Panels in shell tests stay off screen (x −5000). No wall-clock assertion outside `ZivletTimingTests` (D-M7-3). Every password in a test is random per run |
| Passwords | Never in argv or env (tests, demos and scripts included), never logged, never written to disk except a demo's 0600 secrets file in its own temporary folder, deleted after reading. No Keychain item API anywhere |
| Launching the app | Quit any Zivlet you launch with `osascript -e 'quit app "Zivlet"'`. Never trigger a modal alert or an open panel in the running app during automation |
| Screenshots | Only with the screen awake: check `ioreg -n Root -d1 -a \| grep -i CGSSessionScreenIsLocked` first; if locked, skip and say so. Rerun a capture that caught a blank surface once before calling it a defect |
| Hard limits | Never signal, stop or restart a system process or daemon; never `tccutil`; never read or write the Keychain; demos read only files they created in temporary folders; no bookmarks. If any system prompt appears, leave it, stop that line of work and report it |
| Downloads | Only into `Vendor/downloads/<name>-<version>/`, pinned by SHA-256 and signature; treated as untrusted data (no interpreter run from inside them) |
| Deleting | Only what the task created, with literal absolute paths. Never user data |
| Public repo | No personal paths, scratch paths or private research notes in tracked files or commit messages; prior art in our own words only; records say what was not measured, not seen or deferred |

---

## 7. Exit criteria (run by `Scripts/m7-exit.sh`, task F2)

| Row | Check | Command |
|---|---|---|
| V1 | Gates green; coverage ≥ 80 % for every gated module, with measured lines for `EnginePDF` and the shim | `make test lint coverage app release-check licence-gate` |
| V2 | Script tests | `make script-test` |
| V3 | Earlier rows still pass | `Scripts/m5a-exit.sh --only X2,X3,X4,X5`, `Scripts/m5b-exit.sh --only Y4,Y5,Y7`, `Scripts/m6-exit.sh --only Z4,Z5,Z7,Z8` |
| V4 | Real-time budgets judged below the load limit (50 ms drop → island, subprocess grace, ffmpeg cancel split vs NFR-9, pre-flight 50 ms / 100 pages), each with its load; "not judged" = skip | `make timing` |
| V5 | qpdf provenance and build: pins and signatures verified; CQPDF arm64 only, minos 26.0, no OpenSSL/GnuTLS symbols, native crypto present, no build paths; the worker's `otool -L` has no crypto library; the app binary has no qpdf symbols; licence texts in the bundle; the source bundle lists both tarballs; the qpdf + libjpeg-turbo contribution printed against 4.5 MB | `Vendor/verify-sources.sh`, `Vendor/verify-native.sh CQPDF`, `make release-check` |
| V6 | PDF smoke in the real worker: lock (with and without restrictions), unlock, change, a wrong password, RC4-40 and AES-128 legacy inputs, a form PDF; each output opens in PDFKit with the right password and refuses the wrong one; unlock output not encrypted; fields kept; no child process spawned; `ps -E -ww` of the app and worker during the run never shows the password | `make pdf-smoke` |
| V7 | Password policy suite and the CI grep | `make password-policy` (B7's tests by name) and `Scripts/check-secrets.sh` |
| V8 | Lock, unlock and change through the drop path of the Debug app | `make lock-demo` |
| V9 | Read QR through the drop path: payloads equal, Open only for the web link | `make qr-demo` |
| V10 | A locked PDF in Copy Text: one prompt, then the text within 1 % CER | `make locked-input-demo` |
| V11 | Every new state on screen (tool window, password sheet states incl. the wrong password, restrictions, Read QR results, lock/unlock cards near the drop and at the notch), glass and both fallbacks, contrast ≥ 4.5:1 | `make tool-states` |
| V12 | No `tccd` request with `preflight=no` for Zivlet or its worker while V6–V11 ran (D-M5a-5) | log scan in `m7-exit.sh` |
| V13 | Hygiene since `5107be7`: signed off, no `Co-Authored-By`, no file ≥ 800 lines, no personal or scratch path, no `print(` in `Sources/`, no new `NSAlert`, `import Vision` only in `EngineVision`, qpdf headers only in `CZivletPDF`, no Keychain item API, no `--password` argv, the worker's entitlements empty, the cap lint's counts printed | `m7-exit.sh` |

Owner rows (not automated) are in `docs/plan/qa/tool-window.md`, `password.md`, `pdf-lock.md` and `read-qr.md` (F1).

---

## 8. Owner steps and open points

| ID | Step | Why / blocks |
|---|---|---|
| OS-M7-1 | **Allow the qpdf and libjpeg-turbo build** from the verified tarballs (this session's permission check refused running their build), or run it once yourself: after C1, `nice -n 10 Vendor/build-native.sh qpdf` in a terminal. Then the prototype harness (§3.1) can be compiled and run, with `ps` watched. **Still open after stream C's execution** (refused again, G-M7-18): C1, the script (C2), C3 and the licences (C6) are committed; run the command above, then `bash Vendor/tests/test-build-qpdf.sh` | **Built; the owner's confirmation is still asked.** The build ran on 2026-10-29 and stream C finished (20d execution notes), so D and E can go on. No record says who started that build or that the owner allowed it (G-M7-18): please confirm it was meant to run. Nothing was rebuilt after it |
| OS-M7-2 | Confirm that the tool window does **not** activate Zivlet (D-M7-10), unlike PRD §5.7's "app activated" | The prototype shows key focus and Secure Input without activation |
| OS-M7-3 | A mixed drop of locked and unlocked PDFs on LOCK · UNLOCK: lock the plain ones and list the locked ones (planned), or something else | D-M7-19 |
| OS-M7-4 | Try **Suggest** once by hand (QA PW1) | Automation never calls it (hard limits keep it off anything Keychain-adjacent) |
| OS-M7-5 | The S-PDF-LOCK interop matrix (P2-192, QA PL1) | Needs other apps and devices |
| OS-M7-6 | Look review and VoiceOver pass of the tool window, the sheet and the Read QR window (QA TW1–TW6) | OWN-UI-1; not automatable here |
| OS-M7-7 | If R6 shows an ffmpeg cancel takes over NFR-9's 1 s: shorter grace for ffmpeg, a polite quit before SIGINT, or a budget change | G-M7-3; M7 does not change the budget |
| OS-M7-8 | Next: P2-12 (PDF → images and text, then P2-107's conversions) and P2-57 (beta channel) | §2.10 |
| OS-M7-9 | If the measured qpdf contribution is over 4.5 MB | OWN-SIZE-1/2 |
| OS-M7-10 | Run the owner-only XCUITests (`ResultCardUITests`, `ToolWindowUITests`) | D-M4-14 |
| OS-M7-12 | The cold first drop of a process takes 23–94 ms to show the island (warm drops 3–5 ms): draw the island's content once at launch, or set a separate first-drop budget | G-M7-10; M7 does not change P1-40 |
| OS-M7-11 | Merge and push `m7` when satisfied | Owner only |

---

## 9. Risks

| ID | Risk | Mitigation |
|---|---|---|
| R1 | qpdf's build or link fails for arm64/26.0 with native crypto (not tried, §3.1) | C2 is the first code task after OS-M7-1; the flags follow 13 §4.4; CMake logs kept in `Vendor/logs` |
| R2 | The qpdf + libjpeg-turbo contribution passes 4.5 MB | Worker only (no duplicate in the app); `-Os`/dead-strip checked; OS-M7-9 |
| R3 | A password leaks through a path not probed (crash reports, a framework's own logging) | B7 probes every store named in P2-102 with planted leaks first; the shim silences qpdf's output; crash-report fields are checked by reading what `Diagnostics` collects; the record lists what was not probed |
| R4 | Memory residue: the typed `String`, XPC's buffer and qpdf's internal copies are freed but not zeroed | Stated as best effort (D-M7-14), as 17b §2.2 already says; short job lifetimes |
| R5 | A non-activating key panel takes keystrokes the person meant for another app | Opens only right after a drop on Zivlet's own wheel; Esc closes; QA TW5 |
| R6 | Non-ASCII passwords: PDFKit and Preview cannot open the files | OWN-PDF-1 warning and the card note; QA PW3 |
| R7 | The owner-password rule is subtle (bypass risk, OWN-LK-1) | E5's fixtures cover each branch; the rule is one pure function with a table test |
| R8 | Hostile PDFs exhaust memory or time in the worker | D2 limits and watchdog; the worker is the crash boundary (P2-01) |
| R9 | The timing target never judges on a busy Mac, so budgets go unmeasured for long | "Not judged" is a skip, which fails the exit run honestly; the owner can run `make timing` on a quiet Mac |
| R10 | `IJG` added to the licence allow-list by mistake widens it | Only `IJG`, with the libjpeg-turbo entry; licence-gate test |
| R11 | E11 hides slices people may already use | Only pairs that fail today are hidden (no engine handles them) |

---

## 10. Gaps recorded up front

| ID | Gap | Next step |
|---|---|---|
| G-M7-1 | qpdf not built; the library-API prototype, its `ps` check, the build time and the size not measured (§3.1) | **Closed** in stream C's second session: built in 30 s (load 3.3 → 8.8), the worker grew by 1.74 MB; the harness is replaced by the shim's tests; `ps` was not watched (a password reaches qpdf only through memory, never argv), 20d execution notes |
| G-M7-2 | The convert wheel offers PDF → JPG/PNG that fail (`pairNotSupported`); read from code, not run in the app | E11 now; P2-12 later |
| G-M7-3 | The ffmpeg cancel test's 1.5 s bound was already looser than NFR-9's 1 s; 1.46–1.49 s measured | R6, OS-M7-7 |
| G-M7-4 | Focus and Secure Input measured off screen with no typing; VoiceOver and full-screen spaces not tried | QA TW2–TW6 |
| G-M7-5 | Password residue in freed memory (String, XPC buffer, qpdf) | Recorded, best effort (D-M7-14) |
| G-M7-6 | P2-12 and P2-57 not built | OS-M7-8 |
| G-M7-7 | S-PDF-LOCK interop matrix (P2-192) | OS-M7-5 |
| G-M7-8 | `SecCreateSharedWebCredentialPassword` not exercised by automation | OS-M7-4 |
| G-M7-10 | P1-40: the first drop in a process measured 23–94 ms in the timing suite (two judged runs at load 2.9: 90.8 and 93.6 ms); warm drops 3–5 ms. The app's own first drop (m5a X2 signpost) measured 12.7 ms, judged at load 2.3, so the cold cost seen in the test process was not seen in the app | OS-M7-12; a known issue in `NotchHUDTiming` until then |
| G-M7-11 | `make app` failed twice inside exit runners (an `rm` racing on Sparkle's `XPCServices`, then a signing failure on the half-trimmed framework); it passed on its own and in m6 Z1. Cause not found | Watch in F4; look at the embed and trim phases if it recurs |
| G-M7-9 | Unit tests outside stream R's four still assert wall time (near-drop HUD 50 ms, scheduler 100 ms / 1 s, shared load 300 ms, stall watch, text service, tray, OCR); found in R5 | Same treatment as R4–R7 in a later task (20a, execution notes) |
| G-M7-12 | READ QR accepts SVG, but ImageIO does not decode SVG: an SVG is reported as not read (seen by a probe, not in the app) | Rasterize SVG in the worker through EngineImage's renderer, or drop SVG from the slice's formats |
| G-M7-13 | The tool window's disabled-reason state, the bipolar slider and the timecode field were not seen on screen; no tool uses them yet | Capture with E9's Lock window (F3) and the first 2B tool |
| G-M7-14 | `BoxPanelTests.aRealClickOnItsContentMakesItKey` is skipped while the screen is locked (no window can become key then); it last ran and passed with the screen awake in stream A's first `make test` | Runs whenever the gates run with the screen awake; F4 should say whether it ran |
| G-M7-15 | The kernel shows no process's environment on this macOS, not even a child's (`ps -E`, `KERN_PROCARGS2`); a child's environment can only be checked at its spawn request | `LeakProbe` checks spawn requests (20c B7); E's policy run records the requests of its jobs |
| G-M7-16 | In the test process SwiftUI exposed no accessibility tree, so the password sheet's VoiceOver labels are checked through a list that uses the view's own strings, not by walking the tree | OS-M7-6 (VoiceOver pass); an XCUITest when the owner runs them |
| G-M7-17 | P2-102's policy through real Lock, Unlock, Change, a wrong attempt and a cancel in the worker, and the record, undo and history probes, wait for E4–E7; today the policy covers the type, the wire form, the log, the diagnostics and the settings | Stream E grows `PasswordPolicyTests` (20c B7 notes) |
| G-M7-18 | Stream C's execution session was refused the qpdf build as well (the permission check: code from external), so CQPDF does not exist: C2's build and wiring, C4, C5, C6's size row, and streams D and E wait | **Closed**: the build ran on 2026-10-29 (third attempt in `Vendor/logs`, after two script fixes); the repository does not record who started it. Stream C finished in its second session (20d execution notes) |
| G-M7-19 | C5's `WorkerSelection` case ("a PDF tool job with the worker down fails with `engineMissing(.pdf)`") needs a PDF job, which stream E's protect operation brings; today the validator and the service refuse a PDF plan without the engine (tested) | E2/E3 add the case |
| G-M7-20 | With the screen locked, three frame-driven tests fail (`theFirstFrameEndsTheTriggerToFrameSignpost`, `hideFadesOutAndResets`, `samplerDeliversFramesUntilStopped`: no display frames arrive); at load 35–65 two more failed once (`shutdownGivesUpAtTheLimitWhenAJobIgnoresCancel`, `cancellingTheTaskCancelsTheWorkersJob`). None touches stream C's code. With the screen awake on 2026-10-31 all five passed in all six full test runs, so the three were the locked screen; the two were not re-run at a measured load of 35–65 | Skip the three while the screen is locked, as G-M7-14 does, or move them to the timing target (G-M7-9) |
| G-M7-21 | `box-idle.sh` (Y8) has no load guard: on 2026-10-31 it failed once at load 7.1 (`panel-still` 2.03 % over baseline, limit 0.1 %) and passed when run alone at load 2.6 (0.008 %). `ZivletBox` has no commit since `m6`, so load is the likely cause; one rerun does not prove it. On stream D's last commit (2026-11-01) it failed twice more, with no pass seen: 0.384 % at load 12.8, 1.19 % at load 2.9 rising to 5.7, with `dasd` holding most of a core; a third run found no quiet window in 20 minutes (20e notes) | Give the idle rows the load guard of `timing.sh` (D-M7-3), without moving the limit |
| G-M7-22 | The watchdog's stop has never run in a real worker: no test makes a qpdf call hang, so `onStuck` in `Worker/main.swift` is only compiled. The timer, the budget, the turns and the disarm are tested with an injected clock | A DEBUG request that holds a PDF step past a short budget, in `make pdf-smoke` (F) |
| G-M7-23 | Copy Text and Read QR refuse an oversized PDF with their general line ("larger than Zivlet's safety limit"), not "This PDF is larger than 512 MB."; it is one skipped file either way | Word it when E10 touches their copy |
| G-M7-24 | The watchdog covers qpdf steps only; PDFKit rendering in Copy Text and Read QR has none (their cancel is between pages) | Decide with P2-12 |
| G-M7-25 | D-M7-18 asks for tests at every boundary. Size, pages, filters and warnings have them through real files; nesting is proved at 450 and 600, not 500 and 501; the container and parser-error limits are only shown to reach the shim, with no file at 1,000,000, 50,000 or 1,000 | Add with the PDF corpus of 03b's fuzzing row |
