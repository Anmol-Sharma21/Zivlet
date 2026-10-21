# 10 — Zivlet Technical Strategy (synthesis of 11–14)

Date: 2026-10-20. Status: **synthesis for owner decision**. This document pulls the four engine and platform designs into one plan.
Inputs (read in full): [00-decisions](00-decisions.md), [11-media-engine](11-media-engine.md), [12-document-engine](12-document-engine.md), [13-image-pdf-engine](13-image-pdf-engine.md), [14-app-platform](14-app-platform.md). Background: Zivlet's product scope (275-pair format matrix, 27 tools, 6 actions).

Ground rules carried over:
- Zivlet is a free, open-source macOS app. It is downloaded directly, notarized with Developer ID and **not sandboxed**. It needs **macOS 26+** and targets Apple silicon first. It is built with Swift 6 and SwiftUI/AppKit.
- No code, templates, sounds or art from the reference app or Open-Tangerine is reused. Their public behaviour is only a baseline to beat.

Evidence tags are inherited from 11–14: **MEASURED/PROBED/VERIFIED-LOCAL** (run on the dev Mac), **SOURCE/DOC/VERIFIED-UPSTREAM** (read from upstream), **ESTIMATE/INFERRED** (reasoned, not measured), **SPIKE** (must be proven).
- Every local probe ran on **macOS 27.0 (build 26A428)**, not on our 26.x minimum. Re-running them on 26.x is the first spike (G-0).
- Licence checks added in this synthesis (npm registry, google/fonts, Sparkle LICENSE, 2026-10-20) are marked **SOURCE**.

Items that need the owner's input are tagged **[OWNER]** where they come up and are collected in §15.

---

## 0. TL;DR

| Area | Decision |
|---|---|
| **Media** (audio 56, video 42, GIF 6 pairs; 15 media tools) | One self-built **FFmpeg 9.0.2 + ffprobe**, licensed GPLv3. Codecs: x264, libvpx 1.17, SVT-AV1 4.2, dav1d, Opus 1.6.1, Vorbis, LAME, libwebp, zimg, plus VideoToolbox and AudioToolbox. The libav\* libraries ship as shared dylibs with the codecs folded in, and ffmpeg/ffprobe run as child processes. AVFoundation is used only for previews, thumbnails and waveforms. WebM is VP9 + Opus, so WebM output actually works (every advertised encoder is linked and tested). |
| **Raster images** (49 pairs) | **ImageIO + Core Image**: 62 readable and 22 writable types (PROBED). **libwebp 1.6.0** runs in-process for still, animated and target-size WebP. P1 adds libjxl, oxipng and libimagequant. libvips is not used. |
| **SVG** (8 pairs) | **resvg 0.47.x** for raster output and **krilla 0.8 + krilla-svg 0.8.1** for vector PDF, sharing one `usvg 0.47` tree in one Rust static library with no external resource loading. Fallback order: NSImage, then offline WKWebView. *[challenge: svg2pdf 0.13 pins usvg/resvg ^0.45, so it cannot share a tree with resvg 0.48.1; see §3 note and 15 §C-3]* |
| **PDF** (pages, compress, protect, redact) | **PDFKit/Quartz** for merge, split, organize, images↔PDF and rasterising. Lossy compression uses a **Quartz filter built at runtime** (PROBED). **qpdf 12.4.2** handles lossless optimise, linearise, repair, AES-256 and revision scrub. Redaction v1 rasterises the affected pages; MuPDF is a v2 decision gate. |
| **Documents, slides, sheets, EPUB, Pages, PDF→editable** (≈110 pairs) | **Tier 1, in-app and offline:** WKWebView `printOperation` (paginated PDF), docx-preview, mammoth, @aiden0z/pptx-renderer, SheetJS CE 0.20.3, cupertino-files 0.4.0, our own **SDoc** model and writers, and Vision `RecognizeDocumentsRequest` fused with the PDFKit text layer. **Tier 2a (optional):** LibreOffice 26.8 from an existing install or a one-click verified download, never bundled. It is the only path for PPT. **Tier 2b (opt-in):** Pages, Keynote and Numbers via Apple Events. No Java, no POI, no Pandoc in the core app. |
| **Metadata** | **ExifTool 13.59** in a persistent `-stay_open` session on a **bundled trimmed Perl**, falling back to `/usr/bin/perl`. Every write goes read → plan → write → verify and fails closed. ffmpeg handles copy-only edits for formats ExifTool can't write (MP3/ID3, FLAC, Ogg, MKV, WebM, WMA). |
| **Archives** (9 pairs + Extract) | **libarchive 3.8.10** bundled statically, with path, symlink and bomb limits. It reads RAR4/RAR5 but never writes RAR. Encrypted RAR is unsupported, and unRAR is never shipped. |
| **Subtitles** (4 pairs) | Our own Swift `ZivletSubtitles` module, with encoding detection and fuzz tests. |
| **Vision** | Foreground masks, faces, `RecognizeDocumentsRequest` with data detectors (PII), barcodes. Models warm up in the background because the first text recognition took 58 s (PROBED, macOS 27). |
| **Trigger + wheel** | Permission-free. Mouse monitors wake the app; a display-synced sampler runs only during a file drag. The wheel is a pre-warmed non-activating `NSPanel` with an AppKit drop view and Liquid Glass petals drawn in SwiftUI. Accessibility and Input Monitoring are never required. |
| **Shell + release** | AppKit menu-bar app. Sparkle 2.10.0 with EdDSA and a signed feed on GitHub Pages; the DMG and deltas go on GitHub Releases. Every Mach-O is signed inside-out with hardened runtime and a timestamp, then notarized and stapled. Builds run on GitHub Actions `macos-26`, arm64 only. |
| **Process model** | The **app** runs UI, trigger, scheduler, WebKit renderer and actions. **`ZivletWorker.xpc`** (unsandboxed, no entitlements) runs every in-process parser and supervises child processes. **Helpers** (ffmpeg, ffprobe, perl/ExifTool, `zivlet-js`, `zivlet` CLI) are separate signed executables. LibreOffice, if present, runs as an external child. |
| **Project licence** | **GPL-3.0-or-later** **[OWNER]**. It is forced by the GPL FFmpeg build (x264) and libimagequant, and it is compatible with every other bundled component (§10). |
| **Size** | About **69 MB installed and about 30 MB DMG expected**. The range is 55–92 MB (§9). That is over the earlier 60 MB goal **[OWNER]**. |
| **Roadmap** | Phase 0 spikes → **Phase 1 MVP**: trigger, wheel, 153 image and media pairs, 5 actions, signed and updatable → **Phase 2 beta**: 221 pairs and 19 of 27 tools → **Phase 3 1.0 parity**: all 275 pairs, 27 tools, 6 actions, Intents, Services, CLI, worker → **Phase 4 1.x** beyond parity → **Phase 5 2.x**. |

---

## 1. Reconciliation log: where 11–14 disagreed and what this document decides

| # | Conflict | Sources | Decision here | Why |
|---|---|---|---|---|
| R-1 | Doc 14's bundle layout lists `cwebp` and a `jre/` folder, plus a `.jvm` lane | 14 §3.6, §5.2 vs 12 §4.6, 13 §2.3 | **No cwebp and no JRE.** WebP is libwebp in-process; Java/POI is rejected. Drop the `.jvm` lane and spike S-C2. | 12 and 13 both reject them with measurements. |
| R-2 | Where JavaScript libraries run | 12 §6.4 (JSContext inside `ZivletWorker` with `allow-jit`) | Move JS to a tiny **`Helpers/zivlet-js`** process (JSContext over JSON-over-stdio). Only that helper gets `com.apple.security.cs.allow-jit`. One warm instance stays up for 60 s when idle. | JSContext has no public interrupt. A separate process can be killed on cancel or timeout without killing other worker jobs. It keeps JIT off the worker, and the CLI can reuse it. Without the entitlement JSC still runs, only slower (INFERRED; spike D-JS). |
| R-3 | How many isolation processes | 11 (children only), 12 (worker with JIT), 13 ("one engine helper"), 14 (`ZivletWorker.xpc` by 1.0) | **One `ZivletWorker.xpc`**: unsandboxed, hardened runtime, **no entitlements**. It hosts ImageIO, Core Image, PDFKit, Vision, libwebp, resvg, qpdf, libarchive and the SDoc readers and writers, and it spawns ffmpeg, perl and zivlet-js. **WKWebView rendering stays in the app** because it needs a window-server session (12 §6.4). | One IPC boundary, crash isolation for every in-process C/C++/Rust parser, and the same `Engine` protocol in-process as a fallback (14 fallback). |
| R-4 | Job lanes and their widths | 11 §8.3 (remux 4, audio P-cores, hwVideo 2, swVideo 1) vs 14 §5.2 (cpu, ffmpegSoftware pCores/4, mediaEngine 2, webkit 1, jvm 1) | One merged lane table (§8.1). swVideo width is **1**: each encoder is already multithreaded, and 11 measured VP9 at 0.53× realtime. render width is 2 (the 12 §6.5 pool). | Measured data wins. Widths can be overridden in Settings › Advanced. |
| R-5 | Cancellation timing | 11: SIGTERM, then SIGKILL after 2 s. 14: SIGINT 800 ms → SIGTERM 2 s → SIGKILL. Earlier goal: "hard cancel ≤ 500 ms". 12: LibreOffice SIGTERM, then SIGKILL after 5 s | Split the target in two. **User-visible cancel ≤ 100 ms**: the job is marked cancelled, its staging is discarded and nothing is ever published. **Process gone ≤ 1 s** for ffmpeg and ExifTool (SIGINT, SIGKILL at +1 s, whole process group). **≤ 5 s** for LibreOffice. | ffmpeg finalises on its first signal. Because outputs are staged, a slow teardown can't leak a partial file, so the strict 500 ms only matters for what the user sees. |
| R-6 | Who edits audio and video metadata | 11 §11 (ffmpeg for all) vs 13 §5.4 (ExifTool for MP4/MOV/M4A) | **ExifTool** edits MP4/MOV/M4A/HEIF-video (QuickTime Keys, including GPS, written without touching media data). **ffmpeg copy-only** handles MP3, FLAC, OGG, Opus, WAV, AIFF, WMA, MKV, WebM, AVI and WMV, which ExifTool can't write. | ExifTool can't write ID3, FLAC or Ogg. `-map_metadata -1` may leave QuickTime `Keys` items it doesn't map (spike M-META). |
| R-7 | How video redaction is rendered | 11 §11 (ffmpeg `drawbox`/`gblur` filter script) vs 13 §8.3 (AVVideoComposition Core Image handler) | **ffmpeg renders. Vision only detects and tracks.** | One pipeline for every container, including MKV and WebM, which AVFoundation can't read. |
| R-8 | PDF → JPG/PNG default resolution | 13 §4.2 (150 DPI) vs the product scope ("300 DPI") | **300 DPI default** (parity). Presets 72/150/300/600, capped at 16,384 px and 200 MP. | Matches the promised behaviour. The pixel cap prevents memory blowups. |
| R-9 | Fonts in the document engine | 12 §4.10 (Carlito, Caladea, Liberation, Gelasio, Selawik: 6–8 MB) | Ship **Carlito and Caladea** (OFL, 4 styles each) plus **Selawik**. Drop Liberation and Gelasio, because macOS ships Arial, Times New Roman, Courier New and Georgia. | Saves about 4–5 MB (ESTIMATE). The fidelity loss is nil, since the real fonts exist. |
| R-10 | Size goal | earlier product goal (< 60 MB core) vs sum of 11+12+13 (≈ 55–92 MB) | New target **≤ 70 MB installed / ≤ 32 MB DMG**, with a CI gate at 85 / 40 MB **[OWNER]**. | 60 MB can't hold a full-codec GPL FFmpeg, ExifTool + Perl and the document stack together without dropping routes. |
| R-11 | Early draft architecture and licence | early product-scope draft (sandboxed XPC, macOS 13, LGPL FFmpeg, MIT/proprietary licence, paywall) | **Superseded** by 00-decisions and 11–14. Unsandboxed, macOS 26+, GPLv3, free. | Owner decisions are locked. |
| R-12 | Where the Apple Events entitlement lives | 12 §4.8 (worker), 14 §3.6 (app) | **App only.** The iWork bridge and the Finder-selection hotkey both run in the app on the main actor. | The TCC Automation consent is then attributed to "Zivlet", and the worker keeps zero entitlements. |
| R-13 | Spike IDs collide (11 and 13 both have "S-3") | 11–14 | Renamed by prefix: **M-** media, **D-** documents, **I-** image/PDF, **P-** platform, **G-** global (§13). | Unambiguous tracking. |
| R-14 | When to copy streams instead of re-encoding | 11 §10: remux only if *all* kept streams fit | **Decide per stream.** Copy each stream whose codec the target container allows, and re-encode only the others (e.g. MP4 H.264 + AAC → AVI copies the video and re-encodes the audio to MP3). | Faster and lossless for the video. Guarded by the A/V-sync check in the pair tests (spike M-COPY). |

---

## 2. System architecture

### 2.1 Process model

```
┌──────────────────────────── Zivlet.app (LSUIElement, @MainActor UI) ─────────────────────────────┐
│ Shell: NSStatusItem/NSMenu · Settings · Onboarding · Sparkle 2.10 · SMAppService                   │
│ Trigger: mouse monitors → frame sampler → TriggerMachine (pure)                                     │
│ Wheel: WheelPanel (NSPanel) · WheelDropView (NSDraggingDestination) · SwiftUI glass petals         │
│ Runtime: JobScheduler (actor, lanes) · Publisher (staging → RENAME_EXCL) · UndoLog · OrphanReaper  │
│ RenderHost (@MainActor): 2× off-screen WKWebView, zivlet-doc:// scheme, content rules, print→PDF  │
│ Actions: AirDrop · Float shelf · Copy · Move · Copy Path · Terminal (all in-app, no worker)        │
│ Integrations: App Intents (app target) · Services provider · zivlet:// (UI only) · iWork bridge   │
└───────────────┬───────────────────────────────────────────────────────────────┬───────────────────┘
                │ XPCSession, Codable WorkerRequest/Event (progress, cancel)    │ posix_spawn (opt-in)
┌───────────────▼────────────── ZivletWorker.xpc (unsandboxed, no entitlements) ┐   LibreOffice.app
│ links ZivletEngines.framework (dynamic, embedded once)                        │   (TDF-signed, external,
│  EngineImage: ImageIO · Core Image · libwebp · resvg/krilla-svg · oxipng/imagequant│    soffice --headless)
│  EnginePDF: PDFKit/Quartz filters · qpdf (qpdfjob JSON)                         │
│  EngineDocs: SDoc readers/writers · Sheets bridge · PDF+Vision fusion           │
│  EngineArchive: libarchive (hardened) · EngineSubtitles · EngineVision          │
│  EngineMedia: argv planner · ffprobe JSON · runner │ EngineMetadata: ExifTool    │
│  SubprocessRunner (swift-subprocess 1.0.2, own process group, PID files)        │
└──────┬──────────────────┬──────────────────────┬────────────────────────────────┘
       ▼                  ▼                      ▼
 Helpers/ffmpeg     Helpers/perl + exiftool   Helpers/zivlet-js (JSContext; allow-jit)
 Helpers/ffprobe    (-stay_open session)      SheetJS · mammoth · cupertino-files
```

Rules:
1. **The app never parses an untrusted file in-process.** The two exceptions are UTType sniffing and Quick Look thumbnails, and WebKit already isolates rendered content in its WebContent process.
2. **The worker never touches UI or network.** It is unsandboxed, so its "no network" status is a code property rather than an OS guarantee (honest limitation; P-8 is the post-1.0 sandboxed worker).
3. **The CLI** (`Helpers/zivlet`) links `ZivletEngines.framework` in-process and spawns the same helpers. It hands off routes that need WebKit (DOCX/PPTX/EPUB/HTML/MD/TXT/RTF/Pages → PDF/PNG/JPG and spreadsheet → PDF) to the app over a Mach service, launching it hidden if needed (spike P-CLI).
4. **Fallback** (14): if the worker slips past 1.0, engines run in-process behind the same protocol. Only the `WorkerClient` implementation changes.

> [challenge] **Rule 1 is overstated, Rule 3's transport is unspecified, and the drop target needs an operation-mask rule (15 §C-6, §C-7, §C-8).**
> - **In-app parsing.** The tool editors decode untrusted files in the app process: Edit Photo, Annotate, Crop and Redact (Core Image previews), Organize PDF (`PDFThumbnailView`), Trim/Snapshots (`AVPlayer`, `AVAssetImageGenerator`) and Trim Audio (`AVAudioFile` waveform). Rule 1 now reads: *only Apple-framework decoders run in the app, and only for previews in an editor window the user opened. Every third-party parser (libwebp, resvg, qpdf, libarchive, SDoc readers, JS) runs in the worker or a helper.* Editor previews should prefer worker-rendered proxies (a downsampled PNG, an ffmpeg proxy) when the source is not a format AVFoundation or ImageIO handles natively.
> - **CLI → app hand-off.** A plain `LSUIElement` app can't vend a Mach service name. `NSXPCListener(machServiceName:)` needs a launchd job. Choose one: (a) an `SMAppService.agent(plistName:)` launch agent whose plist declares `MachServices`, hosted by the app; or (b) a Unix-domain socket in `~/Library/Application Support/Zivlet/` that checks the peer's code signature from its audit token (`SecCodeCreateWithAuditToken` with our Team ID requirement). (b) is simpler and needs no login-item UI. Spike P-CLI decides.
> - **Drag operation mask.** While the user holds a modifier, Finder narrows `draggingSourceOperationMask`: ⌃ gives `.link`, ⌥ gives `.copy`, ⌘ gives `.generic`/`.move`. A drop view that always returns `.copy` therefore **rejects** the drop if the user is still holding ⌃ (Actions) or ⌘ (Tools) at release. `draggingUpdated` must return the first of `.copy, .generic, .link, .move` that is present in the mask. Zivlet always applies **copy semantics**, so it never deletes or moves the source because of the negotiated operation; only the explicit Move action moves files. Add this to the P-T1 and P-T5 real-drag matrix.

### 2.2 Bundle layout

```
Zivlet.app/Contents/
  MacOS/Zivlet
  Helpers/       ffmpeg  ffprobe  perl  zivlet-js  zivlet        ← each Mach-O signed, hardened runtime
  (no perl-lib here: see the challenge note below; the Perl lib lives in Resources/perl5/)
  Frameworks/    libavcodec.63  libavformat.63  libavfilter.12  libavutil.61  libswscale.10  libswresample.7 (.dylib)
                 ZivletEngines.framework   (Swift engines + static libwebp, libarchive+xz/zstd/lz4, libqpdf+libjpeg-turbo, libzivlet_rs)
                 Sparkle.framework          (Autoupdate, Updater.app, XPCServices)
  XPCServices/   ZivletWorker.xpc
  PlugIns/       ZivletFinderSync.appex   (1.x)
  Resources/     exiftool/ (pure-Perl lib, no Lang/)  perl5/ (trimmed Perl lib: .pm files + individually signed XS *.bundle)
                 js/ (pinned bundles + SHA-256 manifest)  fonts/  sounds/
                 Licenses/ (generated SPDX + texts)  engines-manifest.json (LibreOffice pins, EdDSA-signed)
```

> [challenge] **Two layout errors fixed (see 15-strategy-challenge §C-1, §C-2).**
> - **Sonames were wrong for FFmpeg 9.0.** The earlier list was the FFmpeg 8.x set (it matches the Homebrew 8.1.2 build on the dev Mac). FFmpeg 9.0.2 ships libavcodec 63.1, libavformat 63.1, libavfilter 12.1, libavutil 61.1, libswscale 10.1 and libswresample 7.1 (ffmpeg.org/download, 2026-10-20). If we fall back to 8.1.3 the 62/11/60/9/6 set comes back. The `install_name` rewrite and `verify-media.sh` should therefore read the sonames from the build, not hard-code them.
> - **`Helpers/perl-lib/` contradicted §11.2 ("non-Mach-O scripts go in Resources/").** `Contents/Helpers` is a nested-code location. `codesign` signs non-Mach-O files there by writing the signature into extended attributes, and those attributes are lost in zip and DMG transport, so verification fails. The pure-Perl `.pm` tree and its XS `.bundle` files now go under `Resources/perl5/`. The XS bundles are still signed one by one, with hardened runtime and a timestamp, before the app is sealed. Library validation passes because they carry our Team ID. Only the `perl` Mach-O stays in `Helpers/`. This is the same pattern py2app and Briefcase use for `lib-dynload/*.so`.

Why `ZivletEngines` is a dynamic framework: the app (for render routes and the in-process fallback), the worker and the CLI all link it. A static link would ship about 15–20 MB of native libraries three times (ESTIMATE).

---

## 3. Engine stack per capability (summary)

| Capability | Primary | Bundled add-on | Optional / external | Rejected |
|---|---|---|---|---|
| Audio/video/GIF convert and tools | ffmpeg 9.0.2 (GPLv3 build) | ffprobe | x265, libaom (build flags, off) | FFmpegKit (archived), libav\* in-process, AVFoundation as converter, fdk-aac |
| Raster decode/encode | ImageIO + Core Image | libwebp 1.6.0 | libjxl 0.12 (P1), jpegli (P2) | libvips, cwebp CLI |
| PNG/JPEG size optimisation | ImageIO | oxipng 10.2 + libimagequant (Rust lib, 1.0) | jpegli (P2) | mozjpeg |
| SVG | resvg 0.47.x / krilla-svg 0.8.1 (one usvg 0.47) | — | NSImage, WKWebView fallbacks | librsvg; svg2pdf 0.13 (stale, pins usvg 0.45) |
| PDF structure | PDFKit/Quartz | qpdf 12.4.2 | MuPDF (v2 gate, AGPL), pdfium (if I-PDF1 fails) | Ghostscript |
| DOCX → PDF/PNG | docx-preview 0.4.1 → WKWebView print | — | LibreOffice 26.8 | Apache POI + JRE |
| PPTX → PDF/PNG | @aiden0z/pptx-renderer 1.4.0 → print | — | LibreOffice, Keynote | POI |
| PPT → PDF/PNG | — | — | **LibreOffice or Keynote (required)** | — |
| DOCX semantics | mammoth 1.13.0 | — | Pandoc pack (deferred) | NSAttributedString DOCX |
| Spreadsheets | SheetJS CE 0.20.3 | — | LibreOffice (styled PDF); calamine + rust_xlsxwriter (fallback) | CoreXLSX, npm `xlsx@0.18.5` |
| Pages read/write | cupertino-files 0.4.0 | — | Pages via Apple Events | WorkKit (AGPL) |
| PDF → editable | PDFKit text layer + Vision `RecognizeDocumentsRequest` → SDoc | — | — | MuPDF extract, docling, pdf2docx |
| RTF/RTFD/clippings | NSAttributedString | — | — | — |
| Markdown / HTML | swift-markdown 0.9.0, SwiftSoup 2.14.3 | — | — | NSAttributedString HTML import |
| ZIP containers (OOXML/EPUB/IWA) | ZIPFoundation 0.9.20 | — | — | — |
| Metadata | ExifTool 13.59 | trimmed Perl 5.42.x | `/usr/bin/perl` fallback | exiv2, ImageIO writes |
| Archives | libarchive 3.8.10 | xz 5.8.4, zstd 1.5.7, lz4 1.10 | 7zz without RAR (gated) | unRAR, system bsdtar |
| Subtitles | own Swift module | — | — | SwiftSubtitles |
| Vision | Vision framework (macOS 26) | — | `GenerateIterativeSegmentationRequest` (macOS 27, `#available`) | Tesseract, bundled CoreML |
| Process spawning | swift-subprocess 1.0.2 | — | Foundation.Process (fallback, spike M-4) | — |

> [challenge] **The resvg + svg2pdf pairing did not resolve to one dependency graph.** On crates.io (2026-10-20), `svg2pdf 0.13.0` is from 2025-03-04, it is the last release, and it requires `usvg ^0.45` / `resvg ^0.45`. Cargo treats `^0.45` as `<0.46`, so pairing it with resvg 0.48.1 links **two** copies of usvg, resvg, tiny-skia and fontdb. That costs about 1.5–2 MB and, worse, lets the PNG and PDF outputs parse the same SVG differently. Typst moved SVG→PDF into **krilla** (`krilla 0.8.2` and `krilla-svg 0.8.1`, both MIT OR Apache-2.0, June 2026), and krilla-svg requires `usvg ^0.47`. **Decision:** pin `resvg = "~0.47"` together with `krilla-svg 0.8.1`, so one usvg tree feeds both renderers, and move to resvg 0.48 only when krilla-svg does. `cargo tree -d` becomes a CI failure for usvg, resvg and tiny-skia. Fallback: resvg 0.45 + svg2pdf 0.13, which means accepting an 18-month-old renderer.

---

## 4. Route-by-route engine table (all 275 pairs)

## 5. Tools: all 27

## 6. Actions: all 6

§4–§6 live in [10a-routes-tools-actions](10a-routes-tools-actions.md) with the same section numbers.

---

## 7. Module architecture

### 7.1 Repository layout

```
Zivlet/
  Zivlet.xcodeproj            # targets: Zivlet (app), ZivletWorker (xpc), zivlet-js (helper), zivlet (CLI),
                               #          ZivletFinderSync (appex, 1.x); synchronized folders; xcconfigs
  App/                         # AppDelegate (composition root), Intents/ (App Intents live here), Info.plist, entitlements
  Worker/  JSHelper/  Extensions/FinderSync/
  Config/                      # Base/Debug/Release.xcconfig, *.entitlements, ExportOptions.plist
  Packages/ZivletKit/         # local SwiftPM package (below)
  Vendor/                      # versions.lock (one file for all native deps), build-media.sh, build-native.sh,
                               # build-rust.sh (Cargo.toml/lock, deny.toml), build-perl.sh, js/ (package.json, lock, esbuild),
                               # patches/, licences/
  Fixtures/                    # generate.sh (lavfi, scripted docs) + small committed fixtures; LFS corpus
  Scripts/                     # sign-helpers.sh, verify-signatures.sh, make-dmg.sh, appcast.sh, size-gate.sh, source-bundle.sh
  .github/workflows/           # vendor.yml, ci.yml, nightly.yml, release.yml
```

### 7.2 Package modules and dependency rules

| Module | Depends on | Contents | Isolation |
|---|---|---|---|
| `ZivletCore` | Foundation only | `Format`/UTType registry and content sniffing, **`Catalog`** (275 pairs + extras, 27 tools, 6 actions, each route → ordered `[EngineID]`), `JobRequest`/`JobResult`/options (Codable, Sendable, immutable), `OutputNamer` (pure), `JobError` taxonomy, progress model | nonisolated |
| `ZivletEngineKit` | Core, swift-subprocess | `Engine` protocol, `ExecutionPlan`, `JobWorkspace`, `ProgressSink`, `OutputVerifier`, `SubprocessRunner` (teardown, process group, PID file), `EngineLocator` (finds helpers from any process in the bundle), `CapabilityProbe` | nonisolated, `@concurrent` work |
| `EngineMedia` | EngineKit | ffprobe → `MediaInfo`; **pure argv planners** (audio, video, GIF, tools); progress parser; output verifier | — |
| `EngineImage` | EngineKit, `CWebP`, `ZivletRS` | ImageIO/Core Image pipelines, WebP encoder, SVG, PNG optimise, compress search, collage/annotate/add-BG renderers | — |
| `EnginePDF` | EngineKit, `CQPDF` | PDFKit operations, Quartz filter builder, qpdf job JSON, raster, redaction v1 | — |
| `EngineDocs` | EngineKit, ZIPFoundation, SwiftSoup, swift-markdown | SDoc model, readers and writers, Sheets bridge, `JSClient` (talks to zivlet-js), `OfficeEngine` (LO discovery, verify, batch runner), PDF+Vision fusion | — |
| `EngineRender` | EngineDocs, WebKit | `RenderHost` (WKWebView pool, scheme handler, content rules, print, snapshot) | **@MainActor, app only** |
| `EngineArchive` | EngineKit, `CArchive` | hardened extract, re-pack, create | — |
| `EngineMetadata` | EngineKit | ExifTool `-stay_open` session actor, ffmpeg/qpdf strip paths, verify contract | actor (one session) |
| `EngineSubtitles` | Core | SRT/VTT parse and write (pure) | — |
| `EngineVision` | EngineKit | detection, OCR, masks, warm-up | — |
| `ZivletEngines` (dynamic product) | all engine modules except Render | umbrella framework embedded once | — |
| `ZivletRuntime` | Core, EngineKit | `JobScheduler` actor + lanes, `WorkerClient` (XPC; in-process fallback), `Publisher`, `NameReserver`, `UndoLog`, `OrphanReaper`, `BatchAggregator` | actor |
| `ZivletTrigger` | Core | `TriggerMachine` (pure) + AppKit sampler | sampler @MainActor |
| `ZivletWheel` | Trigger, Core | `WheelPanel`, `WheelDropView`, `WheelModel`, `PetalShape`, glass views, haptics, sound | `defaultIsolation(MainActor)` |
| `ZivletUI` | Wheel, Runtime, EngineRender, KeyboardShortcuts | Settings panes, onboarding, tool editors, HUD/result card, Float shelf, actions | `defaultIsolation(MainActor)` |
| `zivlet-cli` | Runtime, ZivletEngines, ArgumentParser | CLI commands (`convert`, `tool`, `formats`, `info`, `wheel`) | — |
| Binary targets | — | `CWebP`, `CArchive`, `CQPDF`, `ZivletRS` xcframeworks built by `vendor.yml`, consumed through `binaryTarget(path:)` with checksums | — |

Rules:
- Core imports no Apple UI framework.
- Engines never import AppKit, except `EngineRender`.
- The Trigger and Wheel modules never import engines.
- Engine requests and plans are `Codable` from day one, so moving them across XPC is mechanical.

### 7.3 Key contracts (load-bearing signatures)

```swift
public protocol Engine: Sendable {
    static var id: EngineID { get }
    func capabilities() async -> EngineCapabilities                         // probed once per binary hash + OS build, cached
    func plan(_ request: JobRequest, input: InputProbe) throws -> ExecutionPlan // PURE: golden-tested
    @concurrent func execute(_ plan: ExecutionPlan, in workspace: JobWorkspace,
                             progress: ProgressSink) async throws -> [StagedOutput]
}

public struct ExecutionPlan: Sendable, Codable, Equatable {
    public let stages: [Stage]            // e.g. [.vision(detect), .ffmpeg(argv)] for Redact Video
    public let stageWeights: [Double]     // progress weighting, sums to 1
    public let lanes: [Lane]              // one lane per stage; scheduler acquires each in turn
    public let expectedOutputs: [OutputSpec]
    public let verification: VerificationSpec
}
```

`Catalog` is the single source of truth. It drives the wheel slices, App Intents' `OutputFormat` AppEnum, the Services menu, `zivlet formats --json`, the website format table, the Settings "Format compatibility" list and the matrix tests.

---

## 8. Cross-cutting concerns

### 8.1 Job model and queue

Lifecycle: **Request → Probe → Plan → Admit → Execute (stages) → Verify → Publish → Report**, one immutable value per step.

| Lane | Width (default) | Work |
|---|---|---|
| `cpu` | P-core count (`hw.perflevel0.physicalcpu`) | ImageIO, Core Image, libwebp, resvg, PDFKit, qpdf, libarchive, SDoc writers, subtitles |
| `remux` | 4 | ffmpeg stream copy, mute, fast trim, copy-only metadata |
| `audio` | P-cores | ffmpeg audio encodes |
| `hwVideo` | 2 (3–4 on Max/Ultra, from the media-engine count) | VideoToolbox encodes |
| `swVideo` | 1 | libvpx-vp9, SVT-AV1, x264 |
| `render` | **1** until spike D-PRINT2 proves 2 *[challenge]* | RenderHost WKWebViews (app, MainActor) |
| `js` | 2 | zivlet-js processes |
| `vision` | 1 | OCR, masks, tracking |
| `metadata` | 1 | ExifTool session (a second session if the queue exceeds 20) |
| `office` | 1 | LibreOffice batch (one process per filter group) |
| `iwork` | 1 | Apple Events export |

- Memory pressure `.warning` halves every width; `.critical` pauses admission. Low Power Mode halves `cpu`.
- Batch fan-out uses a bounded `TaskGroup` per lane (14 §5.2), with our own ~40-line cancellation-aware async semaphore (with tests).
- If the worker crashes, the scheduler retries each in-flight job **once, one at a time**. A job that crashes it again is reported as "This file made the engine crash", and the rest of the batch continues.
- Quit: `.terminateLater` → cancel all jobs → wait up to 2 s → reply.

> [challenge] **render width 2 is unproven.** The measured print path (12 §3) is `printOperation(with:)` + `runModal(for:)` on an off-screen window. `NSPrintOperation.current` is per thread, and both web views live on the main thread. Two window-modal print operations in flight on the main run loop is an untested configuration, and it can serialise or cross-wire job settings. Default to **1**. Add spike **D-PRINT2**: 2 concurrent print runs × 200 iterations, checking that the outputs are byte-distinct and correct. Only then raise the width to 2. Either way, keep the pre-rendering (docx-preview, pptx-renderer layout) parallel, and serialise only the print step.

### 8.2 Progress

- `JobProgress { stage, fraction: Double?, bytesWritten: Int64?, eta: Duration?, itemIndex, itemCount }`, delivered as an `AsyncStream` and throttled to 10 Hz.
- Sources:
  - ffmpeg: `out_time_us / expected`, with expected duration from the plan (trim range, ÷ speed, sum of clips). x264 2-pass is weighted 0.35/0.65 and loudnorm 0.4/0.6. ETA comes from `speed=`.
  - JS renderers: page or slide index.
  - Vision: page index.
  - LibreOffice: files completed in the batch.
  - libarchive: bytes read.
  - ExifTool: files completed.
- Batch progress is weighted by estimated cost: duration × pixels for video, page count for documents, bytes otherwise.
- **Unknown duration:** an indeterminate bar plus the bytes written.
- The HUD shows "n of m saved", then a done card with thumbnail, before → after size, Undo, Reveal, Open, Copy and drag-out.

### 8.3 Cancellation

| Layer | Mechanism | Target |
|---|---|---|
| User | Cancel in the HUD or menu row → `Task.cancel()` → state `.cancelled` at once; staging deleted | ≤ 100 ms visible |
| Child processes (ffmpeg, perl, zivlet-js) | swift-subprocess `teardownSequence`: SIGINT → SIGKILL at +1 s, sent to the **process group** (`processGroupID = 0`) | gone ≤ 1 s |
| LibreOffice | SIGTERM → SIGKILL at +5 s, process group; 120 s per-file watchdog | ≤ 5 s |
| WebKit | `stopLoading()`; the web view is discarded and rebuilt; `webContentProcessDidTerminate` → job failed | ≤ 200 ms |
| In-process C libraries (qpdf, libarchive, libwebp) | cooperative checks between entries, pages or frames; a stuck call hits the per-job watchdog, which kills and relaunches the worker | ≤ watchdog |
| Orphans after an app crash | `~/Library/Caches/<bundle>/Jobs/<uuid>/job.json {pid, pgid, start, helperPath}`. At launch: if `proc_pidpath(pid) == helperPath`, `killpg(pgid, SIGKILL)`, then delete the directory. | next launch |

Watchdogs (defaults): JS 60 s, render 90 s, Vision page 30 s, ExifTool command 10 s, LibreOffice 120 s per file. ffmpeg has no watchdog, but a stall detector fires when `out_time` doesn't advance for 60 s.

### 8.4 Errors

One taxonomy in Core, mapped from engine-specific errors (`MediaError`, `ConversionError`, and so on):

| Case | User copy (example) | Log context |
|---|---|---|
| `pairNotSupported` / `unsupportedInput(reason)` | "This file can't be converted to WebM: it has no video track." | probe summary |
| `passwordRequired` / `drmProtected` | "This PDF is password-protected." / "Encrypted EPUB files aren't supported." | — |
| `limitExceeded(kind)` | "The archive expands beyond Zivlet's safety limit." | sizes, ratio |
| `engineMissing` / `engineDamaged` | "Zivlet's media engine is damaged. Please reinstall." | signature-check result |
| `optionalEngineRequired(.office/.keynote)` | "PowerPoint 97–2003 needs the Office Engine or Keynote." + Install | — |
| `invalidOptions(field)` | inline in the tool window | — |
| `diskFull` / `permissionDenied(location)` | "macOS didn't allow saving in Desktop. Allow access in System Settings › Privacy." | errno, path (private) |
| `cancelled` / `timedOut(stage)` | "Cancelled" / "Rendering timed out." | stage, elapsed |
| `verificationFailed(detail)` | "The result didn't pass checks and wasn't saved." | expected vs actual |
| `alreadyOptimal` | "Already optimal. The original was kept." | sizes |
| `processFailed(status, stderrTail)` / `crashed(signal)` | "The conversion failed." + Show details | argv (paths `.private`), 64 KB stderr tail |

Errors are never swallowed. A batch reports each file's failure in the HUD and a "Show details" sheet, with Retry.

### 8.5 Output naming and publication

| Rule | Value |
|---|---|
| Location | Beside the original (default). Fallback `~/Downloads` (configurable) for read-only volumes and promised files from Mail, Photos and browsers. Extra options (a `Converted/` subfolder, Ask) are available **[OWNER]**: should they be in 1.0? |
| Conversion | `<base>.<newext>`. Compound extensions (`.tar.gz`, `.tgz`) are stripped as one unit. The "gz" target writes `.tar.gz`. |
| Tool | `<base> <Suffix>.<ext>` (suffixes in §5) |
| Multi-input tools | `<first base> <Suffix>.<ext>` in the first file's folder |
| Folder outputs | `<base> Pages`, `<base> Clips`, `<base> Extracted`, `<base> Sheets`, `<base> Slides`, `<base> Snapshots`; items `Page 001.<ext>`, `Clip 001.<ext>`, `Slide 001.<ext>`, `Frame 001 - 12.345s.png` |
| Collision | Finder-style `name 2.ext`, `name 3.ext`. The `NameReserver` actor holds names across concurrent jobs, and **`renamex_np(tmp, dest, RENAME_EXCL)`** is the ground truth (it respects case-insensitive APFS). The source is never overwritten. |
| Atomicity | Outputs are staged in `FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destDir, create: true)` on the same volume. If that is unsupported (some SMB or FAT volumes), a hidden `.zivlet-<uuid>` folder in the destination is used. Publishing is a single rename. |
| After publishing | Optionally copy Finder tags and comment xattrs. **[challenge] `com.apple.quarantine` is propagated from input to output, not stripped** (see note). One Finder reveal per batch. Entry added to the UndoLog (Undo moves outputs to the Trash). |

> [challenge] **The old "never copy quarantine" rule turned Zivlet into a quarantine-laundering tool (15 §C-5).** Zivlet is unsandboxed and doesn't set `LSFileQuarantineEnabled`, so its outputs are never quarantined. Take a downloaded, quarantined `x.rar` re-packed with **rar → zip** (or zip → tar, gz → zip). The output archive is unquarantined, and anything later extracted from it by Archive Utility, including an `.app` or a script, skips Gatekeeper's first-launch check. That is the same bug class as Archive Utility's CVE-2022-22616 and CVE-2022-32910. Extract already propagates quarantine (§5 #12); re-pack must do the same. **Rule:** if any input has `com.apple.quarantine`, copy its value (`getxattr`/`setxattr` on the staged file before the rename) onto **every** output. For a document or image this costs nothing, because Gatekeeper doesn't prompt for non-executables. Add a pair-matrix assertion for the 9 archive pairs.

### 8.6 Temporary files and disk

| Purpose | Location | Lifetime |
|---|---|---|
| Output staging | `itemReplacementDirectory` per destination volume | deleted on publish, failure or cancel |
| Scratch (2-pass logs, palettes, filter scripts, LibreOffice outdir, page rasters) | `~/Library/Caches/<bundle>/Jobs/<uuid>/` (+ `job.json`) | deleted at job end; launch sweep removes anything older than 24 h |
| Preview proxies (MKV, WebM, WMV for AVPlayer) | `~/Library/Caches/<bundle>/Proxies/` | LRU, 2 GB cap |
| Capability cache | `~/Library/Caches/<bundle>/Capabilities/<binaryHash>-<osBuild>.json` | until the hash or OS build changes |
| Optional engines | `~/Library/Application Support/Zivlet/Engines/LibreOffice/<ver>/`, LibreOffice profile | user-managed (uninstall button) |

Disk preflight before admitting a job: free space ≥ 1.5 × the estimated output + 512 MB, otherwise `diskFull` up front. ENOSPC during a job is mapped to `diskFull`.

### 8.7 Logging and diagnostics (no telemetry)

- `Logger(subsystem: "<bundle-id>", category:)`. Categories: `trigger`, `wheel`, `scheduler`, `worker`, `media`, `image`, `pdf`, `docs`, `render`, `archive`, `metadata`, `vision`, `office`, `update`, `actions`.
- Paths and file names are always `privacy: .private`. argv and stderr tails are logged at `.debug`/`.error`.
- `OSSignposter` intervals cover trigger → first wheel frame, drop → admit, and per stage.
- Settings › Advanced › **Copy diagnostics** bundles: helper versions and hashes, the capability cache, the last 200 log lines (`OSLogStore(scope: .currentProcessIdentifier)`), the last trigger trace, settings, and local MetricKit payloads. Nothing is sent anywhere. Sparkle's system profiling stays off.

### 8.8 Capability probing

At first launch and after each update or OS change, a probe collects:
- ImageIO writable and readable UTIs;
- `ffmpeg -encoders/-muxers/-filters` (keyed by binary hash);
- Vision request availability;
- the bundled Perl self-test (falling back to `/usr/bin/perl`);
- `zivlet-js` bundle hashes;
- whether LibreOffice and the iWork apps are present.

The result is cached as JSON. The wheel shows **only routes whose engine is available**, and Settings shows the reason for anything hidden. The same probe runs in CI on a clean macOS 26 VM.

### 8.9 Security hardening (unsandboxed app, untrusted inputs)

| Area | Control |
|---|---|
| Helper integrity | `SecStaticCodeCheckValidity` on every helper at first use per launch, with the requirement `anchor apple generic and certificate leaf[subject.OU] = "<TEAMID>"`. Release builds never fall back to Homebrew binaries. |
| Child environment | `PATH=/usr/bin:/bin`, fixed `LC_ALL`, `-nostdin`, `SVT_LOG=1`, private `TMPDIR`, `PERL5LIB` set only to our library, ExifTool `-config ''`. The hardened runtime strips `DYLD_*`. |
| ffmpeg input confinement *[challenge]* | `--disable-network` does **not** stop local-file disclosure. A hostile "video" that is really an HLS/ffconcat playlist (or an AVI with an embedded playlist) can make ffmpeg read `file:` segments such as `~/.ssh/id_rsa` and render them into the output, which the user may then share. This is the classic 2017 ffmpeg HLS/AVI local-file-read class. Controls: see the challenge note below this table. |
| Network | ffmpeg `--disable-network`. No network APIs in the worker or helpers. WebKit `WKContentRuleList` blocks `http(s)`, `file` and `ftp`; data store is non-persistent; navigation and `window.open` are blocked. resvg's resolver accepts only `data:`. The LibreOffice profile disables linked content and update checks. The only network traffic is Sparkle and the LibreOffice download, both from the app. |
| Archives | No `..`, symlinks or absolute paths. Owner and setuid bits are never extracted. Total ≤ min(20 × archive + 1 GB, free − 2 GB). ≤ 100,000 entries. Per-entry ratio check. No automatic nested extraction. Quarantine propagated. |
| XML / OOXML / EPUB | DTD and ENTITY rejected (no XXE); node and depth budgets; ZIP limits (≤ 1 GB uncompressed, ratio ≤ 100); 128 MB document input cap; DRM/`encryption.xml` and CFB `EncryptionInfo` refused. |
| Images and PDF | Decode through thumbnailing with a max pixel size where possible; 200 MP raster cap with tiling; PDF raster capped at 16,384 px. |
| LibreOffice | Private profile with macro security *Very High*, `BlockUntrustedRefererLinks`, no OLE/DDE updates. Download pinned by SHA-256 in the EdDSA-signed engines manifest, Team ID `7P5S3ZLCN7` checked. |
| URL scheme | `zivlet://` only opens UI with files preselected and never runs a job. |
| Fuzzing (CI nightly) | Subtitle parser (`-sanitize=fuzzer`), SDoc readers, archive corpus (zip-slip, 42.zip, symlink escape), PDF corpus (broken xref, forms, encrypted) |

> [challenge] **ffmpeg input confinement (15 §C-4).**
> - Build with `--disable-demuxer=hls,dash,webm_dash_manifest,sdp,rtsp,rtp` (none of them are needed offline).
> - **User-supplied** inputs are probed by ffprobe with `-format_whitelist` set to the advertised input demuxers (mov/mp4, matroska/webm, avi, asf, mp3, wav, flac, ogg, aiff, gif, webp…). They are then opened with `-f <that demuxer>` forced and `-protocol_whitelist file,pipe`.
> - The `concat`, `image2` (with `-pattern_type none`) and `ffmetadata` demuxers are allowed **only** for files Zivlet wrote itself (Join lists, still images for Visualizer, palettes), always with `-safe 1`-compatible relative entries in a job folder.
> - The hostile corpus gets an HLS-playlist-renamed-to-`.mp4` fixture and an ffconcat-renamed-to-`.mkv` fixture. Both must be refused.

### 8.10 Testing and quality gates

| Gate | Where | Pass bar |
|---|---|---|
| Unit + plan goldens (argv, naming, catalog, trigger traces) | PR CI | 100 % pass; **80 % coverage** on Core, EngineKit, engines, Runtime, Trigger |
| **Pair matrix** (all advertised pairs on generated fixtures; property checks, not bytes; WebM must be VP9/AV1 + Opus and playable) | PR CI (subset), nightly (all 275 + extras + 27 tools) | 0 failures. An advertised pair that fails blocks the release. |
| Document fidelity (SSIM vs Word/PowerPoint references; EPUBCheck; DOCX opens in Word, Pages and LO without repair) | nightly | 12 §10 bars |
| Hostile corpus + fuzzers | nightly | no crash escapes the worker; all refusals have copy |
| Licence gate (ffmpeg `-buildconf` has no `nonfree`, `-L` says v3; `cargo-deny`; npm licence allowlist; SPDX manifest complete) | vendor + release | hard fail |
| Signature gate (every Mach-O has `flags=0x10000(runtime)` + timestamp; `codesign --verify --strict --deep`; `spctl`) | release | hard fail |
| Size gate | release | ≤ 85 MB installed, ≤ 40 MB DMG (hard); warn above 70 / 32 |
| Performance (signposts) | nightly on Apple silicon | tap → wheel p95 ≤ 16 ms (120 Hz), ≤ 33 ms (60 Hz); HEIC 12 MP → JPEG ≤ 150 ms; idle CPU ≈ 0 %, < 30 MB RSS idle |
| Real-drag QA matrix | manual per release | Finder, Desktop, Mail, Safari, Chrome, Photos, VS Code, Dropover, full-screen, 2 displays |

> [challenge] **"Clean macOS 26 VM" can't run on GitHub-hosted runners (15 §C-10).**
> - GitHub's runner reference says nested virtualization is **not supported** on arm64 macOS runners, a limit of Apple's Virtualization framework. A hosted job therefore can't boot a Tart or UTM guest.
> - The hosted `macos-26` image is itself **macOS 26.6.2 (25G83) with Xcode 26.6** (runner-images README, 2026-10-20). It is neither 26.0 nor clean (Homebrew and many tools preinstalled).
>
> The jobs that need a *clean*, *minimum-version* or *beta* OS (G-0 re-probe, `spctl` first-launch, Sparkle N-1 → N, capability probe on a pristine OS, TCC behaviour) need a **self-hosted Apple-silicon Mac running Tart**. It needs images for 26.0, latest 26.x and latest 27.x, with no Homebrew, no Office and no iWork. Budget one Mac mini (an M2 or later guest host) in Phase 0. The hosted runners keep the build, unit and pair-matrix work.
>
> **The dev Mac skews fidelity results.** It has Microsoft Word installed (Aptos and the other Office fonts are inside `Word.app/Contents/Resources/DFonts`) plus Keynote, Pages and Numbers. D-DOCX, D-RENDER and the Automatic-router tests must run on a VM image with none of these. Otherwise the font substitution and Tier 2 paths are never exercised.
>
> **Idle RSS < 30 MB is an ESTIMATE that a pre-warmed SwiftUI glass panel is unlikely to meet.** Typical SwiftUI menu-bar apps sit at 40–70 MB. Measure in Phase 0 (P-W1) and set the bar from data. RenderHost web views must be created lazily and torn down after 60 s idle, never pre-warmed at launch.

### 8.11 Performance budgets (published)

| Budget | Value | Source |
|---|---|---|
| Wheel latency | ≤ 16 ms p95 at 120 Hz (≤ 33 ms at 60 Hz) | 14 §1 |
| Drop acknowledged | ≤ 1 ms in `performDragOperation`; HUD within 50 ms | 14 §2.2 |
| HEIC 12 MP → JPEG | ≤ 150 ms (ImageIO JPEG 12 MP PROBED at 0.05 s encode) | 13 |
| 1 min 1080p MOV → MP4 | ≤ realtime / 6 with VT (measured 5.8× for H.264) | 11 §2.3 |
| VP9 1080p | about 0.5–0.7× realtime (shows ETA; AV1 option at about 3×) | 11 §2.3 |
| Idle | 0 wakeups from Zivlet; < 30 MB RSS | 14 §1.2 |
| Large video | 4 GB file with < 300 MB app RSS (work happens in ffmpeg) | Zivlet target |

---

## 9. Bundle size budget

| Component | Low | Expected | High | Basis | Phase |
|---|---|---|---|---|---|
| libav\* dylibs (codecs folded in) + ffmpeg + ffprobe | 22 | 25 | 30 | 11 §6.5 INFERRED from Homebrew dylibs; spike M-1 | 1 |
| libwebp (+mux, sharpyuv), static | 0.5 | 0.7 | 1 | 13 §10 EST | 1 |
| `libzivlet_rs` (resvg, krilla-svg, oxipng, imagequant) | 4 | 5 | 6 | 13 §10 EST | 2 |
| libqpdf + libjpeg-turbo | 3 | 4.5 | 6 | 13 §4.4 EST | 2 |
| libarchive + xz + zstd + lz4 | 1.5 | 1.8 | 2 | 13 §10 EST | 2 |
| ExifTool 13.59 library (no `Lang/`) | 4.3 | 4.3 | 4.5 | upstream distribution without `Lang/` (ESTIMATE) | 2 |
| Trimmed Perl 5.42.x + XS modules | 3 | 4.5 | 6 | 13 §5.3 EST; spike I-M1 | 2 |
| JS bundles (SheetJS 0.95, mammoth 0.41, docx-preview + JSZip 0.17, pptx-renderer + ECharts 1.5–2.5, cupertino-files 1–1.5, polyfills) | 3.5 | 4.5 | 5.5 | 12 §9 (3 MEASURED, 2 EST) | 2–3 |
| Fonts: Carlito + Caladea (4 styles each) + Selawik (R-9) | 2 | 3 | 4 | ESTIMATE | 3 |
| Swift code: app, `ZivletEngines.framework`, worker, CLI, zivlet-js | 6 | 9 | 14 | ESTIMATE (shared framework avoids triple linking) | 1–3 |
| Sparkle.framework | 3 | 3.5 | 5 | ESTIMATE | 1 |
| Assets (icon, sounds, onboarding media) | 2 | 3 | 5 | ESTIMATE | 1 |
| **Total installed** | **54.8** | **68.8** | **89** | | |
| DMG (APFS lzfse, ≈ 45 %) | ≈ 25 | **≈ 31** | ≈ 40 | ESTIMATE | |

Not in the bundle:
- LibreOffice: 805 MB installed / 299 MB download (MEASURED), on demand.
- Pandoc pack: 192 MB (deferred).
- Gated additions: libjxl +3–5 (P4), MuPDF helper +8–15 (v2 gate), 7zz +2–3 (gated).
- Never: x265 +7, libaom +4.

> [challenge] **The media row holds up.** On the dev Mac, the Homebrew FFmpeg 8.1.2 arm64 dylibs measure: libavcodec 9.6 MB, libavfilter 2.9, libavformat 2.3, libavutil 0.6, libSvtAv1Enc 2.9, libvpx 1.75, libx264 1.27, libdav1d 0.79. Adding swscale/swresample, Opus, Vorbis, LAME, libwebp and zimg (about 2 MB) and the two executables gives **about 25 MB**, which matches the "expected" figure. The rows most likely to overrun are Swift code (an ESTIMATE, 6–14 MB) and assets. Neither has a measurement yet, so the 70 MB target is still unproven until Phase 0's hello-DMG.

Proposed budget: **target ≤ 70 MB installed / ≤ 32 MB DMG at 1.0, with a CI hard gate at 85 / 40 MB** **[OWNER]**, replacing the earlier "< 60 MB" goal. To get back under 60 MB:
- ship Perl as a download-on-first-use pack (−4.5 MB, but metadata would then need a download); or
- drop x264 and the AV1 encoder (−4 MB, losing "Accurate" target size and the AV1 option); or
- download the document JS and fonts on demand (−7 MB).

None of these is recommended.

---

## 10. Licensing

### 10.1 Project licence

**GPL-3.0-or-later for all Zivlet source** **[OWNER: confirm "or-later" vs "only"]**.
- Forced by bundling a GPL FFmpeg build with x264 (`--enable-gpl --enable-version3`) and libimagequant (GPL-3.0+).
- Apache-2.0 components (qpdf, SheetJS, docx-preview, pptx-renderer, ECharts, swift-subprocess) are compatible with GPLv3 but **not** with GPLv2-only, so v2 is ruled out.
- AGPL-3.0 (MuPDF, if adopted later) may be combined with GPLv3 under GPLv3 §13 (FSF FAQ).

Contribution model **[OWNER]**:
- **DCO** (Signed-off-by, recommended): no copyright assignment. Relicensing becomes practically impossible, which also rules out a future Mac App Store build. That is consistent with 00-decisions.
- **CLA**: keeps relicensing possible, but deters contributors.

### 10.2 Third-party components

| Component | Version | Licence (SPDX) | How shipped | GPLv3-compatible | Notes |
|---|---|---|---|---|---|
| FFmpeg (libav\*, ffmpeg, ffprobe) | 9.0.2 (fallback 8.1.3) | GPL-3.0-or-later (as configured) | shared dylibs + helpers | yes | `--disable-network`; corresponding source required |
| x264 | stable @ b35605ac | GPL-2.0-or-later | folded into libavcodec | yes | patent note §10.4 **[OWNER]** |
| libvpx | 1.17.0 | BSD-3-Clause (+ patent grant) | in libavcodec | yes | |
| SVT-AV1 | 4.2.0 | BSD-3-Clause-Clear + AOMedia Patent License 1.0 | in libavcodec | yes (INFERRED; the patent licence has defensive termination) | |
| dav1d | 1.5.4 | BSD-2-Clause | in libavcodec | yes | |
| Opus | 1.6.1 | BSD-3-Clause | in libavcodec | yes | |
| libogg / libvorbis | 1.3.6 / 1.3.7 | BSD-3-Clause | in libavcodec | yes | vorbis patch for `-force_cpusubtype_ALL` |
| LAME | 3.100 | LGPL-2.0-or-later | in libavcodec | yes | symbol-list patch |
| libwebp (+mux, sharpyuv) | 1.6.0 | BSD-3-Clause | in libavcodec + `ZivletEngines` | yes | |
| zimg | 3.0.6 | WTFPL | in libavfilter | yes | |
| resvg / usvg / tiny-skia / fontdb | 0.47.x (pinned to match krilla-svg) / — | Apache-2.0 OR MIT; tiny-skia BSD-3-Clause | `libzivlet_rs` | yes | `cargo-about` generates notices |
| krilla / krilla-svg / pdf-writer / skrifa | 0.8.2 / 0.8.1 / 0.15 / 0.42 | MIT OR Apache-2.0 | `libzivlet_rs` | yes | [challenge] replaces svg2pdf 0.13 (see §3 note) |
| oxipng | 10.2.1 | MIT | `libzivlet_rs` | yes | |
| imagequant (libimagequant) | 4.x | GPL-3.0-or-later | `libzivlet_rs` | yes | requires a GPLv3 app |
| qpdf | 12.4.2 | Apache-2.0 | static in `ZivletEngines` | yes | reproduce NOTICE |
| libjpeg-turbo | 3.1.x | IJG AND BSD-3-Clause AND Zlib | static (qpdf) | yes | IJG acknowledgement text |
| libarchive | 3.8.10 | BSD-2-Clause | static | yes | |
| xz (liblzma) / zstd / lz4 | 5.8.4 / 1.5.7 / 1.10 | 0BSD / BSD-3-Clause / BSD-2-Clause | static | yes | |
| ExifTool | 13.59 | Artistic-1.0-Perl OR GPL-1.0-or-later | Resources (Perl scripts) | yes (under GPL) | include source (it is source) |
| Perl (trimmed, relocatable) | 5.42.x | Artistic-1.0-Perl OR GPL-1.0-or-later | `Helpers/perl` + lib | yes | build from perl.org source; source in bundle |
| SheetJS CE | 0.20.3 (from cdn.sheetjs.com, not npm 0.18.5) | Apache-2.0 | JS bundle | yes | pinned hash |
| mammoth (+ lop, underscore, xmlbuilder, @xmldom/xmldom, base64-js, dingbat-to-unicode) | 1.13.0 | BSD-2-Clause (deps MIT/BSD) | JS bundle | yes | SOURCE (npm) |
| docx-preview | 0.4.1 | Apache-2.0 | JS bundle | yes | SOURCE (npm) |
| JSZip (+ pako, lie, setimmediate, readable-stream) | 3.10.x | MIT OR GPL-3.0-or-later; pako MIT AND Zlib | JS bundle | yes | SOURCE (npm) |
| @aiden0z/pptx-renderer | 1.4.0 | Apache-2.0 | JS bundle | yes | SOURCE (npm) |
| ECharts / zrender | 6.x | Apache-2.0 / BSD-3-Clause | JS bundle (pptx-renderer dependency) | yes | reproduce ECharts NOTICE |
| mtx-decompressor | 1.x | **MPL-2.0** | JS bundle (pptx-renderer dependency) | yes (MPL-2.0 §3.3) | ship its source form in the source bundle (SOURCE, npm) |
| cupertino-files | 0.4.0 | MIT | JS bundle | yes | SOURCE (npm) |
| ZIPFoundation | 0.9.20 | MIT | SPM | yes | |
| SwiftSoup | 2.14.3 | MIT | SPM | yes | |
| swift-markdown (+ cmark-gfm) | 0.9.0 | Apache-2.0 (cmark-gfm BSD-2-Clause) | SPM | yes | |
| swift-subprocess (+ swift-system) | 1.0.2 | Apache-2.0 with Runtime Library Exception | SPM | yes | |
| swift-argument-parser | 1.7.2 | Apache-2.0 with Runtime Library Exception | SPM (CLI) | yes | |
| KeyboardShortcuts | 3.1.0 | MIT | SPM | yes | |
| Sparkle | 2.10.0 | MIT (bundles bsdiff BSD-2-Clause and other notices in its LICENSE) | framework | yes | SOURCE (repo LICENSE); copy the full file |
| Carlito / Caladea | upstream | OFL-1.1 | fonts | yes (fonts are separate works) | SOURCE (google/fonts `ofl/`); ship OFL.txt, unmodified |
| Selawik | upstream | OFL-1.1 | font | yes | verify at vendoring |
| *Optional, not bundled:* LibreOffice | 26.8.x | MPL-2.0 (parts LGPL-3.0+) | downloaded from TDF on request, never modified | n/a (not distributed) | link to TDF notices |
| *Gated:* MuPDF | 1.27/1.28 | AGPL-3.0-or-later | separate helper | yes (§13) | **[OWNER]** v2 |
| *Gated:* 7-Zip `7zz` without RAR | 26.04 | LGPL-2.1-or-later + BSD-3-Clause | helper | yes | build without RAR codecs |
| *Gated:* libjxl (+highway, brotli) | 0.12.0 | BSD-3-Clause + patent grant; Apache-2.0; MIT | static | yes | P4 |
| **Banned** | — | fdk-aac (nonfree), unRAR licence, any `--enable-nonfree` build | — | **no** | CI fails the build |

### 10.3 Obligations and how CI meets them

1. **Corresponding source (GPLv3 §6).** Every GitHub Release and every Sparkle appcast item links to `Zivlet-<ver>-source.tar.xz`. It contains:
   - the app source at the tag;
   - all vendored upstream tarballs, verified by SHA-256;
   - our patches;
   - `versions.lock`;
   - the build scripts;
   - the JS sources (unminified, including the MPL file);
   - the Perl source;
   - the Xcode and CLT versions used.

   It stays hosted for as long as the binary is offered.
2. **Notices.** About › Acknowledgements and `Resources/Licenses/` are generated from:
   - an SPDX manifest of C libraries (from `versions.lock`);
   - `cargo-about` output for Rust crates;
   - the esbuild metafile and npm licence data for JS bundles.

   Apache NOTICE files (qpdf, ECharts and others) are reproduced verbatim.
3. **No added restrictions.** The appcast and downloads don't need an account. Sparkle keys sign updates but don't restrict modification, since users can build and run their own copy. That stays compliant with GPLv3's installation-information clause, which applies to "User Products" in the consumer-device sense. INFERRED; not legal advice.
4. **SBOM.** A CycloneDX SBOM is attached to each release.

### 10.4 Patent notes (INFERRED, not legal advice)

- **H.264 and HEVC:** VideoToolbox is the default path (Apple's licensed OS feature).
- **x264:** kept for "Accurate" target size. It carries the same theoretical AVC-pool exposure HandBrake, OBS and VLC live with, and can be removed with one flag (`--disable-libx264`). **[OWNER]**
- **x265:** excluded.
- **Royalty-free or expired:** VP9, AV1, Opus and Vorbis are royalty-free (AV1 third-party pool claims are monitored). MP3 patents have expired.
- **Archives:** RAR writing is not implemented, and no RAR code is shipped.

---

## 11. Build and release pipeline

### 11.1 Workflows (GitHub Actions, `macos-26` arm64 runners, Xcode 26.6)

| Workflow | Trigger | Steps | Outputs |
|---|---|---|---|
| `vendor.yml` | changes to `Vendor/**` | `build-media.sh` (11 §6: deps static → FFmpeg shared, `SOURCE_DATE_EPOCH`, `-ffile-prefix-map`, `PKG_CONFIG_LIBDIR` isolated from Homebrew), `verify-media.sh` (licence, deps, minos 26.0, no path leaks, required encoders), `build-native.sh` (libwebp, libarchive + deps, qpdf + libjpeg-turbo → xcframeworks), `build-rust.sh` (`cargo build --release --target aarch64-apple-darwin --locked`, `cargo-deny check licenses advisories`), `build-perl.sh` (perl.org source, `-Duserelocatableinc`, module trim list), JS (`npm ci --ignore-scripts` + esbuild IIFE bundles + hash manifest). A reproducibility job builds twice and diffs the hashes. | `zivlet-vendor-<lockhash>.tar.zst` (binaries + dSYMs), `zivlet-vendor-src-<lockhash>.tar.xz`, SPDX fragment. Cached by lock hash. |
| `ci.yml` | PR | Fetch the vendor artifact by key. Build unsigned (`CODE_SIGNING_ALLOWED=NO`). Swift Testing unit + goldens + pair-matrix subset. Coverage gate. Licence diff check. | test report, coverage |
| `nightly.yml` | cron | Full matrix (275 + extras + 27 tools), document fidelity corpus, hostile corpus, fuzzers (time-boxed), performance signposts; a macOS 26.x VM job **and** a newest-beta job (self-hosted or a beta image when available) | dashboards, failure attachments |
| `release.yml` | tag `v*`, protected `release` environment with a required reviewer | archive → `sign-helpers.sh` (inside-out: dylibs → Perl XS bundles → helpers → `ZivletEngines.framework` → worker XPC → Sparkle → app; `--options runtime --timestamp`; zivlet-js with `allow-jit`) → `-exportArchive` (developer-id) → `verify-signatures.sh` → `notarytool submit --wait` → staple → `make-dmg.sh` (APFS, signed) → notarize and staple the DMG → `spctl` on a clean VM, smoke-testing one pair per engine → `size-gate.sh` → `source-bundle.sh` → `generate_appcast --ed-key-file - --maximum-deltas 3` → `gh release upload` (DMG, deltas, source, SBOM, dSYMs) → push `appcast.xml` to `gh-pages` → open a Homebrew cask bump PR | signed, notarized DMG; appcast; release |

### 11.2 Signing and entitlements

| Code | Entitlements (hardened runtime on every Mach-O) |
|---|---|
| Zivlet.app | `com.apple.security.automation.apple-events` (opt-in Finder selection and iWork bridge) + `NSAppleEventsUsageDescription`. Nothing else. |
| ZivletWorker.xpc | none |
| ffmpeg, ffprobe, perl (+ XS bundles), zivlet CLI | none (our Team ID passes library validation) |
| zivlet-js | `com.apple.security.cs.allow-jit` |
| zivlet-office-helper (1.x, LibreOfficeKit) | `com.apple.security.cs.disable-library-validation` (it loads TDF's dylib) |
| ZivletFinderSync.appex (1.x) | `com.apple.security.app-sandbox` + app group *[challenge: since macOS 15, group containers are TCC-protected. For Developer ID builds the group ID must take the Team-ID-prefixed form (`<TEAMID>.app.zivlet`), and the **app** needs the same group entitlement. Otherwise users get an "access data from other apps" prompt. Doing that adds one entitlement to the app, so the "nothing else" row above changes at 1.x.]* |

Signing rules:
- Never sign with `--deep`.
- Non-Mach-O scripts go in `Resources/`.
- Xcode "Code Sign On Copy" for Helpers is **not trusted until spike M-2**; until then the explicit `sign-helpers.sh` is authoritative.

### 11.3 Secrets and custody

- `DEVID_P12_BASE64` / `DEVID_P12_PASSWORD` (Developer ID Application certificate).
- `ASC_KEY_P8_BASE64` / `ASC_KEY_ID` / `ASC_ISSUER_ID` (notarytool API key).
- `SPARKLE_ED_PRIVATE_KEY`.

All are in the protected `release` environment, so forks never sign. The Sparkle EdDSA key also has an **offline backup** held by the owner. Losing it strands every installed copy. **[OWNER]**: who holds the Apple Developer account? Individual or organisation decides the name Gatekeeper shows.

### 11.4 Versioning and channels

- SemVer for the marketing version. `CFBundleVersion` is a monotonically increasing build number, which Sparkle compares.
- Channels: `stable`, and `beta` (`--channel beta`, opt-in in Settings › Updates). Phased rollout via `--phased-rollout-interval` for minor releases.
- Security point releases (FFmpeg, libwebp, libarchive, qpdf, Perl, ExifTool) follow automated update PRs (Renovate-style job on `versions.lock`) and can ship within days.

---

## 12. Phased roadmap

## 13. Consolidated spike plan (renamed by prefix, R-13)

## 14. Consolidated risk register

§12–§14 live in [10b-roadmap-spikes-risks](10b-roadmap-spikes-risks.md) with the same section numbers.

---

## 15. Decisions needing the owner's input

| # | Decision | Recommendation | Consequence if changed |
|---|---|---|---|
| O-1 | Project licence: **GPL-3.0-or-later** vs GPL-3.0-only | or-later | "only" blocks a future GPLv4 and complicates combining with or-later code. Not GPLv2 (Apache deps). |
| O-2 | Contribution model: **DCO** vs CLA | DCO | A CLA keeps relicensing (and an App Store build) possible but deters contributors |
| O-3 | Size target: accept **≤ 70 MB installed / ≤ 32 MB DMG** (gate 85 / 40) instead of < 60 MB | accept | Meeting 60 MB means download-on-demand packs (Perl, doc JS/fonts) or dropping x264/AV1 |
| O-4 | Include **x264** (exact 2-pass target size, deterministic goldens) | include | Removing it: VT-only H.264, "Accurate" target-size mode gone, −1.2 MB |
| O-5 | **PPT (3 pairs)** and DOC rely on optional LibreOffice (805 MB) or Keynote | accept, with a one-click verified download | Alternative: ship the experimental @silurus raster reader (quality unproven) or hide PPT |
| O-6 | Zivlet downloads and installs **LibreOffice** from TDF mirrors on request (pinned SHA-256 + Team ID) | yes | If no: only detect an existing install and link to libreoffice.org |
| O-7 | Default **Document fidelity** = Automatic (use LO or iWork only if already present) | Automatic | "Best fidelity" default would prompt downloads; "Fast" ignores better engines |
| O-8 | **Bundled trimmed Perl** for ExifTool (vs system Perl only) | bundle | System-only saves about 4.5 MB but depends on a deprecated runtime |
| O-9 | **MuPDF (AGPL) true PDF redaction** in 2.x | decide at the v2 gate | Without it, redaction stays rasterise-the-page (safe, but loses selectable text on those pages) |
| O-10 | **Bundle identifier / domain** (docs assume `app.zivlet`), GitHub org, Homebrew cask name | choose before Phase 0 ends | Changing it after release breaks Sparkle continuity and settings |
| O-11 | **Apple Developer account** holder (individual vs organisation; this name appears in Gatekeeper) and custody of the Sparkle key backup | organisation if possible | — |
| O-12 | **Trademark / name check** for "Zivlet" before any public artifact (00-decisions) | do it in Phase 0 | rename cost grows after release |
| O-13 | **arm64-only** for 1.0 (macOS 26 still runs on a few late Intel Macs) | arm64-only | Universal roughly doubles FFmpeg and native library size |
| O-14 | **Output location options** beyond "beside original" (Converted/ subfolder, Downloads, Ask) in 1.0 | beside + Downloads fallback in 1.0; the rest in 1.x | Not needed for parity; adds Settings surface |
| O-15 | **Languages at 1.0** | English; strings catalogued | Localising at 1.0 adds roughly 2–3 weeks |
| O-16 | Defaults that change behaviour vs the parity baseline: per-stream copy (R-14), 300 DPI PDF raster (R-8), Ogg = Vorbis, WebM = VP9 + Opus, "Already optimal" refusal, wheel keys ⇧/⌘/⌃ | as listed | — |
| O-17 | Optional **Apple Events features** (iWork bridge, Finder-selection hotkey) ship in 1.0 as opt-in | yes, off by default | If no, drop the app's Apple Events entitlement entirely |
| O-18 *[challenge]* | **Realistic 1.0 date or scope** (§12 note): 12–18 months for full parity, or ship 1.0 = Phases 1–2 | decide in Phase 0 | Over-promising "275 pairs at 1.0" in about 7 months risks shipping routes that fail their fidelity bars |
| O-19 *[challenge]* | **Use fonts from a locally installed Microsoft Office** (register `Word.app/…/DFonts` with `CTFontManagerRegisterFontsForURL(.process)` at render time, never copied or redistributed) to fix Aptos/Calibri fidelity | ask counsel; default off | Without it, Aptos-default documents (Office since 2024) always reflow with Carlito |

---

## 16. RECOMMENDATION

### Choice

Build Zivlet as the **native-first, process-isolated stack** below and release it in five phases, with Phase 1 as the MVP slice. Every bundled component is licensed GPLv3-compatibly, and the project itself is **GPL-3.0-or-later**.

1. **Media:** a self-built **FFmpeg 9.0.2 + ffprobe** (GPLv3, full codec set, VideoToolbox first), run as child processes through swift-subprocess. It covers all 104 audio, video and GIF pairs and 15 media tools. AVFoundation is used only for UI.
2. **Images, SVG, PDF:** **ImageIO + Core Image** with **libwebp**, the **resvg/krilla-svg/oxipng/imagequant** Rust library, **PDFKit/Quartz** (runtime Quartz filters for compression) and **qpdf**.
3. **Documents:** **Tier 1** in-app and offline (WKWebView print, docx-preview, mammoth, pptx-renderer, SheetJS CE, cupertino-files, our own SDoc, Vision + PDFKit fusion). **Tier 2a** LibreOffice on demand, required only for PPT. **Tier 2b** opt-in iWork export. No JVM.
4. **Metadata, archives, subtitles, Vision:** **ExifTool on a bundled trimmed Perl**, with fail-closed verification; **libarchive** with hardening; our own **ZivletSubtitles**; Vision with background warm-up.
5. **Platform:**
   - the permission-free hybrid trigger;
   - a pre-warmed non-activating glass wheel with an AppKit drop target;
   - an AppKit menu-bar shell;
   - `ZivletWorker.xpc` plus signed helpers (ffmpeg, ffprobe, perl, zivlet-js, CLI);
   - one `Catalog` driving the wheel, Intents, Services, CLI and tests;
   - an `actor JobScheduler` with resource lanes, staging, and `RENAME_EXCL` publication;
   - Sparkle 2.10 with EdDSA;
   - GitHub Actions `macos-26` with inside-out signing, notarization, licence, signature, size and matrix gates.

> [challenge] **The adversarial review (15-strategy-challenge.md) leaves the choice standing, with these corrections folded in:**
> - FFmpeg 9 sonames (63/63/12/61/10/7).
> - resvg 0.47 + krilla-svg instead of resvg 0.48 + svg2pdf.
> - The Perl lib moved to `Resources/perl5`.
> - Quarantine propagated on every output.
> - ffmpeg demuxer and protocol confinement.
> - AVFoundation-playable gating for stream copy into MP4/MOV.
> - Operation-mask-tolerant drop handling.
> - render width 1.
> - Styled XLSX reading in Phase 2.
> - cupertino-files risk raised to High / High, with D-PAGES moved to gate B.
> - Self-hosted Tart CI for clean and minimum-OS jobs.
> - A realistic 1.0 schedule (O-18).
>
> No licensing conflict was found: every bundled component is GPLv3-compatible, and the AGPL, unRAR and nonfree gates hold.

### Rationale

- **Complete:** 272 of the 275 pairs work out of the box. The 3 PPT pairs work once LibreOffice or Keynote is present. All 27 tools and 6 actions are mapped to a concrete engine (§4–6).
- **Small and fast:** about 69 MB installed with no JVM; the document stack is about 5 MB of JS plus Apple frameworks. Hardware video encoding, in-process WebP, a persistent ExifTool session and an event-driven trigger avoid temp-file round trips and constant polling.
- **Correct by construction:** every advertised encoder is linked, and CI encodes every advertised pair. That fixes the WebM class of bug. The capability probe hides anything that can't run on the user's Mac, and metadata writes are verified.
- **Safer:**
  - every untrusted parser runs out of the UI process;
  - outputs are staged and published atomically, so partial files are impossible;
  - the network is blocked in every renderer;
  - archive and XML limits are enforced;
  - helpers are signature-checked.
- **Licence-simple:** GPLv3 is what the best encoders require anyway. Every other component is permissive, LGPL or MPL, and AGPL/unRAR/nonfree stay out or behind explicit gates.
- **Phased risk:** Phase 0 proves the unknowns that could invalidate the product (permission-free trigger on 26.x, notarized nested helpers, update path) before any feature work. Phase 1 proves the hardest runtime pieces on the 153 highest-volume pairs.

### Risks

- macOS 26.x may differ from the macOS 27 probes (X1).
- Apple could gate drag detection (X2).
- Nested-code notarization (X3).
- Upkeep of about 20 native upstreams (X4).
- Young single-maintainer JS renderers and approximate DOCX pagination (X5, X6).
- Size may land above 70 MB (X7).
- Unsandboxed parsing of hostile files (X8).
- TCC prompts at first save into a protected folder (X9).
- PDF compression side effects (X10).
- Vision cold start (X12).
- PPT parity tied to an 805 MB optional engine (X15).
- The GPL source obligation on every release (X16).
- Sparkle key custody (X14).

### Fallback

| If this fails | Then |
|---|---|
| Hybrid trigger | Polling (10 Hz idle, 120 Hz during a drag), then an opt-in Input Monitoring event tap |
| Glass | The Solid theme becomes the default |
| Self-built FFmpeg slips | The same script without x264. Then a temporary reproducible static build (e.g. adapting markus-perl/ffmpeg-build-script **without** nonfree) until ours is ready. FFmpeg 8.1.3 if 9.0.x regresses. Two static executables if shared-dylib signing fails. |
| Worker XPC slips | In-process engines behind the same `Engine` protocol for 1.0 |
| zivlet-js / JIT helper fails | Host the JS libraries in the RenderHost WKWebView pool |
| Tier 1 document renderers miss D-DOCX / D-RENDER | Make the Office Engine the recommended default for layout routes, enable the Keynote bridge by prompt, and keep Tier 1 as the offline fallback |
| SDoc writers slip | Bundle Pandoc 3.12.x (GPL-2+), accepting +192 MB, or pandoc.wasm if its speed is proven |
| SheetJS fails at scale | calamine + rust_xlsxwriter behind the `Sheets` protocol |
| ExifTool on bundled Perl fails | `/usr/bin/perl`. If that also fails, disable editing and offer re-encode stripping with a warning. |
| PDFKit rendering fails on real files | pdfium (3.5 MB) for rasterising only |
| PDF compression | qpdf `--optimize-images`, then the v2 qpdf-based recompressor |
| Size gate | Optional on-demand packs (Perl, document JS and fonts), in that order, before dropping any route |

---

### Sources

- Design inputs: [11-media-engine](11-media-engine.md), [12-document-engine](12-document-engine.md), [13-image-pdf-engine](13-image-pdf-engine.md) and [14-app-platform](14-app-platform.md). Each lists its upstream sources: FFmpeg, libvpx, SVT-AV1, x264, dav1d, Xiph, libwebp, zimg, swift-subprocess, Sparkle, LibreOffice, Pandoc, docx-preview, mammoth, pptx-renderer, SheetJS, cupertino-files, resvg, svg2pdf, qpdf, libarchive, ExifTool, Perl, Apple SDK headers and documentation, GitHub runner changelog.
- Product scope: Zivlet's own scope (275-pair matrix, 27 tools, 6 actions, improvement targets), kept in private notes that are not published.
- Licence checks done for this synthesis (2026-10-20, SOURCE):
  - `npm view` for @aiden0z/pptx-renderer 1.4.0 (Apache-2.0; deps jszip, echarts, **mtx-decompressor MPL-2.0**), echarts 6.1.0 (Apache-2.0), jszip 3.10.2 (MIT OR GPL-3.0-or-later), docx-preview 0.4.1 (Apache-2.0), mammoth 1.13.0 (BSD-2-Clause), cupertino-files 0.4.0 (MIT);
  - GitHub `google/fonts` `ofl/carlito`, `ofl/caladea`, `ofl/gelasio` (OFL.txt present);
  - `sparkle-project/Sparkle` LICENSE (MIT + external licences, including bsdiff).
