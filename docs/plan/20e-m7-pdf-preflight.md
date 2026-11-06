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
| D-M7-36 | Pre-flight answers for a file it cannot open: a locked file with no password (or an empty one) and a file whose handler cannot be read give a `PDFPreflight` that is "shut" (`isShut`), with the encryption, permissions and version known and the rest 0 or false. A wrong password still throws. E9 picks Lock or Unlock from this (added in execution) |
| D-M7-37 | Structure and hostile test PDFs are typed through `PDFFixtures.raw`, not a test-only `ZIVLET_PDF_TESTING` C++ file: SwiftPM builds a target once, so a test target's define never reaches `CZivletPDF` (added in execution) |
| D-M7-38 | Widgets on pages count as fields when the catalog has no `/AcroForm`: PDFKit writes forms that way on this SDK, and viewers show them as live. `hasAcroForm` still says what the catalog says (added in execution) |
| D-M7-39 | 512 MB is 512,000,000 bytes, as Finder counts, so the refusal's words match what a person sees (added in execution) |
| D-M7-40 | `PDFWatchdog` is the per-job watchdog 10 §8.3 describes, which did not exist: a qpdf step past its budget stops the worker with SIGKILL, and the app's crash rule retries once and then blames the file. Steps take turns and a budget starts when the turn comes, because qpdf runs one call at a time (D-M7-32). It lives in `EnginePDF`, as the worker does not link `ZivletRuntime` (added in execution) |
| D-M7-41 | The qpdf-first rewrite is the last step of `execute`, in a wrapper engine (`PDFRewritingEngine`), not in `verify`: verify then judges the published bytes, and the app gets the final size. `ZivletWorkerCore` is in the app's product and must not link qpdf, so `WorkerService` has no hook (added in execution) |
| D-M7-42 | `JobSecret`'s lock is recursive: one secret may be both user and owner (D-M7-20), and a caller lends both together (added in execution) |
| D-M7-43 | A limit outranks what qpdf did next: the shim reports `ZV_PDF_LIMIT` when qpdf counted a limit error, whether the call then succeeded or ended in damage (added in execution) |
| D-M7-44 | While a qpdf step runs, the worker's footprint may not pass 3 GB: `PDFWatchdog` reads it every 100 ms, and past that the step counts as stuck, the same way out as its time budget. It stands behind D-M7-18, whose limits do not hold memory: qpdf 12.4.2 does not count numbers, nulls or references towards a container, and nothing limits what a Flate stream inflates to. The ceiling is on the whole process, not a step's growth, because malloc keeps what an earlier step freed and that would hide a later step's memory; another job's memory counts too, which at worst costs one retry (added in execution, attempt 2) |
| D-M7-45 | No per-stream decode limit (`qpdf_p_flate_max_memory` and its kin): the ceiling already holds the memory, an honest large stream passes through the check to nowhere and must stay readable, and that limit raises no limit error, so the file would say "damaged" (added in execution, attempt 2) |

---

## Execution notes (stream D on `m7`, 2026-10-31 to 11-01)

Commits: D1 `22b56e4`, D2 `06967d8`, the secret fix `770ce0f`, D3 `91b5df7`, D4 `e2bf319`, D5 `5aaea0d`, a comment
`9c6931d`. `make test` on `ed489f0` was green before any of them: 2301 tests, 23 bundles.

**Two defects found by this stream's tests, in code that was already committed.**

- **A secret in both roles hung (`770ce0f`, D-M7-42).** Lock without restrictions uses the user password as the owner
  password (D-M7-20). `QPDFWriterBridge` lends both together, one lending inside the other, and `JobSecret` guarded its
  bytes with an `NSLock`, so the same object in both roles locked itself. Stream E's plain Lock would have hung the
  worker on every job. Nothing reached it yet, because the smoke tests passed two separate objects. D3's tests hung, and
  a sample of the process showed `withBytes` inside `withBytes`.
- **A limit read as damage (in `06967d8`, D-M7-43).** The shim's comment said a limit becomes `ZV_PDF_LIMIT`, but it
  looked only on success. qpdf gives up with an error of its own after some limits, and the check can report damage, so
  those files would have said "This PDF is damaged." instead of "too complex to open safely". The shim now looks after
  either outcome. D2's first run of the hostile tests showed it: `.damaged` where `.limit` was expected.

**What the plan assumed and the code did not have.**

- **D1, PDFKit forms.** PDFKit on this SDK writes widgets with `/FT` and no `/AcroForm` in the catalog (seen in the
  bytes), so the plan's PDFKit form fixture can never report `hasAcroForm`. A real AcroForm is typed out instead, and
  widgets on pages without one count as fields, since viewers show them as live (D-M7-38). So `hasAcroForm` is true only
  on the typed fixture; `fieldCount == 2` and `signatureFieldCount == 1` hold on both.
- **D1, locked files.** C4's inspect threw on a locked file with no password, which would leave E9 unable to tell Lock
  from Unlock. Such a file now gets a `PDFPreflight` that is "shut" (D-M7-36). A wrong password still throws. qpdf keeps
  `isEncrypted` true after a refused open, and the shim reads the rest from the object it has. It takes the header's
  version as text, because `getVersionAsPDFVersion` reads the catalog, which a refused open has no key for.
- **D1, test-only C++.** `ZIVLET_PDF_TESTING` cannot work: SwiftPM builds a target once, so a test target's define never
  reaches `CZivletPDF`. Structure and hostile files are typed through `PDFFixtures.raw` instead (D-M7-37), which reaches
  the same structures with no C++ at all, so `zivlet_pdf_testing.cc` does not exist.
- **D2, the watchdog.** The row gave the worker's per-job watchdog a budget, and `ResourceLimits.swift` was named for
  it. There is no such watchdog: the only ones are the trigger host's and ffmpeg's stall detector. So `PDFWatchdog` is
  new (D-M7-40), in `EnginePDF`, because the worker does not link `ZivletRuntime`. A step past its budget stops the
  worker with SIGKILL, and the app's crash rule retries once and then blames the file. Steps take turns and a budget
  starts when the turn comes, because qpdf runs one call at a time (D-M7-32): without that, a small job queued behind a
  large one would spend its 30 s waiting and stop a worker that was doing nothing wrong.
- **D4, where the rewrite runs.** It runs as the last step of `execute`, in a wrapper engine, not in `verify` (D-M7-41).
  In `verify`, the engine's own checks would read the file before the rewrite, and the app would keep a stale byte
  count, since verify's reply carries no output. A hook in `WorkerService` was not possible either: `ZivletWorkerCore`
  is in the app's product and must not link qpdf.
- **D4, the lint.** `PDFDocument.write(` is an instance method, so the plan's literal pattern matches nothing in real
  code. The script also looks for `.write(to:`, `.write(toFile:` and `.dataRepresentation(` in files that import PDFKit,
  and for Quartz PDF contexts anywhere; `ImagePDFWriter.swift` is the one allowed writer.

**Other choices.**

- The value is one type: `QPDFDocumentInfo` is gone, `PDFCipher`, `PDFEncryption` and `PDFPasswordMatch` moved to
  `ZivletEngineKit` with `PDFPreflight`, and `/Identity` crypt filters are reported (qpdf says `e_none`, which the shim
  read as no cipher).
- 512 MB is 512,000,000 bytes, as Finder counts, so the refusal's words match what a person sees (D-M7-39).
- `InputRejection` gains `pdfTooLarge`, `pdfTooComplex` and `pdfDamaged`, new values on the wire, so the worker protocol
  is version 6.
- qpdf's own `setMaxWarnings` gives the "more than 100" rule, in the open and during the write, so nothing counts by
  hand.
- `PDFRewrite` runs without the page limit: a long TIFF makes a long PDF of Zivlet's own, and the limit is for files
  people drop.
- D5 also judges an AES-256 file with its password, the slowest case: it opens twice, and each open runs the R6 key
  derivation. The plan had only the plain file.

**Seen, beyond the tests.** A JPEG through `make convert-demo` in the real Debug app ran in `ZivletWorker`, and the
published PDF has qpdf's marker bytes. So the rewrite reaches the real path, not only the loopback.

**Timing, judged by `Scripts/timing.sh PreflightTiming`** at load 2.92, limit 3.0 (the shim as a debug build, qpdf as a
release one).

| Case | p95 | Budget |
|---|---|---|
| 100 pages, plain | 1.7 ms | 50 ms |
| 100 pages, AES-256 with its password | 21.3 ms | 50 ms |
| 10,000 pages, plain | 75.7 ms, one read | not judged |

**Not done, and why.**

- The watchdog's stop has never run in a real worker (G-M7-22). No test makes a qpdf call hang, so `onStuck` in
  `Worker/main.swift` is only compiled. The timer, the budget, the turns and the disarm are tested with an injected
  clock. (Attempt 2 ran the same stop in a real process, below.)
- The watchdog covers qpdf steps only, not PDFKit rendering in Copy Text and Read QR (G-M7-24).
- Copy Text and Read QR refuse an oversized PDF with their general line, not "This PDF is larger than 512 MB."
  (G-M7-23).
- Limits proved through real files: size, pages, filters and warnings at their boundaries, nesting at 450 and 600 rather
  than 500 and 501. The container and parser-error limits are only shown to reach the shim, with no file at 1,000,000,
  50,000 or 1,000 (G-M7-25, closed in attempt 2, below).
- `hasJavaScript` reads what the row names: `/AA` on the catalog and pages, not on fields or annotations, and not
  `/Next` chains after an `/OpenAction`. It is a fact for warnings, not a security filter.
- Nothing calls pre-flight from the app yet (`.inspectPDFs` is E3), and `PDFVerify`'s note reaches no card yet (E8):
  `Engine.verify` returns nothing, so E4 has to carry it.
- No fresh clone was run for this stream: every gate ran in the working repository, whose tree was clean, with every new
  file tracked. Stream C's fresh clone covered the vendor pack, which this stream did not change.

**Gates** (`nice -n 10`; the screen was awake: the screenshot rows passed rather than skipped; load 1m).

| Gate | Result |
|---|---|
| `make test` on `ed489f0` (baseline) | 2301 tests, 23 bundles, all pass |
| `make test` on `5aaea0d` | 2401 tests, 23 bundles, all pass (load 3.0 → 11.6) |
| `make lint` | passes, with `check-pdf-writes.sh` in it |
| `make coverage` | 21 modules ≥ 80 %: EnginePDF 98 % (527/535), CZivletPDF 91 % (471/512), EngineVision 86 % the lowest |
| `make app` | passes |
| `make release-check` | passes: Bundle OK, 55.9 MB installed, worker 8.1 MB, size OK |
| `make licence-gate` | 15 components, 58 crates |
| `make script-test` | 37 scripts pass |
| `Scripts/m5a-exit.sh` (load 1.9 → 3.3) | X1–X5 and X7 pass, X2 judged. X6 fails on idle CPU (`fast-progress` 1.35 % over a 1 % limit): G-M5a-1, not worked on |
| `Scripts/m5b-exit.sh` (load 3.3 → 5.8) | Y1, Y2, Y4–Y7 and Y9 pass. Y3 skipped (not judged). **Y8 failed**, below |
| `Scripts/m6-exit.sh` (load 5.8 → 17.5) | Z1, Z2 and Z4–Z11 pass, Z5's `make worker-smoke` among them. Z3 skipped (not judged), and again when run alone |
| `Scripts/m7-exit.sh` | not yet written (stream F, F2) |

**The three rows that are not a pass.**

- **Y3 and Z3 were not judged.** Both wrap earlier runners, and X2 inside them refused to judge above the load limit.
  The rows they wrap did pass on this commit: X2–X5 in the m5a run, Y4, Y5 and Y7 in the m5b run. A rerun of Z3 alone
  again passed everything but X2, which waited 20 minutes and stayed not judged.
- **Y8 is the one failure.** `panel-still` went over its 0.1 % twice: 0.384 % (started at load 12.79), then 1.19 % (load
  2.92 at the start, but 5.88 over five minutes, and back to 5.7 during the run). A third run waited 20 minutes for the
  1- and 5-minute loads to fall to 3.0 and they did not, so it did not run. `dasd` held most of a core the whole time;
  it is a system daemon and was left alone. This stream adds no timer, task, loop or display link to anything the app
  runs, and `ZivletBox` has no commit since `m6`, so the stream is not the likely cause. That is a reading of the diff,
  not a measurement: **no passing Y8 was seen on this commit.** The limit was not moved. The row still has no load guard
  (G-M7-21; attempt 2 found input, not load, behind it, below).

---

## Execution notes, attempt 2 (stream D on `m7`, 2026-11-01 to 11-07)

Commits: `f349846` (each parser limit at its exact boundary), `47b1288` (the memory ceiling), and this record. Attempt
1's notes above stand as written, with pointers here. Attempt 1 ended with G-M7-25 open and Y8 failing; attempt 2
closed the first, found a defect while doing it, and found what Y8 reads. `make test` on `47b1288` was green before
this record: 2418 tests, 23 bundles.

**G-M7-25, closed (`f349846`).** Each qpdf parser limit has a typed file at it and one past it, and a check that a
limit one lower refuses the first, so the test can fail: 500 nested arrays are read and 501 are not; a container of
1,000,000 entries is read and one more is not, and in a damaged file the same holds at 50,000; 999 parser errors pass
and 1,000 stop. The filter limit (25) equals qpdf's default, so a limit of 5 refusing six filters shows that the shim's
value is the one in force.

**A defect: the limits did not hold memory (`47b1288`, D-M7-44, D-M7-45).** Proving the container limit meant
reading qpdf's parser: it counts names, strings, reals and booleans towards a container, not numbers, nulls or
references. A test pins that (`theContainerLimitDoesNotCount`), so an upgrade that starts counting them says so.
Measured with the real probe and no ceiling: 1,000,001 numbers were read and written, and 5,000,000 of them (a 10 MB
file) peaked at 780 MB, which scales to about 40 GB for a 512 MB file. A 0.2 MB Flate bomb peaked at 693 MB, because
the check holds decoded page content in memory, and nothing limits what a stream inflates to. This Mac has 17 GB, the
worker has no memory cap and the time watchdog allows up to 81 s, so stream E's Lock and Unlock would have reached it.

qpdf cannot be patched here, so `PDFWatchdog` now reads the process's footprint every 100 ms during a qpdf step and
treats a step past 3 GB as stuck, the same way out as its time budget. Measured with the real probe and the 3 GB
ceiling:

| File | Result | Peak footprint |
|---|---|---|
| 5.1 MB Flate bomb (about 17 GB without the ceiling, estimated) | stopped in 0.76 s | 3,201 MB |
| 10,000 pages, 230,002 objects (the worst ordinary file tried) | runs to the end | 651 MB |
| 500 MB of images | runs to the end | 241 MB |

- The ceiling is on the whole process, not on a step's growth. A limit on growth was built first and failed its test
  (`memoryAnEarlierStepFreedStillCounts`): malloc keeps what an earlier step freed and that counts as footprint, so a
  later step starts high and shows almost no growth. `malloc_zone_pressure_relief` did not change that. Another job's
  memory counts too; at worst that costs one retry (G-M7-26).
- No per-stream decode limit (D-M7-45): the ceiling already holds the memory, an honest large stream must stay
  readable, and qpdf's per-stream limit raises no limit error, so such a file would say "damaged".
- `zivlet-pdf-probe` takes an optional ceiling and runs its check as the worker does, so `PDFMemoryCeilingTests` see a
  real process end by SIGKILL: a Flate bomb, a file of uncounted entries, and memory an earlier step freed. An ordinary
  file under the ceiling, and a small bomb with no ceiling, run to the end. Their ceilings are 50 and 150 MB on files
  under 1 MB, so a failing run costs the Mac little. The poll, the ceiling's boundary (at it is not stuck), a reading
  that fails and the real footprint are unit tests with an injected clock and footprint.
- This takes G-M7-22 halfway: the stop has run in a real process, not yet in the XPC worker, because nothing in the app
  reaches `PDFEngine` until stream E.

**Y8 reads input, not load (G-M7-21).** A watcher beside two runs on 2026-11-01 showed the same load passing and
failing: run 1 passed against a baseline the same bursts had raised to 0.342 %, run 2 failed all three rows
(`box-armed` 2.1 % over). The extra CPU moved between states and came with input (`HIDIdleTime` falling), not with
load. In this record's gate run Y8 passed while nothing touched the Mac: `HIDIdleTime` rose without a break from 530 to
1,053 s across the run, at load 4.4 → 2.3 (baseline 0.217 %, every state at or under it). So a load guard alone will
not do; the limit was not moved, and the row still has no guard on input. The same watcher saw no input during X6
either, so X6's failure below is the app's own idle CPU (G-M5a-1), not the owner's.

**G-M7-11 recurred.** `make app` on its own failed once in this record's gate run: Xcode's copy of `Sparkle.framework`
found no `_CodeSignature`. The rerun passed, and so did the `make app` inside X1, Y1 and Z1. The passing rerun's log
shows the likely cause: Xcode's copy of the Sparkle package framework ran after the "Embed media helpers" phase, which
trims Sparkle and signs the nested code. That Debug app kept an untrimmed universal Sparkle with its XPC services, and
`codesign --verify --deep --strict` calls its nested code invalid; when the copy and the phase overlap, they race. The
phase declares no inputs, so nothing orders it after the copy. The Release app of `make release-check` was trimmed
(arm64, no XPC services) and verifies. Read from the logs and the bundles, not fixed: it is outside P2-105, and the
next step is in G-M7-11.

**Gates** (`nice -n 10`, in the working repository on `47b1288` with only this record's edits uncommitted; the screen
was awake, so the screenshot rows ran; load 1m).

| Gate | Result |
|---|---|
| `make test` on `47b1288` | 2418 tests, 23 bundles, all pass (load 2.3 → 12.1) |
| `make lint` | passes |
| `make coverage` | 21 modules ≥ 80 %: EnginePDF 98 % (579/588), CZivletPDF 91 % (471/512), EngineVision 86 % the lowest |
| `make app` | failed once (G-M7-11, above); passed on the rerun and inside X1, Y1 and Z1 |
| `make release-check` | passes: Bundle OK, 55.9 MB installed, worker 8.1 MB, size OK |
| `make licence-gate` | 15 components, 58 crates |
| `make script-test` | 37 scripts pass |
| `Scripts/m5a-exit.sh` (load 4.5 → 3.3) | X1–X5 and X7 pass, X2 judged. X6 fails on idle CPU (G-M5a-1, not worked on): four of eight states over their limits, `fast-progress` 1.93 % over 1 % the most, `hidden` 0.109 % over 0.1 % the least |
| `Scripts/m5b-exit.sh` (load 3.3 → 2.3) | Y1–Y9 pass, Y3 with X2 judged, Y8 with the Mac untouched |
| `Scripts/m6-exit.sh` (load 2.3 → 7.7) | Z1–Z11 pass, Z3 with X2 judged, Z5's `make worker-smoke` among them |
| `Scripts/m7-exit.sh` | not yet written (stream F, F2) |

**Still open from this stream:** G-M7-21 (Y8 has no guard on input), G-M7-22 (the stop in the XPC worker), G-M7-23,
G-M7-24 (PDFKit rendering has no budget or ceiling), G-M7-26 (the words a ceiling stop reaches, and a false stop, not
seen) and G-M7-11 (above). No fresh clone was run, as in attempt 1.
