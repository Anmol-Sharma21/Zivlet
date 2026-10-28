# 20b — M7 Stream A: the tool window shell (P2-30) and Read QR (P2-51 tool)

Part of [20-implementation-plan-m7](20-implementation-plan-m7.md). Conventions: index §6. Decisions: D-M7-2,
D-M7-10 to D-M7-13, D-M7-15. Prototype: index §3.3–§3.4. Gap audit: index §2.2–§2.3. Swift below is
specification-grade and was not compiled.

Acceptance being built (05 P2-30, PRD FR-63): shared chrome that opens at the wheel location; Apply/Cancel; reasons
for a disabled Apply; bipolar sliders that fill from the centre; editable timecodes; the XCUITest launch argument
`-UITestFixture <dir>`; options remembered per tool; fully keyboard operable; Apply admits a job like any drop. Read QR
(05 P2-51, the part left by D-M6-6): Vision barcode detection over every symbology Vision lists, PDF pages at 200 DPI,
a results window with Copy and Copy All, Open only for http(s) with the full URL shown, never opened by itself.

Why Read QR is in M7 (D-M7-2): plan 18 split P2-51 so that the EngineVision base came first and the tool waited only
for "P2-30's tool window" (D-M6-6, G-M6-2). EngineVision, its page renderer and the worker's Vision path exist now
(M6), so after A1–A5 nothing else blocks it.

Look (OWN-UI-1, 19b, 19c): the window is one family with the Drop Box panel. Liquid Glass (`glassEffect(.regular,
in:)`, radius 24, black scrim 0.5, dark scheme forced, 19c D-BL1); Reduce Transparency → solid `#1C1C1C`; Increase
Contrast → solid plus a 1 pt white outline at 0.5 (19b D-NL3); two text styles (13 pt semibold white, 12 pt regular
white 0.8, 19b D-NL7); SF Symbols; no title bar text and no dividers; the header is the tool's symbol, its name and
the file line. Every control has a VoiceOver label; text contrast is computed from the tokens and must be ≥ 4.5:1
(white 0.8 on `#1C1C1C` is 11.2:1; the error red `#FF453A` on `#1C1C1C` is 5.0:1; the system red on a light surface
is about 3.5:1, which is one reason the window forces the dark scheme, D-M7-10).

New strings (*new*, Zivlet's own): "Cancel", "Apply" (each tool names its own Apply, e.g. "Lock"), "Copy", "Copy All",
"Open", "No codes found", "1 code" / "n codes", "Opens in your browser", "Not a web link".

---

## Task A1 — `ToolWindowModel`: the shell's state (pure)

| Field | Value |
|---|---|
| Goal | `ToolWindowModel` (immutable struct in `ZivletUI/Tools/`): `symbol`, `title`, `fileLine` ("Report.pdf" or "3 files"), `apply: ApplyState` (`.enabled(label)` or `.disabled(label, reason: String)`), `isBusy`. Edits return new values (`with(apply:)`, `busy()`). `fileLine(names:)` follows the text card's naming ("Text from 3 files" pattern: "3 files"). A disabled Apply always has a reason; the type makes an empty reason unrepresentable (`ApplyState.disabled` takes a `DisabledReason` with a non-empty string, `init?`) |
| Acceptance | Table tests: one name → the name; three → "3 files"; `.disabled` with "" → nil reason → the initializer fails; `busy()` keeps every other field |
| Effort | S |

**Files:** create `Sources/ZivletUI/Tools/ToolWindowModel.swift`, `Tests/ZivletUITests/ToolWindowModelTests.swift`.

RED: `cannot find 'ToolWindowModel' in scope`. Commit `feat(tools): the tool window's state`.

---

## Task A2 — `ToolWindow`: the panel (D-M7-10)

| Field | Value |
|---|---|
| Goal | `ToolWindow: NSPanel`, style `[.borderless, .nonactivatingPanel]` (no title text, 19c D-BL4), `canBecomeKey == true`, `hidesOnDeactivate = false`, level `.floating`, collection behaviour `[.fullScreenAuxiliary, .moveToActiveSpace]`, hosting a SwiftUI `ToolWindowView(model:, content:)`: header, the tool's content, a footer with the disabled reason (symbol `info.circle` + 12 pt line) and the two buttons (Cancel = `.cancelAction`/Esc, Apply = `.defaultAction`/Return). `ToolWindowPlacement.frame(size:, wheelCenter:, visibleFrame:) -> CGRect` centres the window on the wheel's centre and clamps it inside the visible frame with the 8 pt margin the HUD uses; pure and table-tested. Opening does **not** activate Zivlet: the panel is made key with `makeKeyAndOrderFront` (prototype §3.3: key, focused, Secure Event Input on, the drop source still frontmost). Glass / solid / outline follow the display options and change at once (`accessibilityDisplayOptionsDidChangeNotification`, as `TextPreviewWindow` does) |
| Acceptance | Shell tests with the panel off screen (x −5000): `canBecomeKey`; Esc runs Cancel and closes; Return runs Apply when enabled and does nothing when disabled; placement table (centre, each edge, a corner, a screen smaller than the window → top-left of the visible frame); `usesGlass(reduceTransparency:increaseContrast:)` as `TextPreviewWindow`; VoiceOver labels: the window's `accessibilityLabel` is the title, Apply's label includes the disabled reason ("Lock, unavailable: Passwords don't match") |
| Effort | M |

**Files:** create `Sources/ZivletUI/Tools/ToolWindow.swift`, `ToolWindowView.swift`, `ToolWindowPlacement.swift`,
`Tests/ZivletUITests/ToolWindowTests.swift`, `ToolWindowPlacementTests.swift`.

RED: `cannot find 'ToolWindow' in scope`. Commit `feat(tools): the tool window at the wheel's place`.

---

## Task A3 — Shared controls: bipolar slider and timecode field

No M7 tool uses them (Read QR and the password sheet do not); P2-30's acceptance asks the shell to have them, and the
2B tools (Trim, Speed, Normalize, Edit) are their users. They are kept minimal: a model and a view each (D-M7-11).

| Field | Value |
|---|---|
| Goal | `BipolarValue` (range `-1…1` mapped to a tool's own range, neutral 0): `fill(for:) -> ClosedRange<Double>` returns `0…v` or `v…0`, so the track fills from the centre; keyboard steps ±0.05, ⌥ ±0.01, Home = 0. `Timecode` parses `ss`, `mm:ss`, `hh:mm:ss` with optional `.fff`, rejects negatives, minutes/seconds ≥ 60 and values past the media's duration (`Timecode.parse(_:, limit:) -> Result<Duration, TimecodeError>`), and formats back (`01:02:03.250`). Views: `BipolarSlider`, `TimecodeField` (a text field that shows the error copy under it and keeps the last valid value) |
| Acceptance | Table tests for the fill (−0.4 → −0.4…0; 0 → 0…0; 0.7 → 0…0.7), keyboard steps, parse/format round trips, each error case with its copy ("Use a time like 1:30 or 0:01:30.5" *new*, "That's after the end (2:14)" *new*) |
| Effort | S |

**Files:** create `Sources/ZivletUI/Tools/BipolarValue.swift`, `BipolarSlider.swift`, `Timecode.swift`,
`TimecodeField.swift`, `Tests/ZivletUITests/BipolarValueTests.swift`, `TimecodeTests.swift`.

RED: `cannot find 'Timecode' in scope`. Commit `feat(tools): a centre-filled slider and an editable timecode`.

---

## Task A4 — Options remembered per tool

| Field | Value |
|---|---|
| Goal | `ToolOptionsStore` (in `ZivletSettings`): `load<O: RememberedToolOptions>(_:, for: ToolID) -> O` and `save(_:, for:)`, JSON in `UserDefaults` under `tools.<toolID>.options`. `RememberedToolOptions` is a protocol for plain `Codable & Sendable & Equatable` structs; `JobSecret` (Stream B) is not `Codable`, so an options struct holding a password does not compile as one, and a password cannot be remembered by accident (P2-102) |
| Acceptance | Round trip of a sample options struct; a missing or unreadable value → the tool's defaults; no key other than `tools.<id>.options` is written (defaults domain diff in the test); B7's leak probe scans this store too |
| Effort | S |

**Files:** create `Sources/ZivletSettings/ToolOptionsStore.swift`, `Tests/ZivletSettingsTests/ToolOptionsStoreTests.swift`.

RED: `cannot find 'ToolOptionsStore' in scope`. Commit `feat(settings): tool options remembered per tool, never a
password`.

---

## Task A5 — Window tools from the wheel

| Field | Value |
|---|---|
| Goal | `ToolWindowCoordinator` (app side, `App/ToolWindowWiring.swift`): when a selection's tool needs input (Lock · Unlock in E9; later every `.editor` tool), it opens one `ToolWindow` at the wheel's centre with that tool's content and returns; Apply builds the job (or calls the tool's action) and closes the window; Cancel closes it with no job. One tool window at a time: a second window tool while one is open brings the open one forward (no stack). A single-file tool reached with several files (a stale selection) shows the reason in the HUD, never a silent no-op (PRD §5.7). The `.editor` tools that have no content yet keep today's DEBUG note (not shown in Release) |
| Acceptance | Coordinator tests with a fake window factory: a window tool opens one window at the given point; a second request while open → no new window; Apply admits exactly one job through the existing `ConversionWiring`-style submitter fake; Cancel admits none |
| Effort | M |

**Files:** create `App/ToolWindowWiring.swift`, `Sources/ZivletUI/Tools/ToolWindowCoordinator.swift`,
`Tests/ZivletUITests/ToolWindowCoordinatorTests.swift`; `App/AppDelegate.swift` (`handle(_:near:)` routes window
tools before the DEBUG fallback).

RED: `cannot find 'ToolWindowCoordinator' in scope`. Commit `feat(tools): window tools open the tool window`.

---

## Task A6 — `-UITestFixture <dir> -UITestMode tools`

| Field | Value |
|---|---|
| Goal | 04-tech-doc's launch argument, extended: with `-UITestMode tools` the app opens the wheel in keyboard mode on the files in `<dir>` (Tools mode), so an XCUITest can pick LOCK · UNLOCK by its accessibility identifier and drive the tool window without a cross-app drag. DEBUG only; the existing `-UITestFixture` result-card case is unchanged. `UITests/ToolWindowUITests.swift`: open Lock on a fixture PDF written by the test, type two different passwords → Apply disabled with the reason; matching → Apply enabled; Esc closes |
| Acceptance | `UITestFixture.mode(arguments:)` unit tests (`tools`, `convert`, missing, unknown → nil); `make app` builds; the XCUITest itself is **owner-run** (D-M4-14: it needs an Accessibility grant), listed as OS-M7-10 |
| Effort | S |

**Files:** `Sources/ZivletUI/HUD/UITestFixture.swift`, `App/AppDelegate+Demo.swift`, create
`UITests/ToolWindowUITests.swift`, `Tests/ZivletUITests/UITestFixtureTests.swift` (add cases).

RED: `type 'UITestFixture' has no member 'mode'`. Commit `test(app): a launch argument that opens the Tools wheel on
fixture files`.

---

## Task A7 — `CodeReader` in EngineVision

| Field | Value |
|---|---|
| Goal | `CodeReader.read(_ url:, pageLimit:) async throws(CodeError) -> [FoundCode]` in `EngineVision` (Vision stays imported only here, M6 hygiene rule): images through the existing `ImageTextSource` decode limits; PDFs through `PageRenderer` at **200 DPI** (`scale = 200/72`, still capped by `PageRenderer.maximumSide`/`maximumPixels`); Vision `DetectBarcodesRequest` with **every** symbology the request reports as supported on this Mac (`supportedSymbologies`), not a hard-coded list. `FoundCode {payload: String, symbology: String, page: Int?}`; duplicates (same payload and symbology on one page) kept once; order: page, then top-to-bottom. Locked PDFs → `.pdfLocked` (P2-107 adds the password path in E10). Page cap reuses `PDFTextSource.pageLimit` (500) |
| Acceptance | Fixtures made at test time by our own code: QR images from Core Image's `CIQRCodeGenerator` and `CICode128BarcodeGenerator` with payloads written for Zivlet ("https://zivlet.app/test", "Table 12", "ZIVLET-0042"); a two-page PDF drawn with CoreGraphics with one code per page; a blank image → `[]`. Each payload read back exactly. Runs only with `ZIVLET_VISION=1` like M6's real-Vision tests (D-M6-13); the dedupe/order logic is unit-tested on `FoundCode` values without Vision |
| Effort | M |

**Files:** create `Sources/EngineVision/CodeReader.swift`, `FoundCode.swift`, `CodeError.swift`,
`Tests/EngineVisionTests/CodeReaderTests.swift`, `Tests/OCRTestSupport/CodeFixtures.swift`.

RED: `cannot find 'CodeReader' in scope`. Commit `feat(vision): read QR and barcodes from images and PDF pages`.

---

## Task A8 — The worker's code job

| Field | Value |
|---|---|
| Goal | `WorkerRequest.readCodes(CodeJob)` → `WorkerReply.codes([FileCodes])` / `.codesFailed(CodeError)`; `CodeJob {id, inputs: [URL], pageLimit}` validated by `WorkerRequestValidator` (1…500 inputs, regular files, absolute paths, as text jobs); `WorkerProtocol.version` bumped (it moves to 5 if Stream B's secrets land first; the tests assert "bumped", not a number). `CodeService` in `ZivletRuntime`, as `TextService`: runs in the worker, cancel by job id, never in the app (D-M6-8) |
| Acceptance | IPC round trip of the new cases; validator refuses 0 and 501 inputs, a relative path, a folder; a loopback test runs `CodeService` with a fake reader and gets the codes; a cancel during a fake slow read ends with `.cancelled` |
| Effort | M |

**Files:** `Sources/ZivletIPC/WorkerMessages.swift`, `WorkerRequestValidator.swift`, `Envelope.swift`; create
`Sources/ZivletIPC/CodeJob.swift`, `Sources/ZivletRuntime/CodeService.swift`; `Sources/ZivletWorkerCore/WorkerService.swift`
(route), create `Sources/ZivletWorkerCore/CodeReading.swift`; tests in `ZivletIPCTests`, `ZivletRuntimeTests`,
`ZivletWorkerCoreTests`.

RED: `type 'WorkerRequest' has no member 'readCodes'`. Commit `feat(worker): read codes in the worker`.

---

## Task A9 — The results window (D-M7-13)

| Field | Value |
|---|---|
| Goal | Read QR stays `.instant` on the wheel (no window before the job). Its result opens the tool window in a **results** variant: header `qrcode.viewfinder`, "2 codes", the file line; one row per code with the payload in full (wrapped, selectable, never truncated for links), a symbology caption for non-QR codes, **Copy** per row and **Copy All** (payloads joined by newlines) as the Apply button; **Open** appears only for payloads that parse as `http`/`https` URLs with a host (`CodeLink.webURL(_:) -> URL?`), with the full URL as its accessibility hint ("Opens in your browser"); nothing is ever opened without a click. No codes → the toast "No codes found" (HUD, not a window). Copy uses the general pasteboard (the person asked to copy); `NSWorkspace.open` is behind an injected opener |
| Acceptance | `CodeLink` table: `https://a.b/c` → URL; `http://x` → URL; `HTTPS://X.Y` → URL; `javascript:…`, `file:///…`, `mailto:`, `ftp://`, `https://` (no host), text → nil. Results model: 0 codes → toast; 2 codes → window model with two rows and "2 codes"; Copy All joins with `\n`. Opener fake records a URL only after `press(.open, row:)` and never on show |
| Effort | M |

**Files:** create `Sources/ZivletUI/Tools/CodeResultsModel.swift`, `CodeResultsView.swift`, `CodeLink.swift`,
`Tests/ZivletUITests/CodeResultsTests.swift`, `CodeLinkTests.swift`.

RED: `cannot find 'CodeLink' in scope`. Commit `feat(tools): the Read QR results with Copy, Copy All and safe Open`.

---

## Task A10 — READ QR from the wheel

| Field | Value |
|---|---|
| Goal | `ToolWiring.run(.qrScan, …)` submits a `CodeJob` through `CodeService`, shows the working line (reusing Copy Text's working status and Cancel), then A9's window or toast. A locked PDF among the inputs is listed as "Needs a password" until E10 adds the prompt. The DEBUG `-ZivletQRDemo <dir>` path runs it without a drag for the demo (F3) |
| Acceptance | Wiring tests with fakes: two images with codes → one window with both files' codes grouped by file name; one image without → toast; a reader error on one file → the window plus a note row "1 file not read"; cancel → nothing shown |
| Effort | S |

**Files:** `App/ToolWiring.swift` (or a new `App/CodeWiring.swift` if `ToolWiring.swift` would pass 400 lines),
`Sources/ZivletUI/Tools/ToolWiringModel.swift`, tests in `ZivletUITests`.

RED: wiring test fails (`qrScan` still falls through to the DEBUG note). Commit `feat(tools): READ QR reads codes
from the wheel`.

---

## Decisions of this stream (copied to index §4)

| ID | Decision |
|---|---|
| D-M7-2 | Read QR is built in M7: it waited only for the tool window and EngineVision (D-M6-6), and EngineVision exists |
| D-M7-10 | The tool window is a borderless non-activating `NSPanel` that becomes key without activating Zivlet (prototype §3.3), in the Drop Box's finish (glass, radius 24, scrim 0.5, dark forced; solid and outline fallbacks); it opens centred on the wheel and clamped to the screen. This differs from PRD §5.7's "app activated" (OS-M7-2): activation on macOS 14+ is cooperative and would leave the drop source frontmost anyway |
| D-M7-11 | The bipolar slider and timecode field are built now as models plus minimal views because P2-30's acceptance names them; their first users are 2B tools |
| D-M7-12 | `-UITestFixture <dir> -UITestMode tools -UITestTool <toolID>` runs the named tool on fixture files through the drop path (planned as the Tools wheel in keyboard mode, which does not exist; see the execution notes); the XCUITest stays owner-run |
| D-M7-13 | Read QR stays an instant slice; its results open the tool window's results variant; Open only for http(s) URLs with a host, shown in full, never automatic; no codes → a toast |
| D-M7-15 | Password entry is the tool window's content, not an AppKit sheet attached to another window: a drop has no window to attach to. During a running batch (P2-107) the prompt opens as a tool window at the HUD's or the island's place |

---

## Execution notes (stream A, done on `m7`)

Facts for the record (F4). Commits: A1 `0ae81bd`, A2 `d528e99`, A3 `05468d1`, A4 `7a09962`, A5 `ee101d3`, A6
`74b5dbf`, A7 `d47da18`, A8 `fc53159`, A9 `d82bf8a`, A10 `7178823`. Every task's test was run and seen to fail first
(a missing type), except `ToolWindowTests.aForcedFinishWinsOverTheSystemsUntilItIsCleared`, written with the DEBUG
finish override it checks (A10).

**Baseline.** `make test` on `3483d2b`: 2096 tests, all passing, load about 7.

**Deviations from the tasks above:**

- **A2.** The window keeps the HUD's real margin, 12 pt (`HUDLayout.margin`); the task said 8. Apply has no accent
  fill: a glass button with a semibold label, because white on the system blue falls under 4.5:1 and the island's
  ink has no accent (19b D-NL11).
- **A3.** A lone seconds field may be 60 or more ("90" is 90 s); after a minutes field, seconds stay below 60.
- **A5.** The refusal for a single-file tool reached with several files says "This tool works on one file at a
  time" (*new*). No tool has window content yet, so in the app every editor tool still reaches the DEBUG note; the
  coordinator is exercised by its tests and by Read QR's results.
- **A6 (D-M7-12 changed).** The wheel has no keyboard selection to drive, so `-UITestMode tools` takes
  `-UITestTool <toolID>` and runs that tool on the folder's files through the drop path. The new cases live in a new
  `UITestFixtureTests.swift` (the old suite sits in `ResultCardTests.swift`). `UITests/ToolWindowUITests.swift` drives
  Read QR (there is no Lock window before E9) and landed with A10, which it needs. It compiles
  (`xcodebuild build-for-testing`) and was **not run** (owner-run, OS-M7-10).
- **A7.** The real-Vision cases use M6's flag (`ZIVLET_OCR_FIXTURES=1`, `make ocr-check`), not a new one; run once
  here, 3 of 3 passed (QR and Code 128 payloads, a two-page PDF, a blank image). A PDF that refuses copying is not
  refused for codes: OWN-PDF-5 is about its text. **ImageIO does not decode SVG**, which the READ QR slice accepts, so an
  SVG comes back as "This file couldn't be read" (G-M7-12).
- **A8.** Protocol version 4. `FileCodes` moved to `EngineVision` beside `FoundCode` in A9, so the UI needs no IPC
  import.
- **A9.** The shell's model gained `cancelLabel` ("Close" for results). Copy All copies and closes the window. Open
  sits before Copy, so Copy keeps one column on every row. The notes are the count line with the info symbol, then one
  line per file.
- **A10.** `App/CodeWiring.swift` holds the side effects, `CodeToolModel` (in `ToolWiringModel.swift`) the pure part.
  New results replace earlier results but never another tool's open window; the codes are then announced as a toast
  ("2 codes found. Close the tool window to see them", *new*). DEBUG: `-ZivletQRDemo <dir>` copies to a private
  pasteboard; `-ZivletIslandFinish glass|solid|contrast` also forces the tool window's finish; the app logs
  `Tool window shown: <tool or results> window <number>` (category `actions`) for captures.

**Seen in the Debug app** (screen awake, load 4–10): READ QR on our own Core Image codes through the drop path with
`-ZivletQRDemo`: two files (a QR link with Open and Copy, a Code 128 with its caption, grouped by file), one code,
a QR beside a locked PDF (note "Locked.pdf: Needs a password"), glass, solid and Increase Contrast finishes, and a
blank image (no window; the log line counted 1 file, 0 codes). The frontmost app was the same before and after the
window opened (`lsappinfo front`). Captures stayed in the session's scratch folder (not tracked). The first captures
of the one-code window (glass, solid, contrast, at load about 20) showed the payload's line above the centre of its
Copy button; three recaptures at load about 7 showed them centred, and the same view drawn off screen was centred, so
this was a capture taken mid-layout, not counted as a defect (the capture waits a fixed 1.5 s after the log line).

**Gates after stream A (`nice -n 10`; load 1m).** `make test` on `7178823`: 2187 tests in 22 bundles (2096 at the
baseline), all passing, load 5–10. `make lint`, `make coverage` (every gated module ≥ 80 %; ZivletUI 93 %, EngineVision
86 %, the lowest), `make app`, `make release-check` (size OK), `make licence-gate` (13 components) and
`make script-test` (35 scripts) passed on `7178823` at load 4–10, and again inside the exit runners.

| Runner | Result |
|---|---|
| `Scripts/m5a-exit.sh` (load 11 → 4) | X1–X5 and X7 pass (X2: warm drops p95 4.2 ms, the app's drop 19.0 ms of 50, judged at load 2.73). X6 fails on idle CPU (`indeterminate` 1.3 %, `fast-progress` 1.9 % over a 1 % limit): G-M5a-1, not worked on |
| `Scripts/m5b-exit.sh` (load 4 → 197) | Y2–Y9 pass (Y8 ran for about three hours while the session was away, then passed). Y1 failed twice: first `WorkerServiceTests.theSmokeRequestsReachTheirHooks` (a task-order race, fixed in `d27555b`), then `BoxPanelTests.aRealClickOnItsContentMakesItKey` with the screen locked (skipped while locked since `f092c3b`). Y1 rerun on `f092c3b`: pass (load 11–19) |
| `Scripts/m6-exit.sh` (load 197 → 4) | Z2, Z4–Z6, Z10, Z11 pass. Z1 failed on the locked-screen click test, rerun on `f092c3b`: pass. Z3 not judged (load above 3); its rows had passed earlier in this run (m5a X2–X5 at load 2.73, m5b Y3–Y5, Y7). Z7–Z9 skipped: the screen was locked from the end of Y8 to the end of this stream |
| `Scripts/m7-exit.sh` | not yet written (stream F, F2) |

The two test fixes are outside stream A's tasks (both tests are from M5b and M6) but blocked its gates.
`theSmokeRequestsReachTheirHooks` expected the last recorded idle sleep to be the 5 s one; each idle arm starts its
sleep in its own task, so the order is not fixed, and the test now checks the set of sleeps. The click test needs the
window server to give key focus, which it gives no window while the screen is locked; it is skipped then, with that
reason, and runs unchanged with the screen awake (G-M7-14).

**Not seen or not measured:** VoiceOver, real typing and focus order in the window (OS-M7-6, G-M7-4); the "No codes
found" toast on screen; the shell's disabled-reason state, the bipolar slider and the timecode field on screen (no
tool uses them before E9 and the 2B tools, G-M7-13); the XCUITest run (OS-M7-10).
