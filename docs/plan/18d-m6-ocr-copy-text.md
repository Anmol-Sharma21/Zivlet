# 18d — M6 Stream D: EngineVision base, the OCR core and Copy Text (P2-51 base, P2-103, P2-104)

Part of [18-implementation-plan-m6](18-implementation-plan-m6.md). Conventions: index §6. Behaviour:
[design/17c](../design/17c-image.md) §1; PDFs: [design/17a](../design/17a-pdf.md) §2 (finding 3 and L1) and §3.8
(usable-text rule); decisions OWN-OCR-1, OWN-PDF-5, OWN-QA-1 in [00-decisions](../design/00-decisions.md). Prototype:
index §3.2–§3.3. Decisions: D-M6-6, D-M6-8, D-M6-11 … D-M6-16. Look: OWN-UI-1, 19b. Swift below is
specification-grade and was not compiled.

Flow of one Copy Text drop: wheel slice `tools.copyText` → `ToolWiring` → `TextService` (app, `ZivletRuntime`,
its own `vision` lane) → `WorkerConnection` → worker `recognizeText` → `EngineVision.TextReader` (per image: Vision
documents request; per PDF page: PDFKit text layer or render + Vision) → `RecognizedText` back → clipboard (and with
⌥ one `.txt` per input through the `Publisher`) → `ActionResult.text(…)` to the HUD or the island.

New strings (*new*, Zivlet's own): slice "COPY TEXT"; toast "Text copied"; card line "342 characters · Hindi and
English"; buttons "Copy Again", "Save as Text", "Show All"; "No text found"; "Preparing text recognition (one time)…";
"Text recognition isn't available right now."; "This PDF doesn't allow copying its text."; "This PDF is locked.";
setting "Text recognition" with "Match my languages", "Hindi and English", "English"; Show All window title
"Text from photo.png" / "Text from 3 files".

---

## How the 12 Hindi + English fixtures are made and measured

| Item | Rule |
|---|---|
| Source of the text | Sentences written for Zivlet for this plan (below). No quotation from books, sites, signs or scans |
| Fonts | Fonts that ship with macOS, by PostScript name: `HelveticaNeue`, `KohinoorDevanagari-Regular`, `DevanagariSangamMN`, `ITFDevanagari-Book`. The renderer fails the test (not falls back) if CoreText returns another font |
| Rendering | At test time (D-M6-11) into a temporary folder: CoreText frame into an sRGB bitmap, black on white (one white on `#1F2129`), 40 px margin, the size in the table. Nothing is committed but the manifest |
| Degradation (fixture 07 only) | Rotate 3° about the centre on white, Gaussian blur σ 0.9 (5-tap separable), seeded uniform noise ±4 % (LCG seed `0x5EED`), JPEG quality 0.35. Fixed now, not tuned later |
| Ground truth | The manifest's `text`, exactly |
| CER | Levenshtein distance over Unicode scalars ÷ reference scalar count, after NFC and collapsing whitespace runs to one space (D-M6-12). Pass: ≤ 0.01 per fixture; the row needs 12/12 |
| Devanagari check | A fixture whose truth has a scalar in U+0900–U+097F fails if the output has none (P2-104) |
| Configuration | The production one: documents request, languages `[hi, en]`, auto-detect off, language correction on |
| Where it runs | `make ocr-check` (env `ZIVLET_OCR_FIXTURES=1`), exit row Z6; not in `make test` (D-M6-13) |
| Stress set | The same sentence as 07 at noise ±10/20/30/45 % and 16/22 px, printed with its CER, never scored (prototype: errors start at ±20 %) |

| # | Name | Font, size | Text |
|---|---|---|---|
| 01 | english | Helvetica Neue 36 | The quarterly report is due on Friday. / Please send your notes by 5 pm. |
| 02 | roman_hinglish | Helvetica Neue 36 | Aaj shaam ko market chalenge, tum bhi aa jao. / Bus 6 baje nikalti hai. |
| 03 | hindi_kohinoor | Kohinoor Devanagari 36 | आज मौसम बहुत अच्छा है। / हम शाम को पार्क में टहलने जाएँगे। |
| 04 | hindi_sangam | Devanagari Sangam MN 36 | किताबें मेज़ पर रखी हैं। / कृपया उन्हें अलमारी में रख दीजिए। |
| 05 | mixed | Kohinoor Devanagari 36 | Train का टिकट book कर दिया है, / platform नंबर 4 पर मिलना। |
| 06 | mixed_dark_small | Kohinoor Devanagari 17, white on dark | Office की WiFi आज बंद है, hotspot use करें। |
| 07 | mixed_degraded | ITF Devanagari 30, degraded | Doctor ने कहा है कि रोज़ 30 मिनट walk करो। |
| 08 | short_mixed | Kohinoor Devanagari 36 | शाम 7 बजे call |
| 09 | one_hindi_word | Kohinoor Devanagari 36 | Please carry your पहचान card to the office. |
| 10 | mostly_english | Kohinoor Devanagari 32 | Lunch is at noon. / The meeting moved to room B. / बैठक के बाद चाय मिलेगी। / Bring your laptop charger. |
| 11 | hindi_numbers | Kohinoor Devanagari 36 | कुल बिल: ₹2,340.50 (कर सहित) |
| 12 | devanagari_digits | Kohinoor Devanagari 36 | दिनांक: १५ मार्च २०२६, राशि ₹४५० |

"/" is a line break. Prototype result with these exact parameters: 12/12 at CER 0.000 (index §3.2).

PDF fixtures (also rendered at test time): English, Hindi and mixed text drawn with CoreText into a PDF context (the
text layer of the Hindi ones extracts in visual order, CER 0.054 in the prototype, so they must go through OCR); an
image-only "scan" page of fixture 05; a WebKit-made PDF of the Hindi sentence (`WKWebView.pdf(configuration:)`, a
stand-in for Chrome); a PDF with copying disallowed (PDFKit write with `kCGPDFContextAllowsCopying = false`). Word
and Chrome files come from the owner (OS-M6-3) and are read from a private folder only when `PDFS=<folder>` is set.

---

## Task D1 — `OCRTestSupport`: the CER tool and the fixture renderer

| Field | Value |
|---|---|
| Goal | Test-support target `OCRTestSupport` (strict): `CharacterErrorRate.cer(reference:hypothesis:)`, `Devanagari.contains(_:)`, `OCRFixtures.manifest` (decoded and validated from `Tests/OCRTestSupport/Resources/ocr-fixtures.json`: unique names, non-empty text, known fonts, size 8…96), `OCRFixtures.render(into:)` (images as above, fails on font fallback), `OCRFixtures.renderPDFs(into:)` |
| Acceptance | CER unit tests: identical → 0; one substitution in 10 scalars → 0.1; NFC vs NFD of "ज़" → 0; whitespace runs and newlines collapse; empty reference with empty hypothesis → 0, with text → 1; insertion past the end counts. Renderer: 12 files with the manifest's names; fixture 07 is byte-identical across two renders (deterministic seed); a manifest with an unknown font fails validation with its name |
| Effort | S |

**Files:** `Package.swift` (target `OCRTestSupport` with resources), create `Tests/OCRTestSupport/CharacterErrorRate.swift`,
`OCRFixtures.swift`, `FixtureDegrader.swift`, `Resources/ocr-fixtures.json`; tests
`Tests/EngineVisionTests/CharacterErrorRateTests.swift`, `OCRFixtureRenderTests.swift` (in the D2 test target).

```swift
@Test func canonicalEquivalentsCostNothing() {
    #expect(CharacterErrorRate.cer(reference: "रोज़", hypothesis: "रोज\u{093C}") == 0)
}
@Test func theDegradedFixtureIsDeterministic() throws {
    let a = try TempDir(), b = try TempDir()
    try OCRFixtures.render(into: a.url); try OCRFixtures.render(into: b.url)
    #expect(try Data(contentsOf: a.file("07_mixed_degraded.jpg")) == Data(contentsOf: b.file("07_mixed_degraded.jpg")))
}
```

RED: `cannot find 'CharacterErrorRate' in scope`. Commit `test(vision): a CER tool and 12 rendered Hindi and English
fixtures`.

---

## Task D2 — `EngineVision` module and language defaults

| Field | Value |
|---|---|
| Goal | Target `EngineVision` (strict; Foundation, Vision, PDFKit, ImageIO, CoreGraphics; depends on `ZivletCore`, `ZivletEngineKit`), added to `GATED_MODULES`; `EngineID.vision`. Pure `RecognitionLanguages.defaults(preferred: [String], inputSources: [String], choice: TextLanguageChoice, capabilities:) -> [LanguageTag]`: `.matchMine` → `[hi, en]` when any preferred language's code is `hi` or `mr` or an enabled input source is a Hindi/Devanagari layout, else `[en]`; `.hindiAndEnglish` → `[hi, en]`; `.english` → `[en]`; Hindi is dropped when the capability probe lacks it (OWN-OCR-1). `LanguageTag` is a small Codable value (`code`, `script`) mapped to `Locale.Language` only inside the recognizer. Auto-detect is never set (P2-103) |
| Acceptance | table: `["en-IN","hi-IN"]` → `[hi,en]`; `["en-US"]` → `[en]`; `["mr-IN"]` → `[hi,en]`; `["en-GB"]` + input source `com.apple.keylayout.Devanagari-QWERTY` → `[hi,en]`; `.hindiAndEnglish` without Hindi capability → `[en]`; English is always last when Hindi is first |
| Effort | S |

**Files:** `Package.swift` (targets `EngineVision`, `EngineVisionTests` depending on `OCRTestSupport`), create
`Sources/EngineVision/RecognitionLanguages.swift`, `LanguageTag.swift`; modify
`Sources/ZivletCore/Jobs/JobIdentity.swift`, `Scripts/coverage.sh`; tests `Tests/EngineVisionTests/RecognitionLanguagesTests.swift`.

RED: `no such module 'EngineVision'`. Commit `feat(vision): an EngineVision module that picks Hindi first for Hindi
users`.

---

## Task D3 — Capability probe

| Field | Value |
|---|---|
| Goal | `VisionCapabilities.probe(source:) -> VisionCapabilities { languages: [LanguageTag], hasHindi: Bool, osBuild: String }` behind a `VisionLanguageSource` port (production: `RecognizeDocumentsRequest().supportedRecognitionLanguages`). Hindi is present when any language has `languageCode == "hi"` (the Swift API reports `hi-Deva-IN`, prototype §3.2). Cached per process |
| Acceptance | fake sources: with `hi-Deva-IN` → `hasHindi`; without → not, and `RecognitionLanguages` drops Hindi; real source on this Mac (opt-in suite) lists `hi` and `mr` (macOS 27.0: 33 languages); the probe never runs a recognition (no compile) |
| Effort | S |

**Files:** create `Sources/EngineVision/VisionCapabilities.swift`; tests `Tests/EngineVisionTests/VisionCapabilitiesTests.swift`.

RED: `cannot find 'VisionCapabilities' in scope`. Commit `feat(vision): probe the recognition languages and hide
Hindi where it is missing`.

---

## Task D4 — `TextRecognizer`

| Field | Value |
|---|---|
| Goal | `protocol TextRecognizing: Sendable { func recognize(_ image: CGImage, languages: [LanguageTag]) async throws(TextError) -> RecognizedPage }`. `VisionTextRecognizer`: `RecognizeDocumentsRequest` with `recognitionLanguages` in order, `automaticallyDetectLanguage = false`, `useLanguageCorrection = true`; output = paragraphs' transcripts joined with `\n` (tables: cells joined with tabs, rows with `\n`). If the documents request throws, one fallback to `RecognizeTextRequest` with `.accurate` and the same languages, lines joined with `\n` (P2-103's [challenge]). Cancellation: checked before each request and after it returns (Vision calls are not interruptible). `RecognizedPage { text, scripts: Set<Script> }` where `Script` is `.devanagari`, `.latin`, `.other` from the output's scalars |
| Acceptance | unit (fake Vision adapter): language order passed through; auto-detect false; the fallback runs once on a documents failure and its error is returned if it also fails; scripts derived. Opt-in `OCRFixtureTests` (Z6): the 12 fixtures through `VisionTextRecognizer` → 12/12 CER ≤ 0.01, no Devanagari miss, per-fixture CER and ms printed; with `[en]` only the Devanagari fixtures are *expected* to miss (documents the language-order trap, 17c §1.4) |
| Effort | M |

**Files:** create `Sources/EngineVision/TextRecognizer.swift`, `VisionTextRecognizer.swift`, `RecognizedPage.swift`,
`TextError.swift`; tests `Tests/EngineVisionTests/TextRecognizerTests.swift`, `OCRFixtureTests.swift`
(`.enabled(if: ProcessInfo.processInfo.environment["ZIVLET_OCR_FIXTURES"] == "1")`); `Makefile` target `ocr-check`
(`ZIVLET_OCR_FIXTURES=1 swift test --filter OCRFixtureTests`, with `PDFS=` passed through).

```swift
@Test(.enabled(if: OCRFixtures.realVisionEnabled), arguments: OCRFixtures.manifest.entries)
func everyFixtureIsReadWithinOnePercent(_ entry: OCRFixtures.Entry) async throws {
    let image = try OCRFixtures.image(for: entry)
    let page = try await VisionTextRecognizer().recognize(image, languages: [.hindi, .english])
    let cer = CharacterErrorRate.cer(reference: entry.text, hypothesis: page.text)
    OCRFixtures.report(entry, cer: cer)
    #expect(cer <= 0.01, "\(entry.name): \(page.text)")
    if Devanagari.contains(entry.text) { #expect(Devanagari.contains(page.text), "\(entry.name) lost its Devanagari") }
}
```

RED: `cannot find 'VisionTextRecognizer' in scope`. Commit `feat(vision): recognise text with the documents request,
Hindi first, accurate fallback`.

---

## Task D5 — PDF pages: text layer first, OCR when needed

| Field | Value |
|---|---|
| Goal | `PDFTextSource.read(_ url:, recognizer:, languages:, progress:) async throws(TextError) -> [RecognizedPage]`. Refuse a locked document (`isLocked` → `.pdfLocked`) and one that disallows copying (`allowsCopying == false` → `.copyingNotAllowed`, OWN-PDF-5). Per page (D-M6-15): `page.string` is used when `UsableText.isUsable` (≥ 20 printable scalars, < 5 % U+FFFD; 17a §3.8) **and** it has no Devanagari; otherwise render the crop box at 300 DPI (white behind, rotation honoured, longest side capped at 8192 px and 16 MP like P2-12) and recognise. Cancellation between pages; progress = pages done ÷ pages. Page cap 500 (validated in C2) |
| Acceptance | rendered PDF fixtures: English text layer used (no recognizer call, CER 0); Hindi and mixed CoreText PDFs go to the recognizer although their layer is "usable" (fake recognizer records the call); the scan page goes to the recognizer; the WebKit PDF goes to the recognizer (Devanagari); copying disallowed → `.copyingNotAllowed`; cancel after page 2 of 5 → `.cancelled` and 2 recognizer calls; opt-in: the Hindi/mixed/scan PDFs reach CER ≤ 0.01 with real Vision; with `PDFS=<folder>` every owner PDF is printed with its CER (no threshold: the owner judges, OS-M6-3) |
| Effort | M |

**Files:** create `Sources/EngineVision/PDFTextSource.swift`, `UsableText.swift`, `PageRenderer.swift`; tests
`Tests/EngineVisionTests/PDFTextSourceTests.swift`, `UsableTextTests.swift`, extend `OCRFixtureTests.swift`.

RED: `cannot find 'PDFTextSource' in scope`. Commit `feat(vision): read PDF text from the layer, or by OCR when it is
missing or Devanagari`.

---

## Task D6 — Assembly and the script summary

| Field | Value |
|---|---|
| Goal | Pure `TextAssembly.combine(_ files: [(name: String, pages: [RecognizedPage])]) -> RecognizedText`: one file → its pages joined by a blank line; several → each block headed `— name —` (em dashes, the file's display name) and separated by a blank line; LF only; no trailing spaces; one final newline. `RecognizedText { text, characterCount (grapheme clusters, excluding the separators), scripts, preview: [String] (first 3 non-empty lines, each ≤ 80 characters with "…"), perFile }`. `ScriptSummary.line(_:)` → "Hindi and English", "English", "Hindi", "Hindi, English and other scripts" (Devanagari is called Hindi in the UI; a Marathi user sees the same word, recorded as a known simplification) |
| Acceptance | tables for one file, three files, a file with no text inside a multi-file drop (its block says nothing and is omitted; the count excludes it), CRLF in a PDF layer normalised to LF, the preview's truncation, the summary line per script set |
| Effort | S |

**Files:** create `Sources/EngineVision/TextAssembly.swift`, `ScriptSummary.swift`; tests
`Tests/EngineVisionTests/TextAssemblyTests.swift`.

RED: `cannot find 'TextAssembly' in scope`. Commit `feat(vision): combine recognised text from several files with
name separators`.

---

## Task D7 — Warm-up

| Field | Value |
|---|---|
| Goal | Pure `WarmupState` (`.needed`, `.running`, `.done(osBuild:)`) with `next(osBuild:, languages:)`: needed after onboarding, again when the OS build or the language set changes. `VisionWarmup.run(recognizer:, languages:)` recognises three generated images (64 px, 1024 px, and a 2550 × 3300 page with one line of text in each script of the languages; D-M6-16) at `.utility` priority in the worker (request `warmUp`, D8). The app keeps `{osBuild, languages}` in a new versioned settings field `textRecognitionWarmed` |
| Acceptance | state table: fresh install → needed; done for build A then build B reported → needed; done and same → nothing; language choice changed → needed; a warm-up interrupted by a worker crash stays needed (retried at next launch, never in a loop within one launch). Opt-in: after warm-up, a fresh worker's first fixture recognition ≤ 3 s (P2-190's bar; printed in Z6) |
| Effort | S |

**Files:** create `Sources/EngineVision/WarmupState.swift`, `VisionWarmup.swift`; modify
`Sources/ZivletSettings/Settings.swift`, `SettingsCoding.swift` (new field, schema bump, validation); tests
`Tests/EngineVisionTests/WarmupStateTests.swift`, `Tests/ZivletSettingsTests/SettingsCodingTests.swift`.

RED: `cannot find 'WarmupState' in scope`. Commit `feat(vision): warm up text recognition once per OS build and
language set`.

---

## Task D8 — The text job in the worker; `TextService` in the app

| Field | Value |
|---|---|
| Goal | `ZivletIPC`: `TextJob { id, inputs: [URL], languages: [LanguageTag] }`, replies `text(RecognizedText)` and progress events. `WorkerService` hosts a `TextReader` (images via ImageIO with the existing decode limits from `EngineImage.PixelLimits`; PDFs via D5) and the warm-up. `ZivletRuntime.TextService` (actor): `copyText(_ urls:, languages:) async throws(TextError) -> RecognizedText` on a `vision` lane of width 1, through `WorkerConnection`; cancellation forwarded; a worker crash during a text job → one retry (same rule as C6), then "This file made the engine crash."; no worker → `.unavailable` (D-M6-8). Inputs are validated in the app first (local regular files of a supported type) and again in the worker (C2) |
| Acceptance | loopback with a fake recognizer: two images → one combined text with separators; progress from 0 to 1; cancel → `.cancelled` and the worker's job cancelled; crash once → retried and succeeds; crash twice → `.engineCrashedOnInput`; no worker → `.unavailable`; a 40000 × 40000 header → refused by the decode limit before Vision |
| Effort | M |

**Files:** modify `Sources/ZivletIPC/WorkerRequest.swift`, `WorkerReply.swift`; create
`Sources/ZivletWorkerCore/TextReader.swift`, `Sources/ZivletRuntime/TextService.swift`; modify
`Sources/ZivletWorkerCore/WorkerService.swift`, `Worker/main.swift`, `project.yml` (worker links `EngineVision`); tests
`Tests/ZivletWorkerCoreTests/TextReaderTests.swift`, `Tests/ZivletRuntimeTests/TextServiceTests.swift`.

RED: `type 'WorkerRequest' has no member 'recognizeText'`. Commit `feat(worker): recognise text in the worker and
return it to the app`.

---

## Task D9 — The COPY TEXT slice

| Field | Value |
|---|---|
| Goal | `ToolID.copyText`; spec `COPY TEXT`, symbol `text.viewfinder`, `.instant`, `.multiAllowed`, suffix `Text`, `accepts` = raster formats, GIF, AVIF, BMP and PDF (so image/PDF mixes show it, B3). Rows per 17 §8.1: listed first in the raster single and multi rows, after READ QR for AVIF/BMP/GIF, and in PDF single and multi. SVG gets no COPY TEXT (17 §8.1). `OutputNamer` gives `photo Text.txt` and `photo Text 2.txt` |
| Acceptance | `ToolCatalogTests`: PNG single starts with `.copyText` and has 8 tools; PNG multi 6; PDF single 6; GIF single `[.stripMetadata, .qrScan, .copyText]` order per the table; SVG unchanged; the cap lint (B2) prints the new counts and passes; B3's table gains the image+PDF row with `[.qrScan, .copyText]`; `OutputNamerTests` for the suffix |
| Effort | S |

**Files:** modify `Sources/ZivletCore/Catalog/ToolSpec.swift`, `ToolTable.swift`,
`Sources/ZivletCore/Naming/OutputNamer+Tools.swift`; tests `Tests/ZivletCoreTests/ToolCatalogTests.swift`,
`CombiningRuleTests.swift`, `OutputNamerTests.swift`.

RED: `type 'ToolID' has no member 'copyText'`. Commit `feat(catalog): a COPY TEXT tool for images and PDFs`.

---

## Task D10 — Clipboard and the `.txt` writer

| Field | Value |
|---|---|
| Goal | `ClipboardAction.copyText(_ text: String)` writes `.string` after `prepareForNewContents(with: .currentHostOnly)` (P2-104), through the existing pasteboard port. `TextFileWriter.write(_ text:, beside input:, namer:, publisher:) throws(JobError) -> URL`: UTF-8 without BOM, LF, written to the publisher's hidden staging file in the input's folder (or the existing fallback folder when it is read-only) and published with the exclusive rename; quarantine copied from the input like other outputs |
| Acceptance | private pasteboard: the string reads back and the option is applied (fake port records it); writer: bytes equal `text.utf8` with no BOM, `\r\n` input written as `\n`; a taken name → `photo Text 2.txt`; a read-only folder → fallback folder; staging gone after success and after a failure |
| Effort | S |

**Files:** modify `Sources/ZivletActions/ClipboardAction.swift`; create `Sources/ZivletRuntime/TextFileWriter.swift`;
tests `Tests/ZivletActionsTests/ClipboardActionTests.swift`, `Tests/ZivletRuntimeTests/TextFileWriterTests.swift`.

RED: `value of type 'ClipboardAction' has no member 'copyText'`. Commit `feat(tools): copy recognised text for this
Mac only and save it as a text file`.

---

## Task D11 — The text result: card, toast, Show All

| Field | Value |
|---|---|
| Goal | `ActionResult.text(TextOutcome)` with `TextOutcome { preview: [String], characterCount, scriptLine, savedFiles: [URL], fullText }` (the text lives only in memory for the card's lifetime). Both presenters draw it, minimal per OWN-UI-1: toast "Text copied" with the card below: up to three preview lines (secondary style, selectable off), one line "342 characters · Hindi and English", three icon buttons with labels for accessibility — `doc.on.doc` Copy Again, `square.and.arrow.down` Save as Text, `text.alignleft` Show All. Save as Text runs D10's writer; Show All opens `TextPreviewWindow`: a non-activating panel with a read-only, selectable `NSTextView`, glass background with the solid fallback for Reduce Transparency, Esc and ⌘W close it, title as above. "No text found" is `.done(toast: "No text found", undo: nil)`. Linger: the card stays 8 s, held while hovered, like other cards |
| Acceptance | view-model tests for both presenters (lines, count, buttons, accessibility labels "Copy again", "Save as text", "Show all text"); contrast of the preview and count lines ≥ 4.5:1 over white and over the dark finish (the existing contrast helpers); Show All model: title per count, text equals `fullText`; closing the card drops the text (weak reference test); `NotchHUDTimingTests` still pass |
| Effort | M |

**Files:** modify `Sources/ZivletActions/ActionResult.swift`; create `Sources/ZivletUI/HUD/TextResultContent.swift`,
`Sources/ZivletUI/Notch/NotchTextCard.swift`, `Sources/ZivletUI/HUD/TextPreviewWindow.swift`; modify
`Sources/ZivletUI/HUD/ActionContent.swift`, `Sources/ZivletUI/Notch/NotchCard.swift`, `NotchHUDCopy.swift`,
`HUDCopy.swift`; tests `Tests/ZivletUITests/TextResultTests.swift`, `TextPreviewWindowTests.swift`.

RED: `type 'ActionResult' has no member 'text'`. Commit `feat(ui): a text result card and a Show All window`.

---

## Task D12 — Tool wiring

| Field | Value |
|---|---|
| Goal | `App/ToolWiring.swift`: `AppDelegate.handle(_:near:)` routes `.tool(.copyText)` to it (other tools keep the DEBUG note). It reads the language choice and capabilities, shows the working state (the island or HUD's working line "Recognising text…", and "Preparing text recognition (one time)…" while `WarmupState` is not done; the job never times out), calls `TextService`, copies to the clipboard, with ⌥ writes one `.txt` per input (D10), and shows `ActionResult.text` or "No text found" or the error copy. After onboarding finishes, it starts the warm-up (D7) once |
| Acceptance | `make app`; DEBUG `make copy-text-demo` (D15) passes; unit tests for a `ToolWiringModel` (pure): the right working line per warm-up state, ⌥ → write, errors → copy |
| Effort | S |

**Files:** create `App/ToolWiring.swift`, `Packages/ZivletKit/Sources/ZivletUI/Tools/ToolWiringModel.swift`; modify
`App/AppDelegate.swift`, `App/OnboardingWiring.swift`; tests `Tests/ZivletUITests/ToolWiringModelTests.swift`.

RED: `cannot find 'ToolWiringModel' in scope`. Commit `feat(app): Copy Text from the wheel`.

---

## Task D13 — The setting

| Field | Value |
|---|---|
| Goal | Settings › General gains "Text recognition" with a popup: "Match my languages" (default), "Hindi and English", "English" (D-M6-14). Hindi choices are disabled with the help text (*new*) "Hindi isn't available on this version of macOS." when the probe lacks Hindi (OWN-OCR-1). Changing it marks the warm-up needed (D7). The value is versioned and validated like the other settings |
| Acceptance | `SettingsCodingTests` (default, round trip, unknown raw value → default with a log line); `GeneralPane` model shows three choices and the disabled state; the settings demo `make settings-demo PANE=general` captures the row |
| Effort | S |

**Files:** modify `Sources/ZivletSettings/Settings.swift`, `SettingsCoding.swift`, `SettingsValidation.swift`,
`Sources/ZivletUI/Settings/GeneralPane.swift`, `SettingsModel.swift`; tests in `Tests/ZivletSettingsTests` and
`Tests/ZivletUITests`.

RED: `value of type 'Settings' has no member 'textLanguage'`. Commit `feat(settings): choose the text recognition
languages`.

---

## Task D14 — Privacy: the text is never stored

| Field | Value |
|---|---|
| Goal | The recognised text never reaches `os_log` (only counts and scripts, `privacy: .public` for numbers only), `UserDefaults`, the undo log, the status menu's recent list, diagnostics, or the worker's log. `Scripts/check-log-privacy.sh` gains a rule that fails on logging a `RecognizedText`/`fullText` value. History (P2-145) later stores "Text copied, n characters" only (G-M6-3) |
| Acceptance | a test runs a Copy Text job through loopback with a unique marker sentence, then searches the captured logger output (test log sink), the settings store's file, the undo store and the diagnostics text for the marker: none contain it; the log-privacy script's test plants a violating line and sees it fail |
| Effort | S |

**Files:** modify `Scripts/check-log-privacy.sh`, `Scripts/tests/test-check-log-privacy.sh`; create
`Tests/ZivletRuntimeTests/TextPrivacyTests.swift`.

RED: the planted line passes the privacy script. Commit `test(tools): recognised text is never logged or stored`.

---

## Task D15 — Copy Text demo (exit row Z7) and text states (Z9)

| Field | Value |
|---|---|
| Goal | DEBUG flags `-ZivletCopyTextDemo <folder>` (renders fixture 05 and the mixed PDF into `<folder>`, runs Copy Text through the drop path, once plain and once with ⌥, then on a blank image; writes the clipboard text and results as JSON lines; quits) and `-ZivletTextStates` (shows the text card at the notch and near the drop, the Show All window and the setting for capture, like `demo-notch-states.sh`). `Scripts/demo-copy-text.sh` (`make copy-text-demo`) checks CER ≤ 0.01 against the manifest with a small Swift CER helper (`Scripts/cer.swift`, the same rule as D1), the `.txt` bytes (UTF-8, no BOM, LF) and "No text found"; `Scripts/demo-text-states.sh` (`make text-states`) captures into `build/text-states/` and checks contrast with `Scripts/png-luminance.swift`. Both skip, not pass, when the screen is locked |
| Acceptance | both scripts pass on the Debug app with the screen awake; their shell tests run against canned outputs; `check-release-paths.sh` refuses both flags in Release |
| Effort | M |

**Files:** create `App/CopyTextDemo.swift`, `App/TextShots.swift`, `Scripts/demo-copy-text.sh`,
`Scripts/demo-text-states.sh`, `Scripts/cer.swift`, `Scripts/tests/test-copy-text-demo.sh`,
`Scripts/tests/test-text-states.sh`; modify `Makefile`, `Scripts/check-release-paths.sh`,
`App/AppDelegate+Demo.swift`.

RED: the shell tests fail (no scripts). Commit `test(tools): a Copy Text demo through the drop path and every text
state on screen`.

---

## Stream D checks before Stream E

`nice -n 10 make test lint coverage app release-check`; `make ocr-check` (record the first-call time: a cold compile
can take minutes, R1 — run it in the background); `make copy-text-demo`; `make text-states` with the screen awake;
`Scripts/m5a-exit.sh --only X2` and `Scripts/m5b-exit.sh --only Y5`.
