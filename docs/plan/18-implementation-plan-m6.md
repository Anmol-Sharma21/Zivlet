# 18 — M6 implementation plan: box follow-ups, the cap rule, the worker and Copy Text (TDD)

Date: 2026-10-26. Status: ready to execute after the owner reads it. Branch: `m6`, made from `main` at `9cc6c69`.
Order: [design/17-feature-roadmap](../design/17-feature-roadmap.md) §4.2, wave 2A steps 4 and 5, with the M5b
follow-ups of [17-m5b-record](17-m5b-record.md) §7 first. Acceptance: the 05 rows P2-100, P2-01, P2-51 (base only,
D-M6-6), P2-103 and P2-104, and the gaps G-M5b-8, G-M5b-9 and G-M5b-10. Process model and contracts:
[02-architecture](02-architecture.md) §2 and §7.4–§7.5, [03b](03b-system-design-engines.md) (threat rows),
[design/10](../design/10-tech-strategy.md) §1–§2, [design/14](../design/14-app-platform.md) §5.4. OCR:
[design/17c](../design/17c-image.md) §1, [design/17a](../design/17a-pdf.md) §2 (L1) and §3.8,
[00-decisions](../design/00-decisions.md) OWN-OCR-1, OWN-PDF-5, OWN-QA-1. Look: OWN-UI-1,
[design/19b](../design/19b-notch-look.md), [design/19c](../design/19c-drop-box-look.md).

This file is the index: verification status, scope, the gap audit, the prototypes, decisions, streams and order,
conventions, exit rows, owner steps and risks. The tasks are in five parts, each under 800 lines:

| Part | Stream | Tasks |
|---|---|---|
| [18a](18a-m6-box-follow-ups.md) | **A** — M5b follow-ups | A0 baseline · A1 cancellable executor · A2 busy overlay for Move/Copy to · A3 Trash off the main thread, cancellable, with Undo · A4 box resolve and promise intake off the main thread · A5 the panel's opacity exit |
| [18b](18b-m6-catalog-cap.md) | **B** — P2-100 | B1 visibility marks · B2 the cap and its lint · B3 the combining rule · B4 reserved slots |
| [18c](18c-m6-worker.md) | **C** — P2-01 | C1 `ZivletIPC` · C2 boundary validation · C3 `WorkerService` · C4 connection and transport · C5 `RemoteEngine` · C6 crash retry · C7 fallback · C8 peer requirement · C9 worker target · C10 signing and bundle checks · C11 app wiring · C12 worker smoke |
| [18d](18d-m6-ocr-copy-text.md) | **D** — P2-51 base, P2-103, P2-104 | D1 CER tool and fixtures · D2 `EngineVision` and language defaults · D3 capability probe · D4 `TextRecognizer` · D5 PDF text · D6 assembly and scripts · D7 warm-up · D8 worker text job · D9 the COPY TEXT slice · D10 clipboard and `.txt` · D11 the text result · D12 tool wiring · D13 setting · D14 privacy · D15 demo |
| [18e](18e-m6-qa-exit.md) | **E** — QA, exit, record | E1 QA rows · E2 exit runner · E3 screenshots · E4 exit run and record |

Naming: "M6" is this branch's slice of wave 2A (steps 4–5 plus the M5b follow-ups), not a 05 milestone; 05 is not
changed by this plan.

Clean room: unchanged. No code, assets, sounds or UI strings from any other app; prior art is described in our own
words only. Every string quoted in these parts is Zivlet's own; new ones are marked *new*. OCR fixtures are rendered
by our tests from sentences written for Zivlet with fonts that ship with macOS (D-M6-11); no scan or image is
downloaded.

---

## 0. Verification status of this plan

| Check | Result |
|---|---|
| Baseline | `nice -n 10 make test` on `m6` at `9cc6c69` (this session, load 5–17): 18 test bundles, **1773 tests**, one failure: `SubprocessRunnerTests.aChildIgnoringSIGINTIsKilledAfterTheGrace` measured **0.41 s** where it expects ≥ 0.9 s. It passed when rerun by name (1.39 s). The elapsed time was *shorter* than the grace, so this is not load; the likely cause is a race in the test (SIGINT arriving before the child ignores it). Recorded as G-M6-9. `make lint`, `make coverage`, `make app` and the release gates were **not** re-run for this plan (docs only); task A0 runs them before any code |
| Code read | `ZivletEngineKit/Engine.swift`, `ExecutionPlan.swift`; `ZivletRuntime/JobPipeline.swift`, `JobScheduler.swift`, `JobRequestFactory.swift`; `ZivletCore/Jobs/JobError.swift`, `JobRequest.swift`; `ZivletCore/Catalog/*` (`ToolSpec`, `ToolTable`, `ToolCatalog`, `ConversionTable`, `ActionID`); `ZivletWheelCore/SliceBuilder*.swift`, `WheelGeometry.swift`; `ZivletBox/BoxController*.swift`, `BoxPanel.swift`, `Views/BoxEntrance.swift`; `ZivletShelfCore/BoxPresentation*.swift`; `ZivletActions/MoveExecutor.swift`, `ActionService.swift`, `ActionResult.swift`; `ZivletNotch/IslandAnimation.swift`; `ZivletNotchCore/IslandMotion.swift`; `App/AppDelegate.swift`, `App/ActionWiring.swift`; `Package.swift`, `project.yml`, `Config/*.xcconfig`, `Config/*.entitlements`, `Makefile`, `Scripts/m5b-exit.sh`, `check-bundle.sh`, `sign-app.sh`, `verify-signatures.sh`, `check-release-paths.sh`, `coverage.sh` |
| Prototypes | Run on this Mac on 2026-10-26, outside the repository, under the hard limits (only files the prototypes created in a temporary folder; no Desktop, Documents, Downloads, iCloud Drive, Photos or removable volumes; no security-scoped bookmarks): (a) an XPC service in an app bundle, (b) Vision text recognition on rendered fixtures, (c) PDF text layer and OCR. Results in §3 |
| Code in the parts | Swift in the parts is specification-grade and was **not** compiled. Each RED step names the expected compile error or assertion, not a recorded one |
| Hardware | 14-inch MacBook Pro (Mac14,9, M2 Pro), macOS **27.0** (26A428), Xcode 27.0 (27A266a), Swift 6.4. Load during the prototypes: 5 to 60 (the owner's other work); every timing in §3 carries that caveat |

---

## 1. Scope

| In M6 | Row | Stream |
|---|---|---|
| The box's busy overlay driven by Move to… and Copy to…, with progress, Cancel and Esc; Move/Copy cancellable between items, partial result and Undo | G-M5b-9 | A |
| Move to Trash from the box: off the main thread, cancellable between items, partial result, Undo | G-M5b-9, G-M5b-8 | A |
| Resolving the box at show and making promise files into items, off the main thread | G-M5b-8 | A |
| The panel leaves with opacity (D-BL12); Reduce Motion: a 0.18 s fade (D-M6-3) | G-M5b-10 | A |
| Visibility marks, a 12 cap on every list with a lint, the combining rule for mixed families, reserved slots | P2-100 | B |
| `ZivletWorker.xpc`: Codable IPC, launched on demand, idle exit, crash → one serial retry → "This file made the engine crash", in-process fallback, peer requirement, signed with the hardened runtime and bundled | P2-01 | C |
| `EngineVision` base: the module, the capability probe, page rendering; **not** the Read QR tool | P2-51 (part) | D |
| OCR core: `TextRecognizer`, ordered languages, Hindi capability, warm-up, all Vision calls in the worker | P2-103 | D |
| Copy Text: images, then PDF pages; clipboard, ⌥ `.txt`, multi-file, text result card, "No text found" | P2-104 | D |
| QA rows, `Scripts/m6-exit.sh`, screenshots of the new UI, the record | — | E |

Not in M6: G-M5b-11 and G-M5b-14 (the owner's look review; closed); G-M5a-1 (fast-progress CPU); the owner's hardware
QA rows of M5a/M5b; the Read QR tool itself (P2-51's results window needs P2-30's tool window); EngineMedia in the
worker (D-M6-5); Make Searchable (P2-150, 2C); History (P2-145, 2C) beyond "nothing stores the text"; the full
ordered language list in Settings (D-M6-14); a ZivletEngines dynamic framework shared by app and worker (02 §3
Phase 2, spike P-PKG) — measured in E4, decided by the owner (OS-M6-9).

---

## 2. Gap audit: what exists today and what is missing

Read from the code on `m6` at `9cc6c69` and checked with the baseline run (§0). "Task" is where the gap is closed.

### 2.1 Stream A — the M5b gaps

| Gap | Clause | Exists today | Missing | Task |
|---|---|---|---|---|
| G-M5b-9 | busy overlay with progress | `BoxPresentation` has `.busyStarted(verb:)`, `.progress(Double)`, `.busyEnded` and the `.busy(verb:fraction:)` overlay; `BoxHeader` and `BoxActionBar` draw the verb, bar, percent and Cancel; no caller sends `.busyStarted` | Move/Copy to… must send busy events with a fraction per item | A1, A2 |
| G-M5b-9 | Cancel and Esc | `.escape` while busy → `.cancelBusy` → `running?.cancel()` (`BoxController.swift:169`, `+Selection.swift:36`) | the executor never checks cancellation, so cancelling the task changes nothing | A1 |
| G-M5b-9 | Move/Copy cancellable between items, partial result and Undo | `MoveExecutor.run` loops over steps with no check; `ActionService` records one undo batch for what moved and builds "Some items weren't moved." cards | a check before each step, a `cancelled` list in `MoveReport`, copy that says the move was stopped, Undo covering the part that moved | A1, A2 |
| G-M5b-9 | Trash cancellable, partial result, Undo | `BoxController.trash(_:)` trashes on the main actor in a loop, reports "n moved to the Trash", **no Undo** (`undo: nil`) | an off-main trasher with a check per item, the Trash locations recorded as `UndoMove` entries, the box getting its items back on Undo | A3 |
| G-M5b-8 | trashing off the main thread | on the main actor (0.63 ms a file, ≈ 125 ms for 200, measured in M5b) | as above | A3 |
| G-M5b-8 | box resolve at show off the main thread | `Shelf+Resolve` runs on the main actor at show (0.02 ms a present item, 0.14 ms a missing one) | resolve in a `@concurrent` function, draw the last known statuses first, apply the new ones when they arrive | A4 |
| G-M5b-8 | promise files into items off the main thread | `PromiseReceiving` makes items on the main actor | the same move | A4 |
| G-M5b-10 | opacity exit (D-BL12) | `render()` calls `panel.orderOut(nil)` at once (`BoxController+Panel.swift:37`); the entrance (`BoxEntrance`) and thumbnail fade exist | fade the panel's alpha to 0 on the collapse curve, then order out; a show during the fade cancels it; Reduce Motion 0.18 s fade | A5 |

### 2.2 Stream B — P2-100

| Clause | Exists today | Missing | Task |
|---|---|---|---|
| `ApplicabilityRow` marks each tool `defaultVisible` or `extra` | rows hold `single` and `multi` lists only | a visibility mark per row entry; the builder drops extras | B1 |
| visible tools in catalog order capped at 12 for **every** list (tools, same-family conversions, actions) | only the mixed-family *conversion* union is capped (`SliceBuilder+Convert.swift:33`); today's longest lists: 9 conversions (pdf, documents), 9 tools (video single), 6 actions | one cap applied to every list; lists are short enough today that nothing is cut | B2 |
| lint test fails if any default list > 12 | none | `CatalogCapLintTests` over every format × single/multi, plus actions, printing each count | B2 |
| mixed-family selections show combining tools whose families cover all items | a mixed selection shows nothing, except Read QR when every item is an image, GIF or PDF (hard-coded `qualifiesForQRScan`) | accepted formats as data on the spec; Read QR becomes data; the rule applies to any tool marked as combining | B3 |
| table tests over all inputs and 30 mixed sets | `ToolCatalogTests` covers per-format lists and a few mixes | 30 mixed sets in a table | B3 |
| 05b: the cap counts the reserved TRANSCRIBE slot in audio and video lists | none | a reserved-slot table counted by the lint | B4 |

### 2.3 Stream C — P2-01

| Clause | Exists today | Missing | Task |
|---|---|---|---|
| engines run in an XPC service | no worker; `JobServices.engines: [any Engine]` run in the app (`JobPipeline`); no `WorkerClient` protocol in code (02 §7.4 describes one) | the worker target, IPC, a client, a proxy engine | C1–C5, C9 |
| `Codable` plans | `ExecutionPlan`, `Stage`, `JobRequest`, `JobWorkspace`, `StagedOutput`, `JobError`, `PlanNote` are all `Codable` | an envelope with a protocol version; the request/reply/event types | C1 |
| worker crash → each in-flight job retried once, singly | `JobError.crashed(signal:)` exists for helpers; no worker crash case, no retry | `.workerCrashed`, `.engineCrashedOnInput`, one serial retry gate | C6 |
| a second crash → "This file made the engine crash" and the batch continues | per-file failure isolation exists in the scheduler | the copy in `JobErrorCopy` and the test | C6 |
| in-process fallback | today everything is in-process | a selection rule: worker missing, damaged or unreachable → in-process for conversions; never for a job that crashed the worker; never for Vision | C7 |
| test: injected crash fixture | — | a crashing transport in unit tests; a DEBUG-only self-kill request in the real worker for the smoke row | C6, C12 |
| 02 §2.1: unsandboxed, hardened runtime, **no entitlements**, launched on demand, exits when idle | — | the target, signing, and an own idle exit (the prototype showed launchd keeps an idle worker alive) | C3, C9, C10 |
| 03b: peer code-signing requirement, every request validated | — | `WorkerPeerPolicy` (team for Developer ID, signing identifier for ad-hoc), `WorkerRequestValidator` | C2, C8 |
| release-check keeps passing | `check-bundle.sh` checks helpers and libraries; `sign-app.sh` signs nested code in frameworks but **not** `Contents/XPCServices`; `verify-signatures.sh` checks every Mach-O | worker presence and dependencies in `check-bundle.sh`; inside-out signing of the worker in `sign-app.sh`; script tests | C10 |

### 2.4 Stream D — P2-51 base, P2-103, P2-104

| Row | Clause | Exists today | Missing | Task |
|---|---|---|---|---|
| P2-51 | EngineVision base | no `EngineVision` module; no Vision import anywhere in `Sources/` | the module (strict, Foundation + Vision + PDFKit + ImageIO), capability probe, page rendering | D2, D3, D5 |
| P2-51 | Read QR tool, results window | `ToolID.qrScan` and its slice exist; a drop on any tool shows only a DEBUG note (`AppDelegate.handle`) | **not in M6** (D-M6-6) | — |
| P2-103 | `RecognizeDocumentsRequest`, options, `.accurate` only on the fallback | — | `TextRecognizer` with the documents request and a `RecognizeTextRequest(.accurate)` fallback; prototype §3.2 confirms the API on this SDK | D4 |
| P2-103 | languages ordered, Hindi first for hi/mr users or a Hindi keyboard; auto-detect off | — | `LanguageDefaults` (pure) | D2 |
| P2-103 | capability probe hides Hindi when no language has `languageCode == "hi"` | — | `VisionCapabilities` | D3 |
| P2-103 | all Vision calls in `ZivletWorker` only | no worker | the text job in the worker; no in-process Vision (D-M6-8) | D8 |
| P2-103 | warm-up at `.utility` after onboarding, 64 px and ~3000 px, "warmed for OS build X", re-warm after an OS update | — | `VisionWarmup` (pure state + worker request); sizes from §3.2 | D7 |
| P2-103 | determinate "Preparing text recognition (one time)…" state, never times out | — | a working-state line for a Copy Text job while warm-up is not done | D12 |
| P2-104 | instant slice `COPY TEXT` | no `copyText` tool | `ToolID.copyText`, spec, rows per 17 §8.1 | D9 |
| P2-104 | default → clipboard; `.currentHostOnly` | `ClipboardAction` copies files and paths | `copyText(_:)` with the current-host option | D10 |
| P2-104 | result card text variant: first lines, characters, scripts, Copy again / Save as .txt / Show all | `ActionResult` has toast/partial/failed/cancelled; HUD and Notch HUD draw toasts and cards | a text case, both presenters, a Show all window | D11 |
| P2-104 | ⌥ writes `X Text.txt` (UTF-8, LF); multi → one text with `— name —` separators, ⌥ one .txt each | `Publisher` publishes staged files with exclusive rename; `OutputNamer` has tool suffixes | the text writer and the `Text` suffix; `TextAssembly` | D6, D10 |
| P2-104 | "No text found" is not an error | — | a toast, nothing written | D11 |
| P2-104 | History stores "Text copied, n characters", never the text | no History (P2-145); the status menu's recent list comes from undo entries | nothing stores the text anywhere (os_log, settings, recent list); History itself waits for P2-145 | D14 |
| P2-104 | CI fixture fails if a Devanagari golden returns no Devanagari | — | `OCRFixtureTests` | D1, D4 |
| P2-104 | PDF pages with a Devanagari text layer go through OCR (17a L1) | — | `PDFTextSource`; prototype §3.3 confirms the need | D5 |
| P2-104 | Word- and Chrome-made Hindi PDF fixtures | — | CoreText- and WebKit-made PDFs in tests; real Word/Chrome files are an owner step (OS-M6-3) | D5 |
| P2-104 | honour the PDF extract permission (OWN-PDF-5) | — | refuse when `allowsCopying` is false, with copy | D5 |
| M5a exit | Copy Text 12/12 Hindi+English fixtures ≤ 1 % CER | — | the fixtures, the CER tool and the row | D1, E2 |

---

## 3. Prototype results (2026-10-26, outside the repository)

Three throwaway programs, built with `swiftc` on this Mac and kept outside the repository; nothing from them is
copied into it. They touched only files they created in a temporary folder. No system
process was signalled; the only process killed was the prototype's own worker. The `tccd` log for the prototype
processes over the run window had **0** lines.

### 3.1 (a) XPC service: launch, files, cancel, crash, signing

Setup: `Proto.app/Contents/XPCServices/ProtoWorker.xpc` (`CFBundlePackageType XPC!`, `ServiceType Application`), both
signed ad-hoc with `--options runtime` (worker first, then the app); `codesign --verify --strict --deep` passed;
`flags=0x10002(adhoc,runtime)`. Swift XPC (`XPCSession(xpcService:)`, `XPCListener(service:)`, a `XPCPeerHandler`
per session), Codable messages, the app run from its executable inside the bundle.

| Question | Result |
|---|---|
| Launch on demand | first message 12–38 ms over seven runs (worker started by launchd), then 0.16–0.3 ms a round trip |
| Files by path | the worker read a file the app wrote, by absolute path: works (both unsandboxed) |
| Bookmark without security scope | the app made a bookmark with `.withoutImplicitSecurityScope` (956 bytes); the worker resolved it to the same file, not stale. Works, adds nothing for an unsandboxed worker |
| File descriptor in a Codable message | **does not pass a descriptor**: `System.FileDescriptor` is `Codable` as its number, so the worker got `fd=3` and `fstat` failed |
| File descriptor in an `XPCDictionary` | works with `xpc_dictionary_set_fd` / `xpc_dictionary_dup_fd` (C API via `withUnsafeUnderlyingDictionary`): the worker's descriptor had the same inode and read 19 bytes. The Swift `XPCDictionary` descriptor subscript is **macOS 27.0+** in this SDK, so it cannot be used with a 26.0 deployment target |
| Cancellation | a 5 s job polling a cancel flag every 10 ms; the cancel request's reply came 4.6–6 ms after it was sent; progress events from the worker to the app over the same session arrived (2 in 600 ms at a 200 ms cadence) |
| Long jobs | `XPCReceivedMessage.handoffReply(to:)` keeps the listener free while a job runs on another queue |
| Worker crash (`abort()`) | the pending reply failed in 0.7–2 ms with "Underlying connection interrupted", **and the session was cancelled** (`canRetry=false`): later sends fail with "Attempting to send message using a canceled session". A new `XPCSession` relaunched the worker |
| Kill of our own worker (SIGKILL) | in-flight job failed after 0.3 ms, same error; new session needed |
| Relaunch time after a crash | 30–42 ms normally; **10,032 ms and 10,040 ms** in two of six relaunches (launchd's relaunch throttle after repeated crashes) |
| Crash reports | every `abort()` wrote a `.ips` report to the user's diagnostic reports; SIGKILL wrote none. The seven reports the prototype made were deleted afterwards |
| Idle exit | the worker was still alive 20 s idle with the session open and **15 s after the session was cancelled**: launchd does not stop it promptly, so "exits when idle" (02 §2.1) needs our own timer |
| Peer requirement | `.isFromSameTeam()` **refuses** an ad-hoc worker ("Peer forbidden (code signing)"); `XPCPeerRequirement(lightweightCodeRequirements: ["signing-identifier": …])` accepts it; a wrong identifier is refused |
| Swift 6 | `XPCReceivedMessage` is not `Sendable`; capturing it in the handoff closure is a warning, an error under the repo's warnings-as-errors unless `@preconcurrency import XPC` (or a small wrapper) is used |
| TCC | no prompt and no `tccd` line, but only temporary-folder files were used: the attribution of a worker reading Desktop or Downloads files to the app was **not** tested (hard limits) — OS-M6-5 |

### 3.2 (b) Vision on rendered fixtures

Twelve images rendered with CoreText from sentences written for this plan (English, Roman Hinglish, Hindi, mixed),
fonts that ship with macOS (Helvetica Neue, Kohinoor Devanagari, Devanagari Sangam MN, ITF Devanagari); one white on
dark at 17 px; one degraded (3° rotation on white, Gaussian blur σ 0.9, seeded uniform noise ±4 %, JPEG quality 0.35).
CER = Levenshtein distance over Unicode scalars ÷ reference length, after NFC and collapsing whitespace.

| Item | Result |
|---|---|
| Revisions in this SDK | `RecognizeDocumentsRequest`: `revision1` only; `RecognizeTextRequest`: `revision3` only |
| Languages | documents request and `RecognizeTextRequest(.accurate)`: the same **33**, including `hi-Deva-IN` and `mr-Deva-IN` (`minimalIdentifier` `hi`, `languageCode` `hi`, script `Deva`); `.fast`: 6 Latin languages only |
| Options | `TextRecognitionOptions` = `minimumTextHeightFraction`, `automaticallyDetectLanguage`, `recognitionLanguages`, `useLanguageCorrection`, `customWords`, `maximumCandidateCount` (as P2-103's [challenge] says); `RecognitionLevel` only on `RecognizeTextRequest` |

| Config (12 fixtures) | ≤ 1 % CER | Devanagari missing in | First call | Warm median / max |
|---|---|---|---|---|
| documents `[hi, en]`, auto off | **12/12** (after the fix below) | — | **118 s** (cold model compile, `ANECompilerService` busy) | 127 / 337 ms |
| documents, auto-detect on | 10/12 (one-Hindi-word line read "48ah"; the broken degraded image) | 2 | **99 s** (its own compile) | 177 / 1733 ms |
| text `.accurate` `[hi, en]` | 11/12 (the broken degraded image) | — | 166 ms | 117 / 490 ms |
| text `.accurate` `[en, hi]` | 2/12 | 10 (Devanagari silently dropped) | 131 ms | 180 / 371 ms |
| text `.accurate` auto | 10/12 | 2 | 155 ms | 119 / 233 ms |
| text `.fast` (English) | 2/12 | 10; output contained U+FFFF | 208 ms | 15 / 22 ms |

The first pass rendered the degraded image through a broken Core Image chain (random alpha in the noise layer made a
far harsher image than intended); it scored CER 0.167 with `[hi,en]`. The degradation was rewritten as a
deterministic pixel operation (the one specified above) and that image scored 0.000, giving 12/12. A sweep on the
same sentence with the deterministic chain: noise ±0–4 % at 22 and 30 px → all 0.000; ±10 % → 0.000; ±20 % → 0.143
(16 px) and 0.048 (22 px); ±30 % → 0.452 / 0.048; ±45 % → 1.000 / 0.452. Losing the nukta (रोज़ → रोज) is the first
error to appear. So the 12-fixture bar has margin at ±4 %, and the stress samples above are where it ends.

Compile cache: after the first `[hi,en]` call, other configurations of the text request were warm at once, the
documents auto-detect configuration compiled again (99 s), and a **2550 × 3300** page image compiled again (148 s,
§3.3) although 1400-pixel images were warm. A different executable later ran warm at once, so the cache is shared
across processes on this OS; whether an XPC service shares it was not measured.

### 3.3 (c) PDFs: text layer first, OCR for scans

| PDF (made by the prototype) | PDFKit text layer | Usable (≥ 20 printable, < 5 % U+FFFD) | Layer CER | OCR at 300 DPI, documents `[hi,en]` |
|---|---|---|---|---|
| English, CoreText into a PDF context | 70 chars in 6.5 ms | yes | 0.000 | 0.000 (first call **148 s**: new size compile) |
| Hindi, CoreText | 41 chars | yes | **0.054** ("पाकर्", "जाएँ गे": visual order, 17a L1) | 0.000 in 183 ms |
| Mixed, CoreText | 48 chars | yes | **0.054** ("िटकट", "िदया") | 0.000 in 145 ms |
| Mixed "scan" (the page is one image) | 0 chars | no | 1.000 | 0.000 in 155 ms; render 19 ms |

`allowsCopying` was true and `isEncrypted` false for all four. Not tried: Word-, Chrome- or WebKit-made PDFs,
encrypted PDFs, multi-page timing.

---

## 4. Decisions

| ID | Decision | Why |
|---|---|---|
| D-M6-1 | Streams in this order: A (small, independent, closes M5b) → B → C → D → E. D1–D7 (pure parts and the in-process recognizer behind a port) may start while C is in progress; D8 onward needs C | §4.2 order; D's tests need no worker until D8 |
| D-M6-2 | **Worker IPC:** Swift `XPCSession`/`XPCListener`, one session per app, Codable messages in an `Envelope` with `protocolVersion`. A job step is a request whose reply comes when the step ends (`handoffReply`); progress and spawned PIDs are events from the worker over the same session; cancel is its own request. Any session cancellation fails every in-flight call with `.workerCrashed` and the next call opens a new session | Prototype §3.1: interruption cancels the session; replies give a natural "in flight" table |
| D-M6-3 | **Panel exit:** opacity on the island's collapse curve, ordered out when it settles (≤ 0.6 s); Reduce Motion: a 0.18 s fade, as D-BL12 and `IslandMotion.reducedFade` say. The brief for this milestone asked for "instant under Reduce Motion"; D-BL12 says a fade. This plan follows D-BL12 and asks the owner (OS-M6-6) | One motion language (D-BL12, D-NL13) |
| D-M6-4 | **Files go to the worker by absolute path** (02 §2.2), validated at the worker's boundary; no descriptors and no bookmarks in M6 | Both processes are unsandboxed; prototype: Codable cannot carry a descriptor, the Swift descriptor API is 27+ |
| D-M6-5 | **What runs in the worker in M6:** EngineImage (ImageIO, libwebp, resvg) and EngineVision. EngineMedia stays in-process for now: ffmpeg is already a separate process (02 §1), and moving its PID records and orphan reaping across XPC is a separate task. Recorded as G-M6-1 | Smaller first step; covers the in-process parsers 02 §1 names (ImageIO, libwebp) |
| D-M6-6 | **P2-51 is split:** the EngineVision base (module, capability probe, page rendering) is built for P2-103; the Read QR tool and its results window wait for P2-30's tool window. G-M6-2 | P2-103 depends on the base, not on QR |
| D-M6-7 | **Peer requirement:** both sides check the other. A build with a Team ID uses `.isFromSameTeam(andMatchesSigningIdentifier:)`; an ad-hoc build (Debug, the release dry run before O-1) uses a lightweight code requirement on the signing identifier. The choice comes from the running code's own signature (`SecCodeCopySigningInformation`), not from a build flag | Prototype: the team requirement refuses ad-hoc code. An identifier-only check is weak (any ad-hoc binary can claim it); recorded as R3 |
| D-M6-8 | **Vision only in the worker**, as P2-103 says. If the worker is unavailable, Copy Text fails with copy (*new*) "Text recognition isn't available right now." — no in-process Vision | One process identity for the model cache (P2-103, S-V1) |
| D-M6-9 | **In-process fallback** for conversions only when the worker cannot be reached at all (bundle missing, signature check failed, or no session within 30 s); never for a job that already crashed the worker | A file that crashes the worker would crash the app |
| D-M6-10 | **Idle exit:** the worker exits 60 s after its last job ends (injectable clock). The app treats a session ended while nothing is in flight as normal | Prototype: launchd keeps an idle worker |
| D-M6-11 | **OCR fixtures are rendered at test time**, not committed as images: a JSON manifest of sentences written for Zivlet (no quotes from any source), font PostScript names of fonts that ship with macOS, sizes, dark/degrade flags; the degradation is the deterministic chain of §3.2 with a fixed seed. Parameters are fixed **before** D4 is implemented and are not tuned afterwards; harder samples are a separate, unscored stress set | Licence-clean, reproducible, no over-fitting |
| D-M6-12 | **CER tool:** Levenshtein over Unicode scalars ÷ reference scalar count, after NFC and collapsing every whitespace run to one space; pass ≤ 0.01 per fixture; the Devanagari check is "at least one scalar in U+0900–U+097F" | The measure 17c used; 05's M5a bar |
| D-M6-13 | **Real-Vision tests are opt-in** (`make ocr-check`, env `ZIVLET_OCR_FIXTURES=1`), like `make smoke`; `make test` uses a fake recognizer | A cold compile takes minutes (§3.2), which would stall `make test` |
| D-M6-14 | **Language setting:** one picker in Settings › General, "Text recognition" (*new*): "Match my languages" (default: the P2-103 rule), "Hindi and English", "English". The full ordered list of 17c §1.1 is deferred (G-M6-8) | Few words; covers the owner's languages |
| D-M6-15 | **PDF rule:** a page whose text layer is usable **and** has no Devanagari is read from PDFKit; any other page is rendered at 300 DPI and recognised. `allowsCopying == false` refuses the file with copy (*new*) "This PDF doesn't allow copying its text."; a locked PDF: "This PDF is locked." | Prototype §3.3; OWN-PDF-5; P2-107 not built |
| D-M6-16 | **Warm-up sizes:** 64 px, 1024 px and a 2550 × 3300 page, for the production configuration only (documents `[hi,en]` or `[en]`), at `.utility`, after onboarding and after an OS build change | Prototype: the page size compiled again |
| D-M6-17 | **Every current tool stays default visible**; ADD BG moves to extras only when its list would pass 12 (17 §8.1, OWN-APP-4). No list reaches 12 in M6 | No change people can see beyond COPY TEXT |
| D-M6-18 | **Real crash in the smoke row is a self-SIGKILL** (DEBUG-only request), so no crash report is written on the owner's Mac; unit tests use a crashing transport | Prototype: `abort()` writes `.ips` files |
| D-M6-19 | Exit rows are **Z1–Z11** (`Scripts/m6-exit.sh`), after X (M5a) and Y (M5b) | Same pattern as `m5b-exit.sh` |

---

## 5. Streams, order and estimate

| Order | Task | Depends on | Size |
|---|---|---|---|
| 1 | A0 baseline (`make test lint coverage app`) | — | S |
| 2 | A1 → A2 (executor, busy overlay) | A0 | S + S |
| 3 | A3 (Trash) | A1 | M |
| 4 | A4 (resolve, promises), A5 (exit fade) | A0 | S + S |
| 5 | B1 → B2 → B3 → B4 | A0 | S + S + M + S |
| 6 | C1 → C2 → C3 → C4 → C5 → C6 → C7 → C8 | B4 | L in total |
| 7 | D1 → D2 → D3 → D4 → D5 → D6 → D7 (parallel with 6) | B4 | M in total |
| 8 | C9 → C10 → C11 → C12 | C8 | M |
| 9 | D8 → D9 → D10 → D11 → D12 → D13 → D14 → D15 | C12, D7 | M |
| 10 | E1 → E2 → E3 → E4 | all | S + M + S + S |

Estimate (one engineer, ESTIMATE): A 3–4 days, B 3 days, C 8–10 days, D 7–9 days, E 2–3 days.

---

## 6. Conventions

| Item | Rule |
|---|---|
| Environment | `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before every `swift`, `xcodebuild`, `make`. Prefix heavy commands with `nice -n 10`; long ones run in the background. Never a clean `make vendor` rebuild |
| TDD | Each task: write the failing test → run it and **see** the stated failure → implement the minimum → green → refactor → commit. The record says where a test was not seen to fail first |
| Commands per task | RED/GREEN: `cd Packages/ZivletKit && nice -n 10 swift test --filter <Suite>`; then `nice -n 10 make test lint`; `nice -n 10 make coverage` when a gated module changed; `nice -n 10 make app` after C9, C11, D11, D12; `nice -n 10 make release-check` after C9, C10 |
| Gates (M6 exit) | `make test`, `make lint`, `make coverage` (80 % per module; **19 modules** after C1/C3/D2: `ZivletIPC`, `ZivletWorkerCore`, `EngineVision` added to `GATED_MODULES`), `make app`, `make release-check`, `make licence-gate`, `make script-test` (needs the media stage: run `make release-check` first in a fresh clone; `licence-gate` in a clone needs `Vendor/src` and `Vendor/downloads` copied in), `Scripts/m5a-exit.sh`, `Scripts/m5b-exit.sh`, `Scripts/m6-exit.sh` |
| Commits | Conventional, `git commit -s`, **no** `Co-Authored-By`; scopes `box`, `shelf`, `actions`, `catalog`, `wheel`, `ipc`, `worker`, `runtime`, `vision`, `tools`, `ui`, `settings`, `app`, `scripts`, `docs`. Only on `m6`; never on `main`, never pushed, history never rewritten |
| Code rules | Immutable values (edits return new values), files < 800 lines (aim 200–400), functions < 50 lines, nesting ≤ 4, no `print` (dev tools write through `FileHandle`), typed errors with Zivlet's own copy, validation at boundaries: worker requests, file URLs from drops, PDF permissions, the OCR fixture manifest, settings |
| Tests | Swift Testing (`@Suite`, `@Test`, `#expect`). File-system tests use `TestSupport.TempDir`; nothing outside temporary folders. Panels in shell tests stay off screen (x −5000). Timing tests (the 50 ms HUD test, frame tests, `SubprocessRunner` grace) are rerun once by name before they count as failures |
| Launching the app | Quit any Zivlet you launch with `osascript -e 'quit app "Zivlet"'`. Never trigger a modal alert or an open panel in the running app during automation: demos use DEBUG flags for folders |
| Screenshots | Only with the screen awake: check `ioreg -n Root -d1 -a \| grep -i CGSSessionScreenIsLocked` first; if locked, skip and say so. Demo captures wait a fixed time, so under load rerun once before calling a missing surface a defect |
| Hard limits | Never signal, stop or restart a system process or daemon (including `ANECompilerService`, `mediaanalysisd`, `tccd`); never `tccutil`; kill only a worker this session started; demos read only files they created in temporary folders. If any system prompt appears, leave it, stop that line of work and report it |
| Deleting | Only what the task created, with literal absolute paths (the rm safety check refuses `rm -rf "$VAR/..."`). Never user data |
| Public repo | No personal paths, scratch paths or private research notes in tracked files or commit messages; prior art in our own words only; records say what was not measured, not seen or deferred |

---

## 7. Exit criteria (run by `Scripts/m6-exit.sh`, task E2)

| Row | Check | Command |
|---|---|---|
| Z1 | Gates green, coverage ≥ 80 % for every gated module with a measured line for `ZivletIPC`, `ZivletWorkerCore`, `EngineVision` | `make test lint coverage app release-check licence-gate` |
| Z2 | Script tests | `make script-test` |
| Z3 | Earlier rows still pass | `Scripts/m5a-exit.sh --only X2,X3,X4,X5` and `Scripts/m5b-exit.sh --only Y4,Y5,Y7` |
| Z4 | The Release bundle has `Contents/XPCServices/ZivletWorker.xpc`, hardened runtime, signed, identifier `app.zivlet.Zivlet.Worker`, **no entitlements**, dependencies only in the OS or the bundle | `make release-check` output + `codesign -d --entitlements - --xml` on the worker |
| Z5 | Worker smoke: a PNG → JPEG job runs in a worker whose PID is not the app's; cancel visible ≤ 100 ms; a self-killed worker → the job retried once and succeeds; a job that kills it twice → "This file made the engine crash" and the next job of the batch succeeds; idle exit after the configured time; no crash report written | `make worker-smoke` |
| Z6 | OCR fixtures: 12/12 ≤ 1 % CER with the production configuration; every Devanagari golden returns Devanagari; first recognition after warm-up ≤ 3 s; per-fixture CER and time printed | `make ocr-check` |
| Z7 | Copy Text through the drop path: an image and a mixed PDF, clipboard text within 1 % CER of the golden; ⌥ writes `X Text.txt` (UTF-8, no BOM, LF); "No text found" for a blank image | `make copy-text-demo` |
| Z8 | Box follow-ups: a DEBUG Move of 50 temporary files cancelled part-way leaves a partial result whose Undo moves the moved part back; the busy overlay screenshot shows a fraction | `make box-busy-demo` |
| Z9 | Every new state on screen (text card at the notch and near the drop, Show all window, the setting, box busy), contrast ≥ 4.5:1 over white | `make text-states` and `make box-states` |
| Z10 | No `tccd` request with `preflight=no` for Zivlet or its worker while Z5–Z9 ran (D-M5a-5) | log scan in `m6-exit.sh` |
| Z11 | Hygiene since `9cc6c69`: signed off, no `Co-Authored-By`, no file ≥ 800 lines, no personal path, no `print(` in `Sources/`, no `NSAlert` in new code, `import Vision` only in `EngineVision`, the worker's entitlements empty, the cap lint's counts printed | `m6-exit.sh` |

Owner rows (not automated) are in `docs/plan/qa/copy-text.md` and `docs/plan/qa/worker.md` (E1).

---

## 8. Owner steps and open points

| ID | Step | Why / blocks |
|---|---|---|
| OS-M6-1 | With the Developer ID (O-1), build Release, run `make worker-smoke CONFIG=release`, and check that the team requirement path is taken | D-M6-7: only ad-hoc was prototyped |
| OS-M6-2 | Run P2-190 on a Mac or VM with macOS 26.x: is `hi-IN` listed, do the 12 fixtures pass, cold compile time, does warm-up remove it | This Mac runs 27.0; OWN-OCR-1 hides Hindi if 26.x lacks it |
| OS-M6-3 | Make two Hindi PDFs from your own words, one in Word and one in Chrome (print to PDF), and put them in a private fixture folder for `make ocr-check PDFS=<folder>` | P2-104's Word/Chrome fixtures; Word and Chrome are not on the build Mac |
| OS-M6-4 | Real Hindi scans and phone photos (receipts, signs, forms), private, not committed (OWN-QA-1, P2-191) | Rendered fixtures do not measure real scans |
| OS-M6-5 | Copy Text and one conversion on files in Desktop, Documents and Downloads with the worker on: no permission prompt, or a prompt naming Zivlet (not the worker) | Hard limits forbid automation there; TCC attribution untested |
| OS-M6-6 | Reduce Motion exit of the Drop Box: keep D-BL12's 0.18 s fade (planned) or make it instant | The brief and D-BL12 differ (D-M6-3) |
| OS-M6-7 | Look review of the text card, the Show all window and the setting row | OWN-UI-1 |
| OS-M6-8 | VoiceOver on the text card and Show all window (`qa/copy-text.md`) | Not automatable here |
| OS-M6-9 | After E4's size measurement: keep the engines linked twice (app fallback + worker) or plan the shared `ZivletEngines` framework (spike P-PKG) | Size budget (OWN-SIZE-1) |
| OS-M6-10 | Merge and push `m6` when satisfied | Owner only |

---

## 9. Risks

| ID | Risk | Mitigation |
|---|---|---|
| R1 | Vision's cold compile takes minutes (118 s, 99 s, 148 s measured at load 16–60) and repeats per configuration and input-size bucket | Warm-up of exactly the production configuration and three sizes (D-M6-16); "Preparing…" state; a job never times out; real-Vision tests opt-in (D-M6-13) |
| R2 | launchd delays a relaunch by ~10 s after repeated crashes | The retry waits; Cancel still works (it is the app's task); the working line stays; the smoke row records the relaunch time |
| R3 | Ad-hoc builds can only check the signing identifier, which any ad-hoc binary can claim | Developer ID builds use the team requirement; release gates already require a Developer ID for distribution (`verify-signatures.sh --require-developer-id`) |
| R4 | Swift XPC types are not `Sendable`; warnings are errors | Keep XPC in two small files (`Worker/main.swift`, `XPCSessionFactory.swift`) with `@preconcurrency import XPC`; everything else talks to Sendable ports |
| R5 | App size: the engines are linked into both the app (fallback) and the worker | E4 measures with `Scripts/size-gate.sh`; OS-M6-9 |
| R6 | TCC: the worker's reads of protected folders are untested | OS-M6-5; Z10 scans the log on every exit run |
| R7 | XPC glue cannot run in `swift test` (no bundle), so coverage misses it | Glue kept thin behind `WorkerTransport`; Z5 exercises the real worker |
| R8 | Timing tests flake under load (`SubprocessRunner` 0.41 s seen in the baseline, the 50 ms HUD test in M5a/M5b) | Rerun once by name; G-M6-9 investigates the race |
| R9 | Vision on macOS 26.x may differ from 27.0 | OS-M6-2; the capability probe hides Hindi (OWN-OCR-1) |
| R10 | Fixtures tuned to pass | D-M6-11: parameters fixed before D4; stress set unscored; real scans by the owner |
| R11 | Moving Trash off the main actor races with edits to the box | The trasher returns results; the controller applies them to the *current* library by id (items removed meanwhile are skipped) |

---

## 10. Gaps recorded up front

| ID | Gap | Next step |
|---|---|---|
| G-M6-1 | EngineMedia stays in-process (D-M6-5) | A later task moves it with PID events and orphan reaping across XPC |
| G-M6-2 | Read QR (P2-51 tool) not built (D-M6-6) | With P2-30 |
| G-M6-3 | History (P2-145) absent; only "nothing stores the text" is tested | With P2-145 |
| G-M6-4 | Hindi on macOS 26.x unverified | OS-M6-2 |
| G-M6-5 | Word- and Chrome-made Hindi PDFs not in the fixtures | OS-M6-3 |
| G-M6-6 | Real scans not measured (P2-191) | OS-M6-4 |
| G-M6-7 | Whether an XPC service shares Vision's compile cache with other processes was not measured | Z6 prints the first-call time in a fresh worker after warm-up |
| G-M6-8 | The full ordered language list of 17c §1.1 is not built (D-M6-14) | After the owner uses the picker |
| G-M6-9 | `SubprocessRunnerTests.aChildIgnoringSIGINTIsKilledAfterTheGrace` failed once in the baseline at 0.41 s (too short, so not load) | A0 notes it; investigate the child's signal set-up before sending SIGINT |
