# 20e — M7 Stream D: PDF pre-flight and verify (P2-105)

Part of [20-implementation-plan-m7](20-implementation-plan-m7.md). Conventions: index §6. Decisions: D-M7-18,
D-M7-23. Gap audit: index §2.7. Design: [design/17a](../design/17a-pdf.md) D-PDF-1 to D-PDF-5, OWN-PDF-5,
[03b](03b-system-design-engines.md) (hostile input rows). Needs Stream C (C4's shim). Swift below is
specification-grade and was not compiled.

Acceptance being built (05 P2-105, FR-107). `PDFPreflight` (05 says "qpdf `--json`"; the shim's inspect gives the same
facts through the library, D-M7-18): encryption, AcroForm, signature fields, StructTreeRoot, EmbeddedFiles,
JavaScript and page count in ≤ 50 ms for a 100-page file; `PDFVerify`: qpdf `--check` on every output (the shim's
check, without the password echo, D-M7-16) and a re-open with the expected reader; any PDFKit write is rewritten
through qpdf (the qpdf-first rule, D-PDF-1/D-PDF-3). The brief adds page and size limits for hostile PDFs.

---

## Task D1 — `PDFPreflight`: what a PDF holds

| Field | Value |
|---|---|
| Goal | `PDFPreflight` (value in `ZivletEngineKit`, so the app can read the worker's answer without importing `EnginePDF`): `pageCount`, `encryption` (`.none`; `.standard(revision:, version:, streams:, strings:, files:)` with methods `rc4`, `aes128`, `aes256`, `identity`; `.publicKey` for `/Filter /Adobe.PubSec` or another non-Standard handler; `.unknown`), `permissions` (the /P bits as `PDFPermissions` option set: print low/high, modify, copy, annotate, fill forms, accessibility, assemble; `.all` when not encrypted), `opensWithoutPassword` (true for restrictions-only files: the empty user password works), `matched` (`.none`, `.user`, `.owner`, `.both` for the password given), `hasAcroForm`, `fieldCount`, `signatureFieldCount` (`/FT /Sig`), `isTagged` (`/StructTreeRoot`), `hasEmbeddedFiles` (`/Names /EmbeddedFiles` or file attachment annotations), `hasJavaScript` (`/Names /JavaScript`, `/OpenAction` with `/S /JavaScript`, any `/AA` on the catalog or pages), `isLinearized`, `pdfVersion`, `warningCount`. Built by the shim's `zv_pdf_inspect` (C4) in `EnginePDF.PDFInspector` |
| Acceptance | Fixtures made at test time (index §3.2, C4): a plain PDF (all false, 2 pages); a PDF with a live text field and a signature field made with PDFKit widget annotations then rewritten by the shim (`hasAcroForm`, `fieldCount == 2`, `signatureFieldCount == 1`); a tagged PDF (the shim adds a minimal `/StructTreeRoot` to a plain file through the QPDF object API, test-only helper); an attachment (PDFKit `PDFAnnotation` of type file attachment, or the shim adding `/EmbeddedFiles`, test-only); a JavaScript `/OpenAction` (test-only shim helper; the JS is the string `"void 0"`, never run); RC4-40, AES-128 (CoreGraphics), AES-256 R6 with and without restrictions (shim); a restrictions-only file (empty user password, CoreGraphics owner password + permissions); each fact matches. A file whose `/Encrypt` names `/Adobe.PubSec` (test-only shim helper that writes that dictionary) → `.publicKey` |
| Effort | M |

**Files:** create `Sources/ZivletEngineKit/PDFPreflight.swift`, `PDFPermissions.swift`,
`Sources/EnginePDF/PDFInspector.swift`, `Sources/CZivletPDF/zivlet_pdf_inspect.cc` (if C4 kept one file),
`Tests/EnginePDFTests/PDFInspectorTests.swift`, `Tests/EngineTestSupport/PDFFixtures+Structure.swift`,
`Sources/CZivletPDF/zivlet_pdf_testing.cc` (test-only helpers compiled only when `ZIVLET_PDF_TESTING` is defined by
the test target's settings; the release build has none).

RED: `cannot find 'PDFInspector' in scope`. Commit `feat(pdf): pre-flight reads encryption, forms, signatures, tags,
attachments, JavaScript and pages`.

---

## Task D2 — Limits for hostile PDFs (D-M7-18)

| Field | Value |
|---|---|
| Goal | `PDFLimits` (in `ZivletEngineKit`, checked first in the app's request factory from the drop's size and again in the worker): input ≤ **512 MB** (`maxInputBytes`; above → `.unsupportedInput(.tooLarge)` "This PDF is larger than 512 MB." *new*); page count ≤ **10,000** for structural tools (lock, unlock, change, pre-flight), ≤ 500 for page-rendering tools (Copy Text's existing `PDFTextSource.pageLimit`, Read QR); qpdf's own global limits set by the shim before each document: parser nesting ≤ 500, container size ≤ 1,000,000 entries for undamaged and 50,000 for damaged files, errors ≤ 1,000, stream filters ≤ 25 (qpdf 12's `qpdf::global::limits`; any hit → `.limit` → "This PDF is too complex to open safely." *new*); warnings > 100 → the file counts as damaged ("This PDF is damaged." *new*) for writes, but pre-flight still reports it; the worker's per-job watchdog (10 §7: a stuck in-process call kills and relaunches the worker) gets a PDF budget of 30 s + 1 s per 10 MB |
| Acceptance | Unit tests on `PDFLimits` (boundaries 512 MB ± 1 byte, 10,000 ± 1 pages); shim tests with generated hostile files (test-only helpers, our own bytes): 600 nested arrays → `.limit`; a stream with 30 chained `/FlateDecode` filters → `.limit`; a truncated file → damaged, with a count of warnings; a 10,001-page file (made by the shim by repeating one page object, so it stays small) → refused before any write; the watchdog value for 0, 100 and 512 MB |
| Effort | M |

**Files:** create `Sources/ZivletEngineKit/PDFLimits.swift`, `Tests/ZivletEngineKitTests/PDFLimitsTests.swift`,
`Tests/EnginePDFTests/HostilePDFTests.swift`; `Sources/CZivletPDF/zivlet_pdf.cc` (limits set per call),
`Sources/ZivletRuntime/ResourceLimits.swift` (watchdog), `Sources/ZivletIPC/WorkerRequestValidator.swift` (size).

RED: `cannot find 'PDFLimits' in scope`. Commit `feat(pdf): size, page and parser limits for hostile PDFs`.

---

## Task D3 — `PDFVerify`: every output checked twice (D-M7-23)

| Field | Value |
|---|---|
| Goal | `PDFVerify.verify(_ output:, expect: PDFExpectation, secrets:) throws(PDFEngineError)` in the worker: (1) the shim's check passes (no `--check` echo, D-M7-16) and the page count equals the input's; (2) the shim re-opens with the expected password and the expectation holds: `.locked(revision: 6, method: .aes256, ownerSeparate: Bool)` (also: the wrong password and the empty password are refused unless `opensWithoutPassword` is expected), `.unlocked` (`encryption == .none`), `.preserved(from: PDFPreflight)` (same encryption and permissions as the input), `.formsKept(fieldCount:, signatureFieldCount:)`; (3) PDFKit re-opens it in the worker (`PDFDocument(url:)`, then `unlock(withPassword:)` with the expected password): for a lock output `isLocked == true` before unlock, the right password unlocks, a wrong one does not, and `permissionsStatus` is `.owner` for the owner password and `.user` for the user password when they differ (prototype §3.2: PDFKit reports which one matched); for an unlock output `isEncrypted == false`. A non-ASCII password that qpdf accepts but PDFKit cannot use is **not** a failure: verify returns `.passedWithNote(.macCannotOpen)` (OWN-PDF-1's "check it opens on Mac" result) |
| Acceptance | Tests over E4's outputs (or, before E4, over shim-made files): each expectation passes on a right file and fails on a planted wrong one (an RC4 file where R6 is expected; an output with one page dropped; an "unlocked" file that is still encrypted; a lock output whose owner password equals the user password where they should differ); a Devanagari user password → `.passedWithNote(.macCannotOpen)` |
| Effort | M |

**Files:** create `Sources/EnginePDF/PDFVerify.swift`, `PDFExpectation.swift`, `Tests/EnginePDFTests/PDFVerifyTests.swift`.

RED: `cannot find 'PDFVerify' in scope`. Commit `feat(pdf): verify every output with qpdf and PDFKit`.

---

## Task D4 — The qpdf-first rule for PDFKit and Quartz writes

| Field | Value |
|---|---|
| Goal | `PDFRewrite.normalise(staged:)`: the shim rewrites a staged PDF (`preserve` mode, object streams kept, no linearisation) and checks it; the rule (17a D-PDF-3) applies to every PDF that PDFKit or Quartz wrote. In M7 the one such writer is the image → PDF route (`EngineImage`'s Quartz PDF context); when it runs **in the worker**, its verify step calls `normalise` before publishing (the worker has `EnginePDF`); the in-process fallback keeps today's output and says so in the record (it has no qpdf, D-M7-16). Future PDFKit writers (Organize, Compress, Merge) must call it; a lint (`Scripts/check-pdf-writes.sh` in `make lint`) fails on `PDFDocument.write(` or `dataRepresentation(` in `Sources/` outside an allow-list that names the call sites that normalise |
| Acceptance | A JPEG → PDF job through the loopback worker: the published PDF passes the shim's check, PDFKit opens it with 1 page, and its bytes differ from the Quartz output (qpdf rewrote it); the in-process path's output is unchanged (test pins it); the lint's self-test catches a planted `PDFDocument.write(` |
| Effort | S |

**Files:** create `Sources/EnginePDF/PDFRewrite.swift`, `Scripts/check-pdf-writes.sh`,
`Scripts/tests/test-check-pdf-writes.sh`; `Sources/ZivletWorkerCore/WorkerService.swift` (the image → PDF verify hook),
`Tests/ZivletWorkerCoreTests/ImageToPDFRewriteTests.swift`; `Makefile` (`lint`).

RED: `cannot find 'PDFRewrite' in scope`. Commit `feat(pdf): every Quartz-written PDF is rewritten and checked by
qpdf in the worker`.

---

## Task D5 — The pre-flight's 50 ms budget

| Field | Value |
|---|---|
| Goal | `ZivletTimingTests.PreflightTiming` (R3's target and load guard): a 100-page PDF made at test time (CoreGraphics, text on each page) is inspected 20 times; p95 ≤ **50 ms** (FR-107) is judged only below the load limit; the 10,000-page limit file's inspect time is printed (not judged) |
| Acceptance | `make timing` prints `timing: preflight 100 pages p95 … ms of 50 ms` or "not judged" |
| Effort | S |

**Files:** create `Tests/ZivletTimingTests/PreflightTiming.swift`.

RED: the test does not exist in the filter's output. Commit `test(timing): the PDF pre-flight's 50 ms budget`.

---

## Decisions of this stream (copied to index §4)

| ID | Decision |
|---|---|
| D-M7-18 | Pre-flight comes from the shim's inspect through the qpdf library (the facts of `qpdf --json` without its password echo). Limits: 512 MB input; 10,000 pages for structural tools, 500 for page-rendering tools; qpdf global limits (nesting 500, containers 1,000,000 / 50,000 damaged, errors 1,000, filters 25); > 100 warnings = damaged for writes; PDF watchdog 30 s + 1 s per 10 MB. All values are named constants with tests at their boundaries |
| D-M7-23 | Every PDF output is verified by the shim's check and re-open with the expected password (R6/AESv3, owner separate when restrictions exist, page count kept, forms kept) and by a PDFKit re-open in the worker; a non-ASCII password PDFKit cannot use gives a note on the result ("Preview on Mac can't open…"), not a failure (OWN-PDF-1) |
