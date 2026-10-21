# 12 — Document Engine (documents, slides, spreadsheets, EPUB, Pages, PDF extraction)

Date: 2026-10-20. Status: **proposal for decision**. Owner: engines track.
Inputs: `00-decisions.md` (direct download, not sandboxed, GPL-compatible, macOS 26+, Apple silicon first), plus Zivlet's internal product spec (route matrix), platform-feasibility and competitive notes (not published).

This document picks the engines behind every document, slide, spreadsheet, EPUB, Pages, and PDF-extraction route in Zivlet. It covers about 110 of the 275 conversion pairs. Image, audio, and video routes, plus PDF → JPG/PNG rasterising, belong to other engine docs.

> **Clean-room note.** Zivlet is an independent, clean-room implementation. Nothing here copies code, templates, or assets from the reference app or from Open-Tangerine. Every third-party library named below (docx-preview, cupertino-files, and the rest) is taken from upstream under its own license, with our own glue code.

Evidence tags used below:
- **MEASURED**: run on the dev machine on 2026-10-20 (Apple silicon; `sw_vers` reports 27.0, build 26A428), with the commands shown in §3.
- **SOURCE**: read from an upstream repository, release page, registry, or SDK header.
- **ESTIMATE**: reasoned, not measured. Needs a spike to confirm.

---

## 1. TL;DR

1. **Native first.** One in-app Tier 1 stack covers every route in the matrix offline, with no JVM and no LibreOffice. It adds about 10–12 MB to the app (ESTIMATE). It uses:
   - Apple frameworks: PDFKit, Vision `RecognizeDocumentsRequest`, `NSAttributedString` (only for RTF/RTFD/clippings), and `WKWebView.printOperation` for paginated PDFs.
   - A small set of permissive JavaScript libraries that run offline in WebKit or JavaScriptCore: **docx-preview** (DOCX layout), **mammoth** (DOCX semantics), **@aiden0z/pptx-renderer** (PPTX), **SheetJS CE** (spreadsheets), and **cupertino-files** (Pages).
   - Our own Swift **document model ("SDoc")** with writers for DOCX, EPUB 3, HTML, MD, TXT, RTF, and Pages.
2. **An optional high-fidelity "Office Engine" = LibreOffice 26.8**, never bundled:
   - Zivlet uses an existing `/Applications/LibreOffice.app` if one is installed.
   - Otherwise the user can download the official notarized TDF build on demand: 298.8 MB DMG, **805 MB installed** (MEASURED). Zivlet checks it with a pinned SHA-256 and the TDF Team ID `7P5S3ZLCN7`.
   - It is the only good path for **PPT** and the best path for Office-accurate PPTX/XLSX/DOCX → PDF/PNG.
3. **iWork apps as an opt-in bridge.** When Pages, Keynote, or Numbers is installed, the user can opt in to Apple-Events export (Pages → PDF/DOCX/EPUB, Keynote → PDF/PPTX/images, Numbers → XLSX/CSV/PDF). Apple's own renderer gives the best fidelity for iWork sources.
4. **Rejected as shipped engines:**
   - Apache POI + JRE: 67–91 MB, slow start, and weaker than both LibreOffice and the new JavaScript renderers.
   - Pandoc bundled in core: 192 MB binary. It stays an optional pack, a fallback, and a test oracle.
   - WeasyPrint: needs a Python + Pango stack.
   - Typst as the default PDF backend: 45 MB, and it cannot render HTML or CSS.
   - MuPDF in core: AGPL, and Vision on macOS 26 does the structural work.
5. **PDF → DOCX/MD/TXT/EPUB/XLSX/PPTX is native.** We fuse the PDFKit text layer with Vision `RecognizeDocumentsRequest` on macOS 26, which returns paragraphs, tables, and lists. No third-party engine beats this on a Mac without shipping Python and ML models.

---

## 2. Scope: routes this engine owns

From Zivlet's route matrix (275 pairs), plus a few extras:

| Input | Outputs | Notes |
|---|---|---|
| pdf | docx, pages, pptx, xlsx, epub, txt, md (+ jpg, png owned by the PDF/image engine) | "Editable" vs "preserve pages" modes for DOCX/EPUB |
| docx | pages, pdf, txt, md, html, epub, png, jpg | |
| pages | docx, pdf, txt, md, html, epub, png, jpg | |
| md, txt | docx, pages, pdf, (txt/md), html, epub, png, jpg | |
| rtf, rtfd, textClipping | docx, pages, pdf, txt, md, html, epub, png, jpg | input only |
| epub | pdf, docx, pages, txt, md, html | DRM/obfuscated fonts refused |
| ppt, pptx | pdf, jpg, png | ppt is input only |
| xlsx, xls, ods, csv, tsv | each other (xls input only) + pdf | multi-sheet → CSV/TSV folder |
| image | docx (OCR) | extra |
| *Zivlet extras (P1/P2)* | odt in/out, doc in, odp in, keynote/numbers in, md ↔ html | Zivlet differentiators |

HTML is output only.

---

## 3. Lab measurements (2026-10-20)

All runs used a scratch corpus. A Markdown source with a title block, headings, nested lists, a right-aligned table, an image, a footnote, a link, and a block quote was rendered by Pandoc to DOCX, ODT, EPUB, RTF, HTML, and PPTX. LibreOffice then made the XLSX and XLS files from a CSV.

### 3.1 Native Apple paths (MEASURED)

| Test | Result |
|---|---|
| `textutil -convert html t.docx` (= `NSAttributedString` DOCX import) | Keeps paragraphs, lists (5 `<li>`), and the table (1 `<table>`). **Drops the image, the footnote (marker and text), and the hyperlink URL.** Headings become font sizes with no semantics. |
| `textutil -convert docx t.docx` (DOCX round trip) | The output ZIP has **no `word/media`**, so the image is lost. 8 parts vs 17 in the source. |
| `textutil` ODT / RTF → HTML | Tables and lists survive. Images and footnotes are dropped. |
| `textutil` HTML → HTML | The image, the link, and the footnote text all survive. HTML is the richest input `NSAttributedString` handles. |
| `WKWebView.loadFileURL(t.pptx / t.docx)` | `WebKitErrorDomain 102 "Frame load interrupted"`. **macOS WebKit does not render Office files.** iOS WebKit does, and many people wrongly assume macOS does too. |
| `WKWebView.printOperation(with:)` into an off-screen borderless window, `jobDisposition = .save`, A4, 0.5" margins, from an accessory-policy app | **4 paginated pages with selectable text**, 1.65 s wall time including process launch and WebKit spin-up. |
| `qlmanage -t -s 1600` on pptx, docx, xlsx | One thumbnail per file (first page or slide only). Quick Look is fine for previews but useless for conversion. |
| `WebPage.ExportedContentConfiguration.pdf(region:allowTransparentBackground:)` (macOS 26 SwiftUI WebKit, from the SDK `.tbd`) | Exports a single region, **not paginated**. The same limit as `createPDF`. |
| Vision `RecognizeDocumentsRequest` (macOS 26 SDK swiftinterface) | `[DocumentObservation]` → `.document: Container` with `title`, `paragraphs`, `tables[].rows[][]` (`Cell.content`), `lists[].items` (with `markerType`), and `detectedData`. Has `TextRecognitionOptions` (languages, custom words). SOURCE (SDK). |

### 3.2 JavaScript libraries in JavaScriptCore (MEASURED, using the system `jsc` shell)

| Test | Result |
|---|---|
| SheetJS CE 0.20.3 (`xlsx.full.min.js`, 951,904 B) reads xlsx, xls, and csv, then writes xlsx, ods, and xls | All reads were correct, in 0–10 ms each. Writes: xlsx 16.6 KB, ods 8.1 KB, xls 4.6 KB. `bookType:"numbers"` needs the separate `numbers` payload (zahl). |
| mammoth 1.13.0 (`mammoth.browser.min.js`, 405 KB) DOCX → HTML | **Fails in bare JSC with `Can't find variable: TextDecoder`.** With a 4-line `TextDecoder`/`TextEncoder` polyfill it works in **28 ms**. Output: semantic `<h1>/<h2>`, `<a href>`, footnotes as `<sup>` + an end list, nested `<ol>/<ul>`, a `<table>` with `<thead>`, and the image as a `data:` URI. It warns about unmapped styles (fixed with a style map). |

### 3.3 LibreOffice 26.8.1 (MEASURED)

| Item | Value |
|---|---|
| Artifact | `LibreOffice_26.8.1_MacOS_aarch64.dmg`, **298,845,477 B**. A `.asc` signature sits beside it on `download.documentfoundation.org`. |
| Gatekeeper | `accepted · source=Notarized Developer ID · origin=The Document Foundation (7P5S3ZLCN7)` |
| Bundle | `org.libreoffice.script`, version 26.8.1.1, `LSMinimumSystemVersion` 11.0 |
| Installed size | **805 MB**: Frameworks 435 MB (`libmergedlo.dylib` alone is 144 MB), Resources 361 MB (config 107 MB, help 61 MB, extensions/dictionaries 61 MB, fonts 51 MB, 26 `.lproj`) |
| First `--convert-to pdf` (fresh profile) | **12.7 s** (profile creation + first-launch checks) |
| Later one-shot runs, one process per file | DOCX → PDF 1.18–1.38 s · PPTX → PDF 1.53 s · CSV → XLSX 1.89 s · XLSX → XLS 1.40 s · PPTX → PNG 1.65 s (**first slide only**) |
| `--convert-to` forwarded to an already-running instance | ~1.0–1.1 s per file |
| LibreOfficeKit | `_libreofficekit_hook`, `_libreofficekit_hook_2`, and `_lok_preinit_2` are exported from `libmergedlo.dylib`, so an in-process LOK helper is possible |
| Bundled Python (needed for unoserver) | `Resources/python` wraps `LibreOfficePython.framework` (3.13). It was SIGKILLed (137) in our tool sandbox, so warm UNO latency is **not measured**. unoserver states 2–4× throughput vs one-shot (SOURCE) and does not officially support Mac. |

### 3.4 Pandoc 3.12.1 and Typst 0.15.1 (MEASURED)

| Item | Value |
|---|---|
| `pandoc-3.12.1-arm64-macOS.zip` | 42.3 MB download. **`bin/pandoc` is 192,006,640 B** (static Haskell; links only libSystem, libz, libiconv, libffi, Security). `xz -9` brings it to 23.8 MB. |
| `pandoc.wasm` (3.12.1 wasm.zip) | 16.7 MB zip, **61.3 MB** `.wasm` |
| Startup / speed | `--version` 0.03 s · DOCX → GFM with media extraction 0.42 s · DOCX → EPUB 0.31 s |
| Readers (3.12.1) | docx, odt, fodt, epub, rtf, html, md variants, typst, ipynb, **pptx, xlsx** (text and tables only), csv/tsv, latex, … |
| DOCX → GFM fidelity | Headings, links, footnotes, nested lists, the table, and the image (extracted) are all preserved. The best semantic quality of anything tested. |
| RTF → GFM | Good. The table header row came out as a body row, and the title as bold text. |
| XLSX reader | The integers `3, 10` became `3.0, 10.0`, so not usable as a spreadsheet engine. |
| Typst `typst-aarch64-apple-darwin` | 14.4 MB `.tar.xz`, **45 MB binary** (bundled fonts) |
| `pandoc t.docx --pdf-engine=typst --pdf-engine-opt=--root=/` | 0.59 s, nice typography, footnote at the page foot. **Gotcha:** without `--root`, Typst refuses images outside the project root. |

---

## 4. Evaluation of candidates

Scoring scale: ★ poor … ★★★★★ excellent. "Fit" means fit for Zivlet (size, license, offline use, macOS 26 arm64, maintenance).

### 4.1 Native Apple frameworks

| Capability | API | Quality | Verdict |
|---|---|---|---|
| RTF / RTFD / textClipping read | `NSAttributedString(url:options:[.documentType: .rtf/.rtfd])`. Clippings: a binary plist with UTI-keyed data (`public.utf8-plain-text`, `public.rtf`) via `PropertyListSerialization` | ★★★★★ | **Use** |
| RTF / RTFD write | `NSAttributedString.data(from:documentAttributes:[.documentType: .rtf])`, `fileWrapper(...)` for RTFD | ★★★★★ | **Use** (SDoc → NSAttributedString → RTF) |
| DOCX / ODT read | `.officeOpenXML`, `.openDocument` | ★★ (no images, footnotes, or link URLs; MEASURED) | **Don't use for DOCX/ODT.** Use mammoth or our own reader. |
| DOCX write | `.officeOpenXML` | ★★ (loses images; MEASURED) | **Reject.** Write our own WordprocessingML. |
| HTML read | `.html` (WebKit-backed, main thread only) | ★★★ | Avoid. Parse HTML with SwiftSoup into SDoc instead. |
| Paginated PDF from HTML/CSS | `WKWebView.printOperation(with: NSPrintInfo)`, `.jobDisposition = .save`, `.jobSavingURL`, `showsPrintPanel = false`, `runModal(for:…)` on an off-screen window | ★★★★ (vector, selectable text; MEASURED). WebKit ignores CSS `@page` margin boxes, so page numbers and running headers must be stamped afterwards with PDFKit. | **Core PDF backend** |
| Single-region PDF | `WKWebView.createPDF(configuration:)`, `WebPage.exported(as: .pdf(...))` | ★★★ for fixed-size pages (slides, docx-preview pages) | **Use** per slide or page, then merge with `PDFDocument.insert` |
| Native Office rendering | WKWebView on macOS | ✗ (MEASURED) | Not available |
| Quick Look | `QLThumbnailGenerator` | first page only | Previews and Float shelf thumbnails only |
| PDF text layer | `PDFPage.string`, `attributedString`, `PDFSelection.selectionsByLine()` + `bounds(for:)`, `CGPDFScanner` for font sizes | ★★★★ | **Use** |
| Layout analysis and OCR | Vision `RecognizeDocumentsRequest` (macOS 26): paragraphs, tables with cells, lists with markers, title | ★★★★ (SOURCE; corpus spike S-PDF needed) | **Use**. This is the macOS 26 advantage. |
| TextKit 2 pagination | `NSTextLayoutManager` + `NSTextContainer` per page → `CGContext` PDF | ★★★ | Not needed. WKWebView covers it with less code. |
| `textutil` CLI | the same engine as `NSAttributedString` | — | Dev and test oracle only |

### 4.2 JavaScript libraries hosted offline in WebKit / JavaScriptCore

Hosting rules apply to every library (§6.4). WebKit-hosted libraries run in a hidden `WKWebView` that loads bundled code through a custom `WKURLSchemeHandler` (`zivlet-doc://`), with a `WKContentRuleList` that blocks `^https?://`, `^file://`, and `^data:` subresources except images. DOM-less libraries run in a `JSContext` (with `com.apple.security.cs.allow-jit` on the helper so JSC can JIT), plus small polyfills for `TextDecoder`/`TextEncoder`, `crypto.getRandomValues`, and `setTimeout`.

| Library | Version · license · size | Does | Quality / caveats | Verdict |
|---|---|---|---|---|
| **docx-preview** (VolodymyrBaydalka/docxjs) | 0.4.1 (npm; GitHub release 0.4.0, 2026-07-07) · Apache-2.0 · 75.5 KB min + JSZip 3.10.1 97.6 KB | DOCX → HTML DOM with page boxes, styles, numbering, tables, images, headers/footers, footnotes | ★★★ layout. **No real pagination.** It breaks only at manual page breaks, section changes, and (with `ignoreLastRenderedPageBreak:false`) Word's `<w:lastRenderedPageBreak/>` hints (SOURCE README). TOC fields are not computed. Floating shapes and text boxes are approximate. | **Tier 1 for DOCX → PDF/PNG/JPG.** Our print-driven pagination (rather than per-page `createPDF`) is in §6.3. |
| **mammoth** | 1.13.0 · BSD-2-Clause · 405 KB browser min | DOCX → clean semantic HTML (headings by style map, lists, tables, links, footnotes/endnotes, images) | ★★★★ semantics, ignores visual formatting by design. Mature (since 2013, 6.3k★). | **Tier 1 DOCX reader into SDoc** (DOCX → MD/TXT/HTML/EPUB/Pages) |
| **@aiden0z/pptx-renderer** | 1.4.0 · Apache-2.0 · 5.5 MB unpacked (deps: jszip, echarts, mtx-decompressor) | PPTX → HTML/SVG DOM: shapes, text, images, tables, charts (ECharts), SmartArt, OMML equations, gradients, shadows, bounded 3D | ★★★★ (SOURCE: visual-regression suite vs PowerPoint ground truth with SSIM, IoU, and histograms). Vector output, so the PDF has real text. Young (created 2026-02), 131★, single maintainer. | **Tier 1 for PPTX → PDF/PNG/JPG** |
| **@silurus/ooxml** (office-open-xml-viewer) | 0.89.1 · MIT · 21.9 MB unpacked (Rust → WASM parsers + Canvas 2D) | DOCX (**has a real paginator**, `waitUntilLayoutComplete()`), XLSX, PPTX. An experimental add-on reads legacy .doc/.xls/.ppt. | ★★★★ on its demos, but **raster (canvas) output**: PDFs made from it would be images. README says the codebase is written by AI agents. Has `useGoogleFonts`, which must be off. Fast-moving (0.x). | **Evaluate in spike S-RENDER** as the PNG/JPG path for DOCX and the legacy PPT/XLS fallback. Not the default for PDF. |
| pptx-preview | 1.0.7 · ISC on npm, "Other" on GitHub | PPTX → HTML | ★★ | Reject (license ambiguity, weaker) |
| PPTist | AGPL-3.0 | editor app | — | Reject (an app, not a library) |
| **SheetJS CE** | 0.20.3 · Apache-2.0 · 952 KB (`xlsx.full.min.js`, includes codepages) | Read xlsx/xlsm/xlsb/xls (BIFF2–8)/ods/fods/csv/tsv/numbers. Write xlsx/xlsb/xls/ods/csv/txt/html (numbers with the zahl payload). Formats via SSF. | ★★★★ data. **CE drops most cell styling** (fills, fonts, borders are Pro features). Keeps merges, column widths (`!cols`), and number formats (`cellNF`). Distributed from `cdn.sheetjs.com` and `git.sheetjs.com`. **npm `xlsx@0.18.5` is stale and vulnerable** (CVE-2023-30533 prototype pollution, CVE-2024-22363 ReDoS, both fixed by 0.20.2). | **Tier 1 spreadsheet engine** (vendored 0.20.3, pinned hash) |
| **cupertino-files** | 0.4.0 · MIT · 4.0 MB unpacked, TypeScript, ESM, Node ≥ 22 | Read and write Pages, Numbers, and Keynote (IWA: Snappy-framed protobuf). Byte-identical round trips. `PagesDocument.blank()`. Text, styles, lists, tables, images, footnotes, headers/footers. | ★★★ (SOURCE COVERAGE.md). Very young (created 2026-07-30, 4★, one maintainer). iWork '09 and password-protected files are refused. Mixed LZFSE packages are read-only. | **Tier 1 for .pages read/write** and Keynote/Numbers read (P2). Vendor a pinned build and keep a fixture corpus. |

### 4.3 LibreOffice headless (the "Office Engine")

**What:** the TDF build of LibreOffice 26.8.1 (MPL-2.0/LGPLv3+), used through `soffice --headless --convert-to`, through a resident listener, or through LibreOfficeKit.

**Quality.** ★★★★½ for DOCX/ODT/RTF → PDF (a real layout engine with Carlito/Caladea metric clones bundled), PPTX/PPT/ODP → PDF, and XLSX/XLS/ODS → PDF (print ranges, page setup, charts, conditional formatting). It is the only mature open-source **PPT** and **DOC** reader. Weak spots:
- PDF import goes to Draw as positioned text boxes, which is useless for "editable DOCX".
- Pages/Keynote/Numbers import through libetonyek is partial for modern IWA files.
- `--convert-to png` renders only the first slide or page. Full sets need PDF then a raster step.

**Size.** A 298.8 MB DMG and 805 MB installed (MEASURED). Stripping help, dictionaries, `.lproj` folders, gallery, templates, and Firebird would reach roughly 450–500 MB (ESTIMATE), but any change breaks TDF's code signature. We would then have to re-sign, notarize, and patch-maintain a fork. **So we never bundle it and never modify it.**

**Startup.** First run is 12.7 s, then about 1.2–1.9 s per one-shot process and about 1.0 s when forwarding to a running instance (MEASURED). Warm conversions through a resident listener or LOK should be around 0.1–0.5 s for small files (ESTIMATE, consistent with unoserver's 2–4× claim).

**Integration options, best first:**
1. **Batch one-shot (v1).** Group a multi-file drop by filter into one process: `soffice -env:UserInstallation=file://<AppSupport>/Zivlet/Engines/lo-profile --headless --norestore --nolockcheck --convert-to pdf:writer_pdf_Export --outdir <staging> a.docx b.docx c.docx`. Cancel with SIGTERM, then SIGKILL after 5 s. Use a watchdog of 120 s per file. No Python and no extra code signing.
2. **Resident LOK helper (v1.x optimisation).** A tiny `zivlet-office-helper` CLI inside our bundle `dlopen`s `<LO>/Contents/Frameworks/libmergedlo.dylib`, calls `libreofficekit_hook_2(installPath, profileURL)`, then `documentLoad` → `saveAs(url, "pdf", filterOptions)`. It needs `com.apple.security.cs.disable-library-validation` **on the helper only**, because it loads another team's dylib. That keeps the main app's hardened runtime strict. Talk to it over a pipe with JSON lines. Recycle the helper every N documents or on high RSS.
3. unoserver: needs pip into LO's bundled Python. The project states that Mac is untested, and it adds a Python dependency chain. **Reject.**

**Discovery and download.** See §7.

**Fit.** ★★★ It is huge, but it is the only credible free path to Office-grade fidelity and PPT. As an on-demand engine it costs core users nothing.

### 4.4 Pandoc

**What:** Pandoc 3.12.1 (GPL-2.0-or-later, so compatible with Zivlet's GPLv3). Released 2026-10-08, very active (46.6k★).

**Quality.** ★★★★★ for *semantic* conversion between DOCX, ODT, EPUB, RTF, HTML, MD, and Typst (MEASURED: everything in the corpus survived). It does not do layout. DOCX → PDF goes through a PDF engine (Typst or WKWebView), so the output is re-typeset rather than page-faithful. The PPTX and XLSX readers extract text only.

**Size.** The 192 MB binary is the problem. It would triple the core app. The 61 MB `pandoc.wasm` could run inside a WKWebView (which has a JIT) with a WASI shim. That is novel and slower (ESTIMATE 3–10×).

**Startup.** 0.03 s (MEASURED). Excellent.

**Fit.** ★★★ It is the best semantic engine, but Zivlet's core app budget is under 60 MB and our own SDoc is needed anyway for PDF → DOCX and Pages.

**Role:**
- (a) a **CI oracle**: compare our MD/HTML/EPUB/DOCX writers against Pandoc output on the corpus;
- (b) an optional **"Pandoc pack"** download (42 MB) later, if corpus scores show our semantic paths lag;
- (c) the **fallback** if our writers slip: bundle it and accept +192 MB installed (+~40 MB DMG).

### 4.5 Typst and WeasyPrint (PDF typesetters)

| | Typst 0.15.1 | WeasyPrint v70.0 |
|---|---|---|
| License | Apache-2.0 | BSD-3-Clause |
| Footprint | 45 MB binary (fonts embedded), 14.4 MB `.tar.xz` | Python 3 + Pango/HarfBuzz/fontconfig/GLib/cairo-free stack. Bundling a relocatable Python is roughly 60–100 MB (ESTIMATE) |
| Input | Typst markup (Pandoc writes it) | HTML + CSS Paged Media (margin boxes, running headers, footnotes) |
| Quality | Excellent typography, fast (0.59 s via Pandoc, MEASURED) | Best CSS paged-media support of any open engine |
| Verdict | **Reject for v1.** WKWebView print is free and renders our HTML. Revisit for a "Beautiful PDF" theme (P2). | **Reject.** Python packaging on arm64 macOS for a direct-download app is high-maintenance. Use WKWebView + a PDFKit stamping pass for page numbers. |

### 4.6 Apache POI + bundled JRE

- **POI 5.5.1 / PDFBox 3.0.8** (Apache-2.0), latest on Maven Central.
- **Cost:** a jlinked JRE 21 runtime is roughly 30–35 MB per architecture, plus about 20–25 MB of POI/PDFBox jars. A single arm64 runtime plus jars is about 55–60 MB (ESTIMATE). JVM start plus POI class loading is typically 1–2 s per run, even with start-up tuning such as C1-only tiered compilation and serial GC.
- **Quality:** POI's `XSLFSlide.draw(Graphics2D)` → PDFBox has no charts, no SmartArt, and weak text layout. That is worse than pptx-renderer (vector, with charts) and far worse than LibreOffice. POI HSLF (PPT) rendering is weaker still. For spreadsheets, SheetJS does the data work in under 1 MB.
- **Verdict: Reject.** It would be the single largest component in the app and buys the least. Shipping with no JVM is one of Zivlet's headline goals.

### 4.7 Spreadsheet libraries (native alternatives to SheetJS)

| Library | Version · license · status | Role | Verdict |
|---|---|---|---|
| calamine (Rust) | 0.37.0 (2026-10-18) · MIT · active | Fast reader for xls/xlsx/xlsb/ods. Values and formulas, few styles. | **Fallback** if SheetJS is too slow on large sheets (more than 1M cells). Ship as a Rust staticlib with a C ABI. |
| rust_xlsxwriter | 0.100.0 (2026-10-17) · Apache-2.0 / MIT · active | Full-featured XLSX writer (styles, charts, tables) | Fallback writer, paired with calamine |
| umya-spreadsheet | 3.1.1 (2026-10-12) · MIT · active | Read **and** write xlsx with full styles | Candidate for **styled XLSX → PDF** (read fills, borders, fonts → HTML) if CE styles prove insufficient |
| libxlsxwriter (C) | 1.2.4 · BSD-2 | XLSX writer, easy SPM C target | Not needed if SheetJS is used |
| libxls (C) | 1.6.4 (2026-10-12) · BSD-2 | XLS (BIFF) reader | Not needed (SheetJS reads BIFF) |
| CoreXLSX (Swift) | 0.14.2 (2023-03) · Apache-2.0 · **stale** (last push 2024-03) | XLSX reader only | **Reject** (unmaintained, read-only) |
| ZIPFoundation (Swift) | 0.9.20 (2025-09) · MIT · maintained | ZIP read/write for OOXML/ODF/EPUB/IWA containers. Store-only entries supported (EPUB `mimetype`). | **Use** (all packaging) |

### 4.8 Pages, Keynote, Numbers

| Option | Read | Write | Notes | Verdict |
|---|---|---|---|---|
| **cupertino-files 0.4.0** (MIT, TS) | Pages/Numbers/Keynote IWA | Pages/Numbers/Keynote | See §4.2. Seed new documents from `PagesDocument.blank()`, so we need **no template file** (no Pages-authored template ships in the bundle). Bundle with esbuild into one IIFE for JSContext. | **Tier 1** |
| WorkKit (6over3) | ✓ (visitor API, Swift) | ✗ | **AGPL-3.0.** Combinable with GPLv3 under GPLv3 §13, but it would put AGPL terms on the combined work. Read only. 95★. | Reject (keep as a reading reference only, no code reuse) |
| libetonyek (MPL-2.0) | partial | ✗ | C++ with librevenge/boost. Already inside LibreOffice. | Covered indirectly by the Office Engine |
| numbers-parser / keynote-parser (Python) | ✓ | partial | Python | Reference only |
| **iWork apps via Apple Events** (Pages/Keynote/Numbers 14.5 installed here) | ✓ perfect | ✓ perfect | Local sdef export enumerators: **Keynote** PDF, slide images (JPEG/PNG/TIFF), Microsoft PowerPoint, HTML, QuickTime movie. **Pages** PDF, Microsoft Word, EPUB, unformatted text, formatted text. **Numbers** PDF, Microsoft Excel, CSV (MEASURED from the `.sdef` files). Needs the hardened-runtime entitlement `com.apple.security.automation.apple-events` + `NSAppleEventsUsageDescription`, and a one-time TCC Automation consent per app. The app launches visibly unless hidden. Slow (2–5 s, ESTIMATE). | **Tier 2, opt-in** ("Use Pages/Keynote/Numbers when installed") |
| `preview.jpg` inside `.pages` | first page image | ✗ | Modern IWA packages hold `preview.jpg` and `preview-web.jpg`. Only old ones have `QuickLook/Preview.pdf`. | Last-resort preview |

### 4.9 PDF → editable formats (DOCX, MD, TXT, EPUB, XLSX, PPTX, Pages)

| Option | License / size | Quality | Verdict |
|---|---|---|---|
| **PDFKit text layer + Vision `RecognizeDocumentsRequest` fusion** | system | ★★★★ (ESTIMATE pending S-PDF). Vision gives reading order, paragraphs, tables, and lists, and works on scans. PDFKit gives exact glyphs, font names and sizes (for heading inference), and links. | **Tier 1** |
| Vision `RecognizeTextRequest` (macOS 15+) only | system | ★★★ lines only | Fallback for languages `RecognizeDocumentsRequest` does not support |
| MuPDF 1.28.5 `mutool convert -F docx/odt/html/stext` | AGPL-3.0 · ~30–50 MB with fonts (ESTIMATE) | ★★★ (the "extract" writer: positioned paragraphs, weak tables) | Reject for core. Optional CI comparison. |
| pdfminer.six 20260107 / pdf2docx 0.5.13 (MIT, but depends on PyMuPDF, which is AGPL) | Python | ★★–★★★ | Reject (Python) |
| docling 2.140.0 (IBM) | Python + ML models, multi-GB | ★★★★½ | Reject for shipping. Use as a quality yardstick in research. |
| LibreOffice PDF import (Draw) | Office Engine | ★ for "editable" (positioned frames) | Reject for these routes |

**PDF → editable pipeline (Tier 1):**
1. Per page, if `page.string` has a usable text layer (more than 20 printable characters per 1000 pt² and less than 5% U+FFFD), collect line selections with bounds and font sizes. Otherwise the page is "scanned".
2. Render the page at 2× (about 144 dpi, or 200 dpi for scans) into a `CGImage`. Run `RecognizeDocumentsRequest` with `recognitionLanguages` from the user's preferred languages.
3. Use the Vision containers (paragraphs, tables, lists) for structure. For text-layer pages, replace OCR transcripts with PDF-layer text matched by bounding-box overlap (IoU > 0.5), so accuracy stays perfect where text exists.
4. Find headings by font-size clustering: k-means on run sizes, then rank the clusters above the body mode as H1–H3. Drop repeated top and bottom bands across pages as headers and footers. Turn hyphen + newline into a joined word.
5. Emit SDoc, then the target writer. "Preserve pages" modes (DOCX/EPUB/PPTX) embed each page as an image, with an optional invisible OCR text layer for EPUB (fixed-layout EPUB 3 with `rendition:layout=pre-paginated`).
6. PDF → XLSX: one sheet per detected table (`Table.rows` → cells, typed with number and date sniffing), written through SheetJS. Pages with no tables give a "No tables found" result with an explanation, not an empty file.

### 4.10 Fonts (a hidden fidelity factor)

Office documents mostly use Calibri, Cambria, Aptos, Arial, and Times New Roman. macOS 26 ships Arial and Times New Roman, but not Calibri, Cambria, or Aptos unless Microsoft Office is installed.

Bundle these metric-compatible OFL/Apache fonts (about 6–8 MB, ESTIMATE; verify each license file):
- **Carlito** (Calibri metrics)
- **Caladea** (Cambria)
- **Liberation Sans/Serif/Mono 2.x** (Arial/Times/Courier, as a fallback)
- **Gelasio** (Georgia)
- **Selawik** (Segoe UI)

Register them with `CTFontManagerRegisterFontURLs(_, .process, …)` for native rendering, and inject `@font-face { font-family: "Calibri"; src: url(zivlet-doc://fonts/Carlito-Regular.ttf) }` aliases into the docx-preview and pptx-renderer pages, so line breaks match Word.

Aptos has no metric clone. Map it to Carlito and flag "font substituted" in the result report. Always prefer an installed real font: check `NSFontManager.availableFontFamilies` before aliasing.

---

## 5. Comparison summary

| Engine | Size added | License | Startup | DOCX→PDF | PPTX→PDF | XLSX→PDF | Semantic doc↔doc | PPT/XLS(legacy) | Fit |
|---|---|---|---|---|---|---|---|---|---|
| Native Apple + JS (Tier 1) | ~10–12 MB (E) | Apache/BSD/MIT | 0.2–1.7 s (M) | ★★★ | ★★★★ | ★★½ (data-faithful, style-light) | ★★★★ | XLS ✓ (SheetJS), PPT ✗ | ★★★★★ |
| LibreOffice 26.8 (on demand) | 0 bundled / 805 MB if downloaded | MPL-2.0 | 1–2 s, 12.7 s first (M) | ★★★★½ | ★★★★ | ★★★★½ | ★★★½ | ✓✓ | ★★★ |
| iWork apps (opt-in) | 0 | Apple | 2–5 s (E) | ★★★★ (via Pages import) | ★★★★ (via Keynote import) | ★★★★ (via Numbers) | — | PPT ✓ (Keynote) | ★★★ |
| Pandoc 3.12.1 | 192 MB (42 MB zip) | GPL-2+ | 0.03 s (M) | ★★ (re-typeset) | ✗ | ✗ | ★★★★★ | ✗ | ★★★ |
| POI + JRE | 55–60 MB (E) | Apache-2.0 | 1–2 s | ✗ (n/a) | ★★ | ★★★ | ✗ | ★★ | ★ |
| Typst | 45 MB | Apache-2.0 | 0.3 s | via Pandoc ★★ | ✗ | ✗ | ✗ | ✗ | ★★ |
| WeasyPrint | 60–100 MB (E) | BSD-3 | ~1 s | ✗ | ✗ | ✗ | ✗ | ✗ | ★ |

(M = measured, E = estimate.)

---

## 6. Architecture

### 6.1 Modules

```
ZivletDocs (Swift package, Swift 6 strict concurrency)
├── SDoc/                 Document model (value types, Sendable)
│   ├── SDocument { meta, sections[ {pageSize, margins, header?, footer?, blocks} ], footnotes, assets }
│   ├── Block: heading(level, inlines) | paragraph(style, align, inlines) | list(ordered, start, items[[Block]])
│   │          | table(columns, rows[[Cell{rowSpan,colSpan,blocks}]], headerRows) | image(assetID, size, alt)
│   │          | quote([Block]) | code(lang, text) | pageBreak | rule
│   └── Inline: text(String, Marks{b,i,u,s,sup,sub,code,color,size,font}) | link(url,[Inline]) | footnoteRef(id) | lineBreak | image
├── Readers/   MammothDOCXReader (JS), EPUBReader (ZIPFoundation + OPF spine + SwiftSoup), HTMLReader (SwiftSoup),
│              MarkdownReader (swift-markdown 0.9.0), AttributedReader (RTF/RTFD/clipping/TXT), PagesReader (cupertino-files),
│              PDFStructureReader (PDFKit + Vision)
├── Writers/   DOCXWriter (own WordprocessingML + our own styles.xml/numbering.xml), EPUB3Writer, HTMLWriter (+print CSS),
│              MarkdownWriter (swift-markdown MarkupFormatter), TXTWriter, RTFWriter (via NSAttributedString), PagesWriter (cupertino-files),
│              PPTXImageWriter (PDF→PPTX: one picture per slide + optional text boxes), PDFWriter (HTMLWriter → RenderHost)
├── RenderHost/ @MainActor pool of 2 off-screen WKWebViews; scheme handler zivlet-doc://; content rules; printOperation & createPDF;
│              PDFKit merge + page-number stamping; rasterizer (PDF page → CGImage → ImageIO PNG/JPG at N dpi)
├── JSHost/     JSContext runner (SheetJS, mammoth, cupertino-files) in the conversion helper; polyfills; per-job memory/time caps
├── Sheets/     SheetJS bridge: read any → workbook JSON; write xlsx/ods/csv/tsv; workbook → styled HTML for PDF
├── OfficeEngine/ LibreOffice discovery/download/verify; batch one-shot runner; (later) LOK helper client
└── IWorkBridge/  opt-in Apple Events export (NSAppleScript/OSAKit in helper; entitlement automation.apple-events)
```

**Why our own SDoc and not "everything through Pandoc".** SDoc is the hub for routes no external engine serves well: PDF → DOCX/Pages (Vision), Pages ↔ DOCX (cupertino-files), and EPUB/MD/TXT writers that must work offline in the core app. Keep it deliberately small, about 25 node types. Layout-faithful renders (DOCX/PPTX → PDF/PNG) bypass SDoc and go straight to the renderers.

### 6.2 Engine selection

Each route declares an ordered list of engines with a **capability check**: `isAvailable()`, `fidelity: .semantic | .layout | .exact`, `costEstimate`. The router picks by the user's **Document fidelity** setting:

- **Automatic (default).** Use the Office Engine or the iWork apps for *layout* routes (DOCX/PPTX/PPT/XLSX/XLS/ODS → PDF/PNG/JPG; Pages → PDF) **when they are already present**. Otherwise use Tier 1. Never block a drop to ask for a download, except PPT/DOC, which have no Tier 1 path.
- **Fast (native only).** Never launch external engines.
- **Best fidelity.** Always prefer the Office Engine or iWork, and prompt for the download if it is missing.

Every result records the engine used, so the "Details" popover can say, for example, "Rendered with LibreOffice 26.8.1 · fonts substituted: Aptos → Carlito". That is one of Zivlet's transparency goals.

### 6.3 Key code paths (sketches)

**Paginated HTML → PDF (MEASURED working approach):**

```swift
@MainActor
func printToPDF(_ webView: WKWebView, in window: NSWindow, to url: URL, page: PageSetup) async throws {
    let info = NSPrintInfo(dictionary: [.jobDisposition: NSPrintInfo.JobDisposition.save, .jobSavingURL: url])
    info.paperSize = page.size                       // from sectPr / user setting (A4 vs Letter by Locale)
    (info.topMargin, info.bottomMargin, info.leftMargin, info.rightMargin) = page.margins
    info.horizontalPagination = .fit; info.verticalPagination = .automatic; info.isVerticallyCentered = false
    let op = webView.printOperation(with: info)
    op.showsPrintPanel = false; op.showsProgressPanel = false
    op.view?.frame = webView.bounds                  // required, or WebKit prints blank pages
    try await op.runModal(for: window)               // async wrapper over runModal(for:delegate:didRun:contextInfo:)
}
```

The window is a borderless `NSWindow` at (-10000, -10000). It works in an `LSUIElement` / accessory app (MEASURED). Page numbers: reopen with PDFKit and draw them with a `PDFPage` subclass `draw(with:to:)` overlay, or a `PDFAnnotation` of type `.freeText` flattened on save.

**DOCX → PDF with docx-preview (an improvement over per-page `createPDF`):**
1. Load `zivlet-doc://render/docx.html` (docx-preview + JSZip + font aliases). `callAsyncJavaScript("return await renderDocx(b64, opts)")` with `{ breakPages: true, ignoreLastRenderedPageBreak: false, ignoreHeight: true, renderHeaders: true, renderFooters: true, renderFootnotes: true, useBase64URL: true }`.
2. JS returns the section list with page size and margins from `sectPr`. Inject print CSS: `section.docx { box-shadow:none; margin:0; padding: <margins>; break-after: page }` and `@page { size: <w>pt <h>pt; margin: 0 }`.
3. One `printOperation` lets WebKit paginate long sections that lack `lastRenderedPageBreak` hints. Documents saved by Word (which have hints) paginate almost like Word. Mixed page sizes: split by section into separate print runs, then merge with PDFKit.
4. PNG/JPG: rasterise the PDF pages. One page gives a file beside the original. Several pages go into a `<base> Pages/Page 001.png` folder (Zivlet's multi-page naming convention).

**PPTX → PDF/PNG with pptx-renderer:** render all slides into fixed-size containers at the native slide size (EMU → pt). Print with `@page { size: <slideW>pt <slideH>pt; margin:0 }` and `break-after: page` per slide, which gives one vector multi-page PDF. For PNG/JPG, use `WKWebView.takeSnapshot(with: WKSnapshotConfiguration(rect:snapshotWidth:))` per slide at 2× for crisp output, or rasterise the PDF. Disable animations and transitions. Charts render through ECharts (bundled, no network).

**LibreOffice batch (Tier 2):**

```swift
let args = ["-env:UserInstallation=\(profileURL.absoluteString)", "--headless", "--norestore", "--nolockcheck",
            "--nodefault", "--nologo", "--convert-to", "pdf:impress_pdf_Export", "--outdir", staging.path] + inputs.map(\.path)
// Process with environment trimmed (HOME → sandboxed tmp, no proxies); terminate → SIGKILL after 5 s; 120 s/file watchdog
```

PNG per slide or page: LibreOffice → PDF → our rasterizer, because `--convert-to png` stops at the first page (MEASURED).

**Vision document structure:**

```swift
let observations = try await RecognizeDocumentsRequest().perform(on: cgImage)
guard let doc = observations.first?.document else { return .empty }
let paragraphs = doc.paragraphs.map(\.transcript)
let tables = doc.tables.map { $0.rows.map { $0.map { $0.content.text.transcript } } }
let lists  = doc.lists.map { $0.items.map { $0.content.text.transcript } }
```

### 6.4 Process model and security

- **Conversion helper.** One bundled helper process (`ZivletWorker`, an XPC service; not sandboxed, hardened runtime) hosts JSHost, the readers and writers, Vision, and child-process supervision. Entitlement: `com.apple.security.cs.allow-jit` (JSC). **No network code** runs in the helper.
- **RenderHost.** Lives in the main app on the MainActor, because WKWebView needs a window-server session. WebKit already isolates content in WebContent processes. A renderer crash surfaces as `webViewWebContentProcessDidTerminate`, which we report as a failed job and then rebuild the web view.
- **Offline enforcement:**
  - A `WKContentRuleList` blocks `^https?://`, `^file://`, and `^ftp://`.
  - The custom scheme serves only bundled assets and the job's blob.
  - `WKWebsiteDataStore.nonPersistent()`.
  - JavaScript `window.open` and navigation are blocked by the navigation delegate.
  - pptx-renderer is built with no remote media (it ships "external-media controls"). For @silurus/ooxml, `useGoogleFonts:false`.
- **Input hardening** (Zivlet's spec): a 128 MB input cap; ZIP entry and ratio limits (zip-bomb guard: total uncompressed ≤ 1 GB, ratio ≤ 100); refuse symlinks and `..` in entry names; reject DTD/ENTITY in XML (XXE); EPUB `META-INF/encryption.xml` → "DRM/obfuscated" refusal; password-protected Office (CFB `EncryptionInfo`) and iWork are refused with clear copy; PDF `isEncrypted`/`allowsCopying` checks.
- **LibreOffice hardening:**
  - A private profile, seeded with a `registrymodifications.xcu` that sets macro security to *Very High*, disables update checks, sets `BlockUntrustedRefererLinks=true`, and turns off linked-content updates (OLE/DDE/external images), so documents cannot fetch remote resources.
  - A trimmed environment.
  - A process-group kill on cancel.
  - Never pass user-controlled strings into filter options.
- **Apple Events:** sent only after the user enables "Use iWork apps when installed". One-time TCC prompts, with our own explanation shown first.

### 6.5 Concurrency and performance

- WKWebView pool: 2 views. JSContext pool: 2 contexts, each warm-loaded with SheetJS, mammoth, and cupertino-files on first use. That costs about 30–60 MB RSS each (ESTIMATE). Idle contexts are dropped after 60 s.
- `NSAttributedString` RTF work runs off-main (RTF/RTFD do not need WebKit). We **never** use `NSAttributedString` HTML import.
- **Batching:**
  - LibreOffice: one process per (filter, batch) group.
  - Pandoc (if present): one process per file. Its 0.03 s start makes batching unnecessary.
- Progress sources:
  - docx-preview / pptx-renderer: page or slide index ÷ count via `WKScriptMessageHandler`.
  - LibreOffice: per-file completion within a batch.
  - Vision: page index.

---

## 7. Office Engine: discovery, download, verification

1. **Discover.** Call `NSWorkspace.shared.urlsForApplications(withBundleIdentifier: "org.libreoffice.script")` and accept LibreOffice ≥ 24.8. Also accept a Zivlet-managed copy at `~/Library/Application Support/Zivlet/Engines/LibreOffice/<ver>/LibreOffice.app`. Validate it with `SecStaticCodeCheckValidity` and the requirement `anchor apple generic and certificate leaf[subject.OU] = "7P5S3ZLCN7"`.
2. **Offer.** Show a Settings → Engines card: "Office Engine (LibreOffice 26.8.1) — adds PowerPoint 97–2003 support and Office-accurate PDFs. 299 MB download, 805 MB on disk." The same offer appears inline the first time a PPT/DOC file is dropped. Never download automatically.
3. **Download.**
   - Source: `https://download.documentfoundation.org/libreoffice/stable/<ver>/mac/aarch64/LibreOffice_<ver>_MacOS_aarch64.dmg` (mirror-redirected).
   - Use resumable `URLSessionDownloadTask` in the main app, not the worker.
   - Verify against an **engines manifest** shipped and updated via Sparkle (EdDSA-signed by us). It pins version, size, and SHA-256, and we optionally also check TDF's `.asc` GPG signature in CI when we update the manifest.
4. **Install.** Use `diskutil image attach --readOnly --mountOptions nobrowse` (`hdiutil attach` is deprecated in this OS build; MEASURED warning), `ditto` the app into the Engines folder, detach, re-verify the code signature, and record the version. Uninstall is a button. Downloaded files are quarantined, so clear quarantine only after signature validation, or leave it in place: Gatekeeper accepts the notarized app (MEASURED).
5. **Licensing.** We do not redistribute LibreOffice. We link to TDF's license and notices on the card.

---

## 8. Per-route tiered strategy

Legend: **T1** = in-app native/JS (always available) · **T2-LO** = Office Engine · **T2-iW** = iWork app via Apple Events · Q = expected quality on a 1–5 scale (ESTIMATE until the §10 corpus results).

### 8.1 Word-processing family

| Route | T1 engine (Q) | T2 (Q) | Notes |
|---|---|---|---|
| docx → pdf | docx-preview → WKWebView print (3.5) | LO writer_pdf_Export (4.5) | Automatic uses LO only if already installed |
| docx → png/jpg | docx-preview → PDF → raster (3.5) | LO → PDF → raster (4.5) | multi-page → folder |
| docx → md / txt / html | mammoth → SDoc → writer (4.5) | — (Pandoc oracle) | style map for Title/Subtitle/Quote/Code |
| docx → epub | mammoth → SDoc → EPUB3 (4) | — | split chapters on H1 (H2 fallback) |
| docx → pages | mammoth → SDoc → cupertino-files (3.5) | T2-iW: Pages open + save (5) | images, lists, tables, footnotes |
| pages → pdf | cupertino-files → SDoc → HTML print (3) | T2-iW Pages export PDF (5); LO/libetonyek (2.5) | `preview.jpg` only as a last resort |
| pages → docx | cupertino-files → SDoc → DOCXWriter (3.5) | T2-iW Pages export Word (5) | |
| pages → txt/md/html/epub | cupertino-files → SDoc (4) | T2-iW EPUB / text (5) | |
| pages → png/jpg | pages → pdf path → raster | T2-iW | |
| md → * | swift-markdown → SDoc → writer (4.5); md → pdf via HTMLWriter + print CSS (4) | — | GFM tables and task lists |
| txt → * | plain → SDoc (paragraphs split on blank lines) (5) | — | encoding detection (UTF-8/16 BOM, then `String(contentsOf:usedEncoding:)`) |
| rtf/rtfd/clipping → * | NSAttributedString → SDoc (4.5) | — | RTFD attachments → assets |
| epub → pdf | EPUBReader → per-spine XHTML in WKWebView (book CSS kept, scripts disabled) → print → merge (4) | LO (2.5) | |
| epub → docx/pages/txt/md/html | EPUBReader → SDoc (4) | — | refuse DRM |
| odt → * (extra) | **T2-LO** (4.5); T1 later via our own ODF reader (P2) | Pandoc pack | ODT is not in the core route matrix |
| doc → * (extra) | ✗ | **T2-LO** (4.5) | needs the Office Engine |

### 8.2 Slides

| Route | T1 (Q) | T2 (Q) | Notes |
|---|---|---|---|
| pptx → pdf | pptx-renderer → print (4) | LO impress_pdf_Export (4); T2-iW Keynote export PDF (4.5) | |
| pptx → png/jpg | pptx-renderer snapshot @2× (4) | LO/Keynote → raster | folder `<base> Slides/Slide 001.png` |
| ppt → pdf/png/jpg | ✗ (S-RENDER: try the @silurus legacy add-on as an experimental T1) | **T2-LO** (4); **T2-iW Keynote** (4.5) | The slice shows "Needs Office Engine or Keynote" if neither is present |
| pdf → pptx | PDFKit raster per page → PPTXImageWriter (+ optional OCR text boxes) (baseline) | — | |
| keynote → pdf/pptx/png (extra) | cupertino-files → our slide HTML (2.5) | **T2-iW Keynote** (5) | P2 |

### 8.3 Spreadsheets

| Route | T1 (Q) | T2 (Q) | Notes |
|---|---|---|---|
| xlsx/xls/ods/csv/tsv → xlsx/ods/csv/tsv | SheetJS CE (4.5 data; styles dropped on xlsx ↔ ods in CE) | LO calc8 / Calc MS Excel 2007 XML (4.5 with styles) | Say "Formatting simplified" when a styled source goes T1 xlsx → ods. CSV options: UTF-8 with BOM for Excel compatibility (setting), delimiter, `;` locales. |
| multi-sheet → csv/tsv | SheetJS per sheet → `<base> Sheets/<Sheet>.csv` | — | |
| * → pdf | SheetJS → styled HTML (gridlines, bold header, number formats via SSF, merges, column widths, auto-landscape when wide, repeat header row, a section per sheet) → print (2.5–3) | **LO calc_pdf_Export (4.5)**: honours print areas, page setup, charts | The strongest reason to install the Office Engine for spreadsheet users. umya-spreadsheet can raise T1 styled output to about 3.5 later. |
| pdf → xlsx | Vision tables → SheetJS writer (3.5) | — | |
| numbers → xlsx/csv/pdf (extra) | cupertino-files / SheetJS read (3) | T2-iW Numbers export (5) | P2 |

### 8.4 PDF and image extraction

| Route | T1 (Q) | Notes |
|---|---|---|
| pdf → txt | PDFKit text + Vision for scanned pages (4.5) | reading order from Vision |
| pdf → md | fusion → SDoc → MD (4) | headings, lists, tables as GFM |
| pdf → docx "editable" | fusion → SDoc → DOCXWriter (3.5) | report: "Layout approximated · 3 tables · 2 pages OCR'd" |
| pdf → docx "preserve pages" | page images (300 dpi JPEG) in a DOCX, one per page with section margins 0 (4 visual / 1 editable) | |
| pdf → epub reflow / fixed | fusion → EPUB3 reflowable (3.5) / pre-paginated EPUB with page images (4.5 visual) | a frequently requested route |
| pdf → pages | fusion → SDoc → cupertino-files (3) | |
| image → docx (OCR, extra) | Vision RecognizeDocuments → SDoc → DOCX (3.5) | |

---

## 9. Size budget (core app, document engine share)

| Component | Size (installed) | Source |
|---|---|---|
| SheetJS CE 0.20.3 | 0.95 MB | MEASURED |
| mammoth 1.13.0 | 0.41 MB | MEASURED |
| docx-preview 0.4.1 + JSZip 3.10.1 | 0.17 MB | MEASURED |
| pptx-renderer 1.4.0 bundle (+ ECharts, tree-shaken) | ~1.5–2.5 MB | ESTIMATE (5.5 MB unpacked npm includes ESM + CJS + types) |
| cupertino-files 0.4.0 bundle | ~1–1.5 MB | ESTIMATE (4.0 MB unpacked) |
| Fonts (Carlito, Caladea, Liberation, Gelasio, Selawik) | ~6–8 MB | ESTIMATE |
| Swift code (SDoc, readers/writers, SwiftSoup 2.14.3, swift-markdown 0.9.0 with cmark-gfm, ZIPFoundation 0.9.20) | ~2–3 MB | ESTIMATE |
| **Total** | **~12–16 MB** | well inside the "core < 60 MB" target |
| Office Engine (optional) | 805 MB | MEASURED, never in the DMG |
| Pandoc pack (optional, deferred) | 192 MB | MEASURED |

For comparison, a JRE + POI stack alone would be about 55–60 MB (ESTIMATE, §4.6).

---

## 10. Validation plan (spikes and corpus)

| Spike | Question | Pass bar | Effort |
|---|---|---|---|
| **S-DOCX** (was S7) | docx-preview + print pagination vs LO vs Word reference PDFs (Word is installed on the dev machine) on 40 DOCX files (Word, Google Docs, LibreOffice, and Pages authored; with TOC, floats, headers/footers, footnotes, RTL, CJK) | Median page-count delta ≤ 1 · median SSIM ≥ 0.85 vs Word · no lost text (character recall ≥ 99%) | 4 d |
| **S-RENDER** (was S11) | pptx-renderer vs LO vs Keynote vs PowerPoint ground truth on 30 decks (charts, SmartArt, masters, embedded fonts). Also try @silurus/ooxml for PNG and legacy PPT. | Median SSIM ≥ 0.80 vs PowerPoint · zero blank slides · ≤ 2 s for a 30-slide deck | 4 d |
| **S-SHEET** | SheetJS on 30 workbooks (100k-row CSV, 2M-cell XLSX, BIFF5/8 XLS, ODS with merges, formulas cached) | Value equality 100% vs LO export · 2M cells under 15 s and under 1.5 GB RSS. Otherwise switch the reader to calamine. | 2 d |
| **S-PAGES** (was S10) | cupertino-files read/write on 20 Pages 13–14.5 docs, round trip through Pages 14.5 | Opens in Pages without a repair dialog · text recall ≥ 99% · images and tables kept | 3 d |
| **S-PDF** | Vision + PDFKit fusion on 20 born-digital + 20 scanned PDFs (tables, 2-column, footnotes) vs docling as a yardstick | Text recall ≥ 98% · table cell F1 ≥ 0.8 · headings F1 ≥ 0.7 | 5 d |
| **S-LO** | Office Engine: download, verify, install, and batch convert. LOK helper prototype for warm latency. | Install in under 3 min on 100 Mb/s · warm LOK under 0.5 s per small DOCX | 3 d |
| **S-WRITERS** | Our DOCX, EPUB, MD, and HTML writers vs Pandoc output (oracle) on SDoc fixtures. EPUBCheck 5 must pass. DOCX must open in Word, Pages, and LO without repair. | 0 EPUBCheck errors · 0 repair prompts | 3 d |

Regression harness: golden outputs per route, plus an image-diff (SSIM) stage in CI on macOS 26 runners. Test against the *capability matrix* too, so a route can never silently disappear (a "hidden options" regression is a known failure mode for converter apps).

---

## 11. RECOMMENDATION

### Choice

1. **Tier 1 (ships in the core app, offline, about 12–16 MB):**
   - Apple frameworks: PDFKit; Vision `RecognizeDocumentsRequest`; `NSAttributedString` for RTF/RTFD/clippings only; `WKWebView.printOperation` as the universal paginated-PDF backend; PDFKit for merging and stamping.
   - **docx-preview** for DOCX → PDF/PNG.
   - **mammoth** for DOCX semantics.
   - **@aiden0z/pptx-renderer** for PPTX → PDF/PNG.
   - **SheetJS CE 0.20.3** for all spreadsheet reads, writes, and data-faithful PDF.
   - **cupertino-files** for Pages read and write.
   - Our own **SDoc** model with DOCX, EPUB 3, HTML, MD, TXT, RTF, and Pages writers.
   - **ZIPFoundation**, **SwiftSoup**, **swift-markdown**.
   - Metric-compatible fonts (Carlito, Caladea, Liberation, and others).
2. **Tier 2a, Office Engine = LibreOffice 26.8.x, on demand.** Never bundled and never modified. Use an existing install, or a one-click download of TDF's notarized arm64 build, verified by a pinned SHA-256 and Team ID. Start with a v1 batch `soffice --convert-to` runner, then add a v1.x resident LibreOfficeKit helper (`disable-library-validation` on the helper only). Used for PPT/DOC (required), and for Office-accurate DOCX/PPTX/XLSX/XLS/ODS → PDF/PNG when present or when the user picks "Best fidelity".
3. **Tier 2b, iWork apps, opt-in.** Apple-Events export from Pages, Keynote, and Numbers when installed. This is the highest-fidelity path for iWork sources and a PPT alternative through Keynote.
4. **Not shipped:**
   - Apache POI + JRE.
   - WeasyPrint.
   - Typst (revisit for a P2 "Beautiful PDF" theme).
   - MuPDF.
   - unoserver.
   - CoreXLSX.
   - Pandoc stays a CI oracle and a deferred optional pack.

### Rationale

- It meets the full route matrix offline in about 14 MB, roughly a quarter of what a JRE + POI stack alone would cost (about 55–60 MB), with **no JVM**. It also aims to beat a POI-based stack on several routes:
  - real pagination for DOCX without break hints;
  - vector PPTX output with charts and SmartArt;
  - Vision-structured PDF → DOCX/XLSX on macOS 26;
  - an honest per-result engine and substitution report.
- Users who need Office-grade fidelity, or PPT/DOC, get it without anyone else paying 805 MB. The direct-download, unsandboxed decision makes the download, child processes, and LibreOfficeKit straightforward.
- Licenses are all permissive (Apache, BSD, MIT, OFL) inside the bundle. GPL/MPL engines stay external, which keeps Zivlet's GPLv3 licensing simple.
- Each JavaScript library runs in an isolated, network-blocked WebKit or JSC host with strict input caps, so a malformed document cannot reach the network or the main process.

### Risks

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| pptx-renderer and cupertino-files are young (2026), with one maintainer each | Med / High | Pin versions and vendor builds with hashes. Keep a corpus and SSIM gates. Keep LO/Keynote fallbacks. Budget time to fork and patch (Apache/MIT allow it). |
| docx-preview pagination is approximate for long documents without Word hints | High / Med | Print-driven pagination (§6.3). Label the result "Layout approximated". Automatic mode prefers LO when installed. Evaluate the @silurus/ooxml paginator for PNG. |
| SheetJS CE drops styles, so xlsx → ods and xlsx → pdf look plain | High / Med | Clear "Formatting simplified" copy. LO path. Later, umya-spreadsheet for styled reads. |
| Vision `RecognizeDocumentsRequest` quality and language coverage vary | Med / Med | Fuse with the PDFKit text layer. Fall back to `RecognizeTextRequest`. Expose an OCR language setting. Run the S-PDF corpus. |
| LibreOffice size, first-run latency (12.7 s), and its CVE history | Med / Med | Opt-in only. Private hardened profile, macro security Very High, linked content off. Pinned manifest with fast Sparkle updates. Watchdogs. |
| Apple Events prompts confuse users, and iWork apps launch visibly | Med / Low | Opt-in toggle with an explainer. Run hidden (`launch` without activating). Never use it by default. |
| The JS host needs `allow-jit` and polyfills (TextDecoder missing in JSC; MEASURED) | Low / Low | Put the entitlement on the helper only. Keep a polyfill shim under unit tests. Alternatively host in WKWebView. |
| Fonts: Aptos and other non-cloned fonts change line breaks | High / Low–Med | Prefer installed fonts. Report substitutions. LO path. |
| Our SDoc writers take longer than planned | Med / Med | Pandoc fallback (below). Keep SDoc small. Use EPUBCheck and Word/LO/Pages open tests as gates. |

### Fallback

- **If the Tier 1 renderers miss the S-DOCX or S-RENDER bars,** make the Office Engine the recommended default for layout routes: a first-run card offers the download, and Tier 1 stays as the offline fallback. For PPTX, also ship the Keynote bridge enabled-by-prompt.
- **If our SDoc writers slip,** bundle Pandoc 3.12.x (GPL-2+, compatible). That costs +192 MB installed and about +40 MB in the DMG, or 61 MB as `pandoc.wasm` in WKWebView if a spike proves its speed. Route DOCX/ODT/EPUB/RTF/HTML/MD conversions through SDoc → Pandoc JSON AST → Pandoc writers.
- **If SheetJS fails S-SHEET on scale,** swap the reader and writer to a Rust staticlib (calamine 0.37 + rust_xlsxwriter 0.100, plus our own ODS writer) behind the same `Sheets` protocol.
- **If cupertino-files breaks on a new Pages version,** degrade Pages read to a `preview.jpg` + text extraction notice. Route Pages output through T2-iW when Pages is installed, and otherwise hide the Pages slice for that source, with a clear reason.

---

### Sources

- Pandoc 3.12.1 release assets: https://github.com/jgm/pandoc/releases/tag/3.12.1
- Typst v0.15.1: https://github.com/typst/typst/releases/tag/v0.15.1
- LibreOffice 26.8.1 macOS aarch64: https://download.documentfoundation.org/libreoffice/stable/26.8.1/mac/aarch64/
- unoserver README: https://github.com/unoconv/unoserver
- docx-preview: https://github.com/VolodymyrBaydalka/docxjs (npm `docx-preview` 0.4.1)
- mammoth.js: https://github.com/mwilliamson/mammoth.js (npm 1.13.0)
- pptx-renderer: https://github.com/aiden0z/pptx-renderer (npm `@aiden0z/pptx-renderer` 1.4.0)
- office-open-xml-viewer: https://github.com/yukiyokotani/office-open-xml-viewer (npm `@silurus/ooxml` 0.89.1)
- SheetJS CE 0.20.3: https://cdn.sheetjs.com/ · https://git.sheetjs.com/SheetJS/sheetjs
- cupertino-files: https://github.com/den-frie-vilje/cupertino-files · WorkKit: https://github.com/6over3/WorkKit
- calamine https://github.com/tafia/calamine · rust_xlsxwriter https://github.com/jmcnamara/rust_xlsxwriter · umya-spreadsheet https://github.com/MathNya/umya-spreadsheet · CoreXLSX https://github.com/CoreOffice/CoreXLSX · libxlsxwriter https://github.com/jmcnamara/libxlsxwriter · libxls https://github.com/libxls/libxls
- ZIPFoundation https://github.com/weichsel/ZIPFoundation · SwiftSoup https://github.com/scinfu/SwiftSoup · swift-markdown https://github.com/swiftlang/swift-markdown
- Apache POI 5.5.1 / PDFBox 3.0.8: Maven Central metadata
- MuPDF 1.28.5 (AGPL): https://github.com/ArtifexSoftware/mupdf · WeasyPrint v70.0: https://github.com/Kozea/WeasyPrint
- Apple SDK (macOS 26): Vision `RecognizeDocumentsRequest` / `DocumentObservation` swiftinterface; WebKit `WKWebView printOperationWithPrintInfo:`; `WebPage.ExportedContentConfiguration` symbols in `WebKit.tbd`
- Local `.sdef` files: Keynote/Pages/Numbers 14.5
