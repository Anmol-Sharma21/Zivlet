# 15 — Adversarial review of the Zivlet technical strategy

Date: 2026-10-20. Target: [10-tech-strategy](10-tech-strategy.md), with the topic files [11](11-media-engine.md), [12](12-document-engine.md), [13](13-image-pdf-engine.md) and [14](14-app-platform.md) read where 10 cites them.

Method: I tried to break each major recommendation along seven lines:
- licensing;
- notarization and signing;
- binary size;
- maintenance of dependencies;
- macOS 26 API claims;
- trigger latency and performance;
- fidelity and coverage against Zivlet's route matrix.

Claims were checked against primary sources on 2026-10-20: ffmpeg.org, the FFmpeg `release/9.0` tree, crates.io, the npm registry, GitHub and GitLab release APIs, Apple's documentation JSON, the GitHub runner-images README, the Sparkle source, the SheetJS CE build, and local measurements on the dev Mac (macOS 27.0, build 26A428, M2 Pro).

Every error I found has been fixed **in place in 10-tech-strategy.md**, each marked `> [challenge]` (or `[challenge]` inline in tables). This file records the evidence and the reasoning behind each fix.

Severity scale: **CRITICAL** (wrong output, security hole, or a release blocker), **HIGH** (a coverage or quality regression, or a plan that won't work as written), **MEDIUM** (needs a design change or spike), **LOW** (accuracy or hygiene).

---

## 0. Summary

| # | Finding | Severity | Status in 10 |
|---|---|---|---|
| C-1 | FFmpeg 9.0 dylib sonames in the bundle layout are the 8.x set | LOW (build-breaking if hard-coded) | fixed §2.2 |
| C-2 | `Helpers/perl-lib/` puts non-code in a nested-code directory, so signatures break in DMG and zip transport | HIGH (notarization or Gatekeeper failure) | fixed §2.2 |
| C-3 | resvg 0.48.1 + svg2pdf 0.13 can't share one usvg; svg2pdf is stale | MEDIUM | fixed TL;DR, §3, §4.1, §9, §10.2 |
| C-4 | ffmpeg has no demuxer or protocol confinement, so HLS/concat local-file disclosure is open | CRITICAL (security) | fixed §8.9 |
| C-5 | "Never copy quarantine" means archive re-pack routes launder quarantine and bypass Gatekeeper | CRITICAL (security) | fixed §8.5 |
| C-6 | Rule "app never parses untrusted files" is contradicted by the tool editors | MEDIUM | fixed §2.1 |
| C-7 | The CLI → app "Mach service" can't exist without a launchd job | MEDIUM | fixed §2.1 |
| C-8 | Drop view ignores the operation mask: holding ⌃ or ⌘ at release rejects the drop | HIGH (core UX) | fixed §2.1, spike P-T6 |
| C-9 | Stream copy into MP4/MOV produces files unplayable on the Mac (AV1 on M1/M2, `hev1`, Xvid ASP) | HIGH | fixed §4.5 |
| C-10 | "Clean macOS 26 VM" CI is impossible on GitHub-hosted arm64 runners; the hosted image is 26.6.2 | HIGH (gates can't run) | fixed §8.10, spike P-CI |
| C-11 | render lane width 2 assumes concurrent `NSPrintOperation`s on the main thread work | MEDIUM | fixed §8.1, spike D-PRINT2 |
| C-12 | SheetJS CE attaches only fills to cells, so xlsx → pdf loses fonts and borders that a POI-based renderer keeps | HIGH (quality) | fixed §4.10, spike D-XLSX-STYLE |
| C-13 | cupertino-files (16 pairs) is 2.5 months old with 4 stars | HIGH (maintenance) | fixed X5, D-PAGES moved to gate B |
| C-14 | Metadata "Remove all" keeps cover-art streams (which can hold GPS) on ffmpeg paths | HIGH (privacy) | fixed §5 #2 |
| C-15 | Redact Video's drawbox-per-box filtergraph doesn't scale | MEDIUM (performance) | fixed §5 #26, spike M-REDACT |
| C-16 | The AVIF fallback via SVT-AV1 drops alpha and ICC silently | MEDIUM | fixed §4.2 note |
| C-17 | The dev Mac has Word (Aptos fonts) and iWork installed, so fidelity measurements skew optimistic | MEDIUM | fixed §8.10, O-19 |
| C-18 | The schedule (27–33 weeks, one engineer) isn't credible for the full route matrix | HIGH (planning) | fixed §12, O-18 |
| C-19 | Output names drift from the product spec (Speed, Create PDF, Metadata) | LOW | fixed §5 note |
| C-20 | Trigger: the high-rate `leftMouseDragged` monitor, pasteboard-privacy re-check, Esc hotkey inconsistency | MEDIUM | spikes P-T1/G-0 extended |
| C-21 | The idle RSS < 30 MB target is unrealistic with a pre-warmed SwiftUI glass panel | LOW | fixed §8.10 note |
| C-22 | FinderSync app-group naming triggers TCC on macOS 15+ unless Team-ID-prefixed | LOW (1.x) | fixed §11.2 |
| C-23 | The ogg default-codec claim is build-dependent | LOW | fixed §4.4 |

No licensing conflict was found (§2). Versions in 10 match upstream on 2026-10-20 (§1).

---

## 1. What survived: verified claims

| Claim in 10 | Verification (2026-10-20) | Result |
|---|---|---|
| FFmpeg 9.0.2 "Lei" exists; 8.1.3 is the fallback | ffmpeg.org/download: 9.0.2 released 2026-09-18, branch cut 2026-06-26; 8.1.3 released 2026-09-21 | ✔ |
| FFmpeg 9 adds an animated WebP decoder and demuxer, the ProRes RAW VT hwaccel and the whisper filter | `release/9.0/Changelog`: "Animated WebP decoder", "Animated WebP demuxer", "ProRes RAW VideoToolbox hwaccel"; "Whisper filter" (8.0) | ✔ |
| libvpx 1.17.0, Opus 1.6.1, SVT-AV1 4.2.0, dav1d 1.5.4, libwebp 1.6.0, x264 stable `b35605ac` | GitHub/GitLab tags; SVT-AV1 4.2.0 released 2026-07-14; x264 stable HEAD `b35605ac` (2025-06-08) | ✔ |
| libarchive 3.8.10, qpdf 12.4.2, xz 5.8.4, zstd 1.5.7, oxipng 10.2.1, libimagequant 4.4.1 (GPL-3.0-or-later) | GitHub releases and tags; crates.io `imagequant` 4.4.1 licence GPL-3.0-or-later | ✔ |
| resvg 0.48.1 exists | GitHub release 2026-08-02 | ✔ (but see C-3) |
| Sparkle 2.10.0 and a signed feed | Release 2026-09-13; `SURequireSignedFeedKey` in `SUConstants.m`; 2.10 raises the minimum to macOS 12 | ✔ |
| swift-subprocess 1.0.2 with `processGroupID` and `teardownSequence` | Release 2026-10-16; both symbols in `Subprocess+Darwin.swift` / `Teardown.swift` | ✔ |
| ExifTool 13.59 | exiftool.org/ver.txt = 13.59 | ✔ |
| LibreOffice 26.8 | download.documentfoundation.org/stable lists 26.8.0 and 26.8.1 | ✔ |
| LibreOffice Team ID `7P5S3ZLCN7` | Third-party app catalogue (appcatalog.cloud) shows that OU in the designated requirement | ✔ (single source; re-check against a fresh download in D-LO) |
| JS libs: pptx-renderer 1.4.0 (Apache-2.0), docx-preview 0.4.1 (Apache-2.0), mammoth 1.13.0 (BSD-2), cupertino-files 0.4.0 (MIT), mtx-decompressor 1.8.0 (MPL-2.0) | `npm view` | ✔ |
| Vision `RecognizeDocumentsRequest` is macOS 26.0+, with tables, lists, barcodes and `Text.detectedData` (`DataDetectorMatch`) | Apple doc JSON: introducedAt macOS 26.0; `DocumentObservation.Container.Text` → `detectedData` | ✔ |
| `GenerateIterativeSegmentationRequest` is macOS 27 | Apple doc JSON: introducedAt macOS 27.0 | ✔ (must stay `#available`-gated) |
| `TrackObjectRequest`, `DetectBarcodesRequest`, `GenerateForegroundInstanceMaskRequest` | macOS 15.0+ | ✔ |
| `PDFDocumentWriteOption.saveTextFromOCROption` | macOS 13.0+ | ✔ |
| `NSScreen.displayLink(target:selector:)` | macOS 14.0+ | ✔ |
| `CIToneMapHeadroom` | Documented Core Image filter protocol | ✔ |
| SVT-AV1 `avif=1` parameter | `Docs/Parameters.md` @ v4.2.0, line 301: `--avif [0-1]` "still-picture coding optimizations" | ✔ (but see C-16) |
| GitHub `macos-26` arm64 runner, Xcode 26.6 | runner-images README: label `macos-26`/`macos-latest`; image macOS 26.6.2 (25G83), Xcode 26.6 default; Xcode 27 in preview | ✔ (but see C-10) |
| FFmpeg media payload ≈ 25 MB | Homebrew 8.1.2 arm64 dylibs on the dev Mac: avcodec 9.6, avfilter 2.9, avformat 2.3, avutil 0.6, SvtAv1Enc 2.9, vpx 1.75, x264 1.27, dav1d 0.79 MB; plus about 2 MB of small libs and the executables | ✔ about 25 MB |
| Drag pasteboard is exempt from pasteboard privacy | Apple `NSPasteboard.AccessBehavior.default`: the alert applies to the **General** pasteboard; the AppKit header says "All other pasteboards default to always allow access". Shipping status of the alert in 26.x is still unclear (secondary sources say it was not enforced by default mid-2026) | ✔ with a re-test (C-20) |

---

## 2. Licensing: attempted breaks

| Attack | Analysis | Verdict |
|---|---|---|
| GPL-3.0-or-later app + Apache-2.0 deps (qpdf, SheetJS, docx-preview, pptx-renderer, ECharts, swift-subprocess) | Apache-2.0 → GPLv3 is one-way compatible (FSF). This rules out GPLv2-only, as 10 says. | OK |
| x264 (GPL-2.0-or-later) + `--enable-version3` | The combined libavcodec is GPLv3. "or-later" makes it legal. | OK |
| LAME (LGPL-2.0+) static inside a GPLv3 libavcodec | LGPL → GPL conversion is allowed (LGPL §3). Because the whole app is GPL, there is no "relink" duty to satisfy separately. | OK |
| libimagequant GPL-3.0-or-later | Forces GPLv3 independently of FFmpeg. If the owner ever wants a permissive licence, **both** x264 and imagequant must go, along with an LGPL FFmpeg build. 10 states this. | OK |
| SVT-AV1 BSD-3-Clause-Clear + AOMedia Patent License 1.0 | FSF lists Clear BSD as GPL-compatible. The AOM patent licence is a separate grant from AOM members, not a copyright restriction. Debian ships SVT-AV1 in main. Residual: its defensive termination is broader than GPLv3 §11. This is a theoretical tension, and the same one every GPL FFmpeg distributor with SVT-AV1 lives with. | OK (INFERRED, low risk) |
| JSZip "MIT OR GPL-3.0-or-later", pako "MIT AND Zlib" | Choose MIT. | OK |
| mtx-decompressor MPL-2.0 inside a GPL bundle | MPL-2.0 §3.3 allows a Larger Work under GPL unless the file carries "Incompatible With Secondary Licenses". npm 1.8.0 is plain MPL-2.0. The source of the MPL file must be shipped (10 §10.3 does this). | OK; add an "Incompatible With Secondary Licenses" grep to the licence gate |
| Minified JS in a GPL binary | Minified JS isn't the "preferred form for modification". 10 ships unminified sources in the source bundle. | OK |
| ExifTool / Perl "same terms as Perl" | Artistic-1.0-Perl OR GPL-1.0-or-later. Take GPL-1.0+ → GPLv3. | OK |
| OFL fonts (Carlito, Caladea, Selawik) in a GPL app | Fonts are separate works under OFL; bundling is explicitly permitted. They must not be sold alone, and OFL.txt must be shipped. | OK |
| New: krilla / krilla-svg / skrifa (C-3) | MIT OR Apache-2.0 (crates.io). | OK |
| New: umya-spreadsheet (C-12) | MIT. | OK |
| New: @silurus/ooxml + `@silurus/ooxml-legacy-office` (PPT option) | Both MIT (npm 0.89.1). | OK |
| MuPDF AGPL (v2 gate) | GPLv3 §13 permits the combination. The AGPL network clause is irrelevant for a local app. The source obligation already exists. | OK (owner gate stays) |
| LibreOffice auto-download | Not distributed by Zivlet: TDF's own signed DMG, unmodified. Trademark use is nominative ("Office Engine: LibreOffice"). | OK |
| GPLv3 "Installation Information" vs Developer ID signing and library validation | It applies only to "User Products" (consumer devices). A user can rebuild and ad-hoc sign. Sparkle keys restrict nothing. | OK (INFERRED) |
| Registering fonts from a user's Office install (new O-19) | No redistribution, but Microsoft's EULA governs font use by other apps. This needs counsel, so it defaults to off. | Owner/legal decision |
| Patents beyond x264 | ffmpeg's *software decoders* for H.264, HEVC and AAC carry the same theoretical pool exposure as x264. Using `-hwaccel videotoolbox` where possible (11 §8 already allows it) reduces both CPU and exposure. | Note only |

**Conclusion:** the GPL-3.0-or-later choice is sound. The banned list (fdk-aac, unRAR, `--enable-nonfree`) is correct and enforced in CI.

---

## 3. Findings in detail

### C-1 FFmpeg 9 sonames (LOW, build-breaking if hard-coded)

10 §2.2 listed `libavcodec.62 libavformat.62 libavfilter.11 libavutil.60 libswscale.9 libswresample.6`. Those match the **Homebrew 8.1.2** build on the dev Mac. FFmpeg 9.0.2 ships libavcodec 63.1.102, libavformat 63.1.102, libavfilter 12.1.102, libavutil 61.1.102, libswscale 10.1.102 and libswresample 7.1.102 (ffmpeg.org). Any `install_name_tool` or `verify-media.sh` step with hard-coded names would break on the 9.0 build, and the 8.1.3 fallback flips them back. **Fix:** derive the sonames from `otool -D` of the built dylibs.

### C-2 Non-code in `Contents/Helpers` (HIGH)

`Contents/Helpers`, `MacOS` and `Frameworks` are nested-code locations. When `codesign` meets non-Mach-O files there, it writes their signatures into extended attributes (`com.apple.cs.*`). Those attributes don't survive zip, some DMG flows or git, so the app later fails `codesign --verify --strict` or Gatekeeper. Apple's "Placing content in a bundle" guidance is to keep data out of code directories. 10 §2.2 put the trimmed Perl `.pm` tree in `Helpers/perl-lib/`, which also contradicts 10's own §11.2 rule. **Fix applied:** `Resources/perl5/` holds the `.pm` files and the individually signed XS `.bundle`s (hardened runtime, timestamp, our Team ID, so library validation passes on `dlopen`). This is the layout py2app and Briefcase use for Python extension modules, and it notarizes. Spike I-M1 must include `notarytool` + `spctl` on the DMG, not just the `.app`.

### C-3 resvg/svg2pdf version coupling (MEDIUM)

From crates.io:
- `svg2pdf 0.13.0` (2025-03-04, the latest) depends on `usvg ^0.45`, `resvg ^0.45`, `pdf-writer ^0.12`.
- `resvg 0.48.1` depends on `usvg ^0.48.1`, `tiny-skia ^0.12`.

Cargo 0.x caret ranges are minor-locked, so one static library would contain two usvg, two resvg and two tiny-skia copies. That costs size, and the raster and PDF outputs could parse one SVG differently, which defeats spike I-S1. svg2pdf's successor inside Typst is **krilla** (`krilla 0.8.2`, `krilla-svg 0.8.1`, June 2026, MIT OR Apache-2.0), and krilla-svg depends on `usvg ^0.47`, `resvg ^0.47`, `tiny-skia ^0.12`. **Fix applied:** pin resvg `~0.47` + krilla-svg 0.8.1, and add `cargo tree -d` as a CI failure for usvg, resvg and tiny-skia. Fallback: resvg 0.45 + svg2pdf 0.13.

### C-4 ffmpeg local-file disclosure (CRITICAL, security)

10 relied on `--disable-network`. That removes http, tcp and the like, but the **file** protocol stays, and several demuxers follow references:
- HLS playlists, which can be renamed `.mp4`/`.avi`; ffmpeg probes by content;
- ffconcat;
- DASH manifests;
- image2 patterns.

The well-known 2017 attack makes ffmpeg render the bytes of `~/.ssh/id_rsa` or `/etc/passwd` into the output video. A user converts a downloaded "video", posts the result, and the local file leaks. Zivlet runs ffmpeg unsandboxed with the user's full file access, so the exposure is real.

**Fix applied (10 §8.9):**
- disable `hls, dash, webm_dash_manifest, sdp, rtsp, rtp` at build time;
- probe user inputs with `-format_whitelist` = the advertised input demuxers;
- open them with `-f <probed demuxer>` and `-protocol_whitelist file,pipe`;
- allow concat, image2 (`-pattern_type none`) and ffmetadata only for files Zivlet itself wrote into the job folder.

Hostile-corpus fixtures and spike M-HOSTILE prove it.

### C-5 Quarantine laundering through archive re-pack (CRITICAL, security)

Zivlet is unsandboxed and doesn't set `LSFileQuarantineEnabled`, so files it creates carry no `com.apple.quarantine`. 10 §8.5 said "never copy quarantine". Extract (§5 #12) propagates it, but the 9 archive *conversion* pairs (rar/zip/tar/gz → zip/tar/gz) don't. A quarantined download re-packed by Zivlet becomes an unquarantined archive. Anything later extracted from it, by Archive Utility or anything else, skips Gatekeeper's first-launch assessment. That is the same class as Archive Utility CVE-2022-22616 and CVE-2022-32910.

**Fix applied:** propagate the quarantine value from any quarantined input onto **every** output, written on the staged file before the atomic rename. It is harmless for documents and media, because Gatekeeper doesn't prompt for non-executables. The pair matrix asserts this for archive outputs.

### C-6 In-app parsing (MEDIUM)

10 §2.1 Rule 1 claimed the app never parses untrusted files except for UTType sniffing and Quick Look. But the editors (Edit/Annotate/Crop/Redact via Core Image, Organize via `PDFThumbnailView`, Trim/Snapshots via `AVPlayer`/`AVAssetImageGenerator`, waveforms via `AVAudioFile`) all decode in the app. This isn't fatal, since these are Apple decoders and the user opened the window. The rule was false, though, and a false security invariant leads to bad later decisions. **Fix applied:** the rule is restated honestly, and worker-rendered proxies are used for anything not natively handled by AVFoundation or ImageIO.

### C-7 CLI hand-off transport (MEDIUM)

`NSXPCListener(machServiceName:)` requires a launchd job that declares the name. An `LSUIElement` app launched from Finder has none. **Fix applied:** choose either an `SMAppService.agent` with `MachServices`, or a Unix socket in Application Support that checks the peer's code signature from its audit token (`SecCodeCreateWithAuditToken`). Spike P-CLI decides.

### C-8 Drop rejected when a modifier is still held (HIGH, core UX)

AppKit narrows `draggingSourceOperationMask` while modifiers are held during a drag: Control → link, Option → copy, Command → generic (and Finder's move). Zivlet's modes are ⇧ convert, ⌘ tools and ⌃ actions. Zivlet's taps are press-edge (14 §1.3), so many users will keep holding the key until they drop. A destination that returns `.copy` when the mask is `.link` gets **no** `performDragOperation`, and the drop silently fails. **Fix applied:** return the first of `.copy, .generic, .link, .move` present in the mask, always apply copy semantics, and never act destructively based on the negotiated operation. New spike P-T6.

### C-9 Stream copy that the Mac can't play (HIGH)

R-14's per-stream copy is a good idea, but 10 copied **AV1 into MP4/MOV**. 11 measured `VTIsHardwareDecodeSupported(av01) == false` on the M2 Pro, AV1 hardware decode starts at M3, and AVFoundation has no software AV1 decoder. On every M1 and M2 Mac, the "converted" MP4 won't play in QuickTime, Photos or Quick Look. That's worse than simply re-encoding.

The same class of problem:
- HEVC from MKV is often `hev1` (in-band parameter sets). QuickTime wants `hvc1`, so copies must use `-tag:v hvc1`.
- MPEG-4 ASP (Xvid) with packed bitstream, QPel or GMC is unreliable in AVFoundation.

**Fix applied:** an "AVFoundation-playable" predicate (codec + profile + hardware) gates copy into MP4/MOV. AV1 is copied only with hardware decode and outside the default "Maximum compatibility" mode. Every pair test asserts `AVURLAsset.load(.isPlayable)`.

### C-10 CI cannot provide the "clean macOS 26 VM" (HIGH)

GitHub's runner reference says nested virtualization isn't supported on arm64 macOS runners (an Apple Virtualization framework limit), so a hosted job can't boot Tart or UTM. The hosted `macos-26` image is macOS **26.6.2** with Homebrew and other tooling preinstalled. It is neither the 26.0 minimum nor clean.

So these gates can't run as written:
- G-0 re-probe on 26.0;
- `spctl` first-launch on a clean VM;
- Sparkle N-1 → N;
- the capability probe on a pristine OS;
- the TCC behaviour checks.

**Fix applied:** a self-hosted Apple-silicon Tart host with clean 26.0, 26.x and 27.x images (no Homebrew, Office or iWork). That's one Mac mini in Phase 0 (spike P-CI). Hosted runners keep the build and test work.

### C-11 Concurrent print operations (MEDIUM)

The only measured paginated-PDF path is `WKWebView.printOperation(with:)` + `runModal(for:)` on an off-screen window. `NSPrintOperation.current` is per thread, and both RenderHost views are main-actor bound. Running two window-modal print operations at once on one thread hasn't been tested, and its failure modes (serialisation, mixed settings, a blank PDF) would only show under batch load. **Fix applied:** render width 1, with spike D-PRINT2 to earn width 2. The layout step stays parallel; only the print step is serialised.

### C-12 xlsx → pdf loses styling (HIGH, quality)

A POI-based renderer (Java POI + PDFBox) reads full cell styles. In the SheetJS CE 0.20.3 build from cdn.sheetjs.com, the only per-cell style is `p.s = styles.Fills[fillid]`. Fonts and borders are parsed into tables but never attached to cells (verified in `xlsx.mjs`). So a styled report prints as a plain grid: no bold header, no borders, no font colour. That is a visible regression on a headline route. **Fix applied:** bring `umya-spreadsheet` 3.1.x (MIT, Rust, released 2026-10-12) into `libzivlet_rs` in Phase 2 as the XLSX style reader for the HTML print path. SheetJS CE stays for XLS/ODS/CSV reading and all writers. New spike D-XLSX-STYLE. XLS (BIFF) styling remains Tier 2 (LO).

### C-13 cupertino-files maturity (HIGH, maintenance)

From GitHub (2026-10-20): `den-frie-vilje/cupertino-files` has **4 stars**, was created **2026-07-30**, and has one open issue. Its commits are 155 by an AI agent, 85 by the maintainer and 3 by a bot. It is the only Tier 1 engine for **16 pairs** (pages → 8; docx/md/rtf/rtfd/textClipping/txt/epub/pdf → pages). 10's X5 rated this Med / High, which understates it.

**Fix applied:**
- X5 raised to High / High;
- D-PAGES moved to gate B (before the dependent Phase 3 work);
- Pages input falls back to the package's `preview.jpg` / `QuickLook/Preview.pdf` with a notice;
- Pages output falls back to the Pages app via Apple Events (iWork is preinstalled on most Macs) if the bar fails;
- budget to fork (MIT).

pptx-renderer (131 stars, 8 months old, one maintainer) is also young. `@silurus/ooxml` (849 stars, very active, MIT, Rust/WASM + Canvas) should be the D-RENDER comparison. Its MIT `@silurus/ooxml-legacy-office` add-on reads a subset of **binary PPT**. That makes it the most credible way to give the 3 PPT pairs a Tier 1, raster-only answer instead of "needs LibreOffice".

### C-14 Cover art survives "Remove all" (HIGH, privacy)

The ffmpeg strip recipe `-c copy -map 0 -map_metadata -1` keeps `attached_pic` streams. An MP3 or FLAC cover JPEG can carry its own EXIF with GPS and camera serials, so "No GPS left" fails. **Fix applied:** drop the stream with `-map -0:disp:attached_pic` (the `disp:` specifier is documented in FFmpeg 9.0 `fftools-common-opts`), or re-encode the cover through ImageIO without properties. M-META covers this case.

### C-15 Redact Video filtergraph scaling (MEDIUM, performance)

A drawbox node per box per time slice, each with `enable='between(t,…)'`, grows linearly with track length × objects. Every node is evaluated on every frame, so a 10-minute tracked face produces thousands of nodes. **Fix applied:** one drawbox (or blur chain) per track driven by `sendcmd`, or a Swift-rendered grey mask piped in as rawvideo + `maskedmerge`. Pass bar: ≥ 1× realtime for 10 min 1080p with 3 tracks (M-REDACT).

### C-16 AVIF fallback quality (MEDIUM)

If G-0 finds ImageIO can't write AVIF on 26.x, the fallback `ffmpeg -c:v libsvtav1 -svtav1-params avif=1 -pix_fmt yuv420p` is valid. But it drops alpha, subsamples chroma and carries no ICC, EXIF or XMP, which contradicts 10's own image rules. **Fix applied:** an honest card copy, `tune=3` and `yuv444p` for graphics, hiding AVIF for alpha sources on such OSes, and libavif (+about 3 MB) as the gated proper fix.

### C-17 Biased measurement environment (MEDIUM)

`/Applications` on the dev Mac contains Microsoft Word (its `DFonts` include the full Aptos family), Keynote, Pages and Numbers. Document fidelity runs there will over-score Tier 1 and never exercise the "Needs Office Engine or Keynote" paths. 12 §4.10 already notes Aptos has no metric clone; Office has defaulted to Aptos since 2024. **Fix applied:** fidelity spikes run on a clean Tart image. O-19 asks counsel whether fonts from a local Office install may be registered process-locally (`CTFontManagerRegisterFontsForURL(.process)`) when present.

### C-18 Schedule (HIGH, planning)

Phases 0–3 add up to 3 + 6–8 + 8–10 + 10–12 = **27–33 weeks** for one engineer. That time covers 275 pairs, 27 tools (8 of them editor-heavy), five SDoc writers with external validators (EPUBCheck, Word without repair), Vision/PDFKit fusion, the Pages bridge, App Intents, the CLI and accessibility. This is not credible. **Fix applied:** O-18. Plan 12–18 months to the full route matrix, or define 1.0 = Phases 1–2 (221 pairs, 19 tools) and move Phase 3 to 1.x.

### C-19 Output-name consistency (LOW)

The output names used in 10 for Speed, Create PDF and the Metadata tools do not match the names in the product spec. **Fix applied:** the differences are listed so O-16 decides them explicitly, with the product spec's names as the default.

### C-20 Trigger details (MEDIUM)

- **Wake-up monitor cost.** A global `leftMouseDragged` monitor fires for *every* drag in every app, at the mouse's report rate (up to 1 kHz on gaming mice), on our main thread. **Change:** act on the first dragged event of a drag, compare `dragPB.changeCount`, then remove the dragged monitor until `leftMouseUp`. The display-link sampler takes over only for file drags (spike P-T1 extended).
- **Correct petals in ≤ 16 ms.** 14 §2.2 builds provisional petals from the drag pasteboard *type* (which is `public.file-url`, not the file's content type) and refines them on `draggingEntered`. `draggingEntered` only fires on the next mouse movement after the panel appears, so the first frames can show the wrong wheel. Reading the file URLs from the **drag** pasteboard at tap time is allowed by the AppKit header ("all other pasteboards default to always allow"), and `URLResourceValues.contentType` is cheap. Cap it at the first N items. G-0 is extended to re-test this with `EnablePasteboardPrivacyDeveloperPreview` on 26.x and 27.x. 14's R2 stance (no URL reads mid-drag) becomes the fallback, not the default.
- **Esc inconsistency.** 10 P-T3 tests a Carbon `RegisterEventHotKey` Esc (no permission). 14 makes "Esc closes the wheel" an opt-in Input-Monitoring `CGEventTap`. Pick one. If Carbon passes P-T3, register the bare-Esc hotkey **only while the wheel is visible**, because a registered Esc hotkey swallows Esc system-wide.
- **Latency budget.** Sampling on vsync gives ≤ 2 frames, as 14 says. On a 60 Hz external display that's up to 33 ms, which 10 already documents. If S-T2 confirms that `flagsChanged` taps arrive without permission (the tap is *created* without a prompt on macOS 27, OBSERVED), the event path should be the default.

### C-21 Idle memory target (LOW)

"< 30 MB RSS idle" with a pre-warmed `NSHostingView` + `GlassEffectContainer` panel is optimistic; SwiftUI menu-bar apps typically sit at 40–70 MB. **Fix applied:** measure in P-W1 and set the gate from data. RenderHost web views are lazy and torn down when idle.

### C-22 FinderSync app group (LOW, 1.x)

Since macOS 15, group containers are TCC-protected. Developer ID apps must use Team-ID-prefixed group identifiers, and both the app and the extension need the entitlement, or users see an "access data from other apps" prompt. **Fix applied** as a note in §11.2.

### C-23 ogg default (LOW)

ffmpeg's ogg muxer defaults to Vorbis when libvorbis is compiled in, and to FLAC otherwise. The "VERIFIED-LOCAL" observation came from the Homebrew build without libvorbis (`ffmpeg -h muxer=ogg` → "Default audio codec: flac"). Forcing `libvorbis` stays correct.

---

## 4. Notarization and signing: attack list

| Pitfall | 10's coverage | Verdict |
|---|---|---|
| Non-Mach-O in code directories | contradicted itself | **fixed** (C-2) |
| Mach-O outside code directories (Perl XS in `Resources/`) | — | allowed. Each bundle must be signed (hardened runtime, timestamp) **before** the app seal; notary scans `Resources`. `verify-signatures.sh` must walk every Mach-O, not only `Helpers` and `Frameworks` |
| `--deep` signing | banned | correct |
| Helper identifiers | — | sign with explicit `-i app.zivlet.ffmpeg` etc., so the designated requirement is stable for the `SecStaticCodeCheckValidity` check in §8.9 |
| `allow-jit` on zivlet-js | yes | notary accepts it; scope is correct |
| `disable-library-validation` on the 1.x LibreOfficeKit helper | yes | acceptable, but that helper must never load anything except TDF's verified `libmergedlo.dylib`. Pin by path + Team ID before `dlopen` |
| Unsandboxed XPC service inside an unsandboxed app | yes | supported |
| Sparkle 2.10's XPCServices in an unsandboxed app | bundled | not needed when unsandboxed. They can stay (signed) or be removed; Sparkle documents both. Keep them to reduce surprises |
| DMG notarize + staple, then `spctl` | yes | correct. Run it on the self-hosted clean VM (C-10) |
| `Code Sign On Copy` trust | spike M-2 | correct to distrust until proven |

---

## 5. Fidelity and coverage (route-by-route stress)

| Route family | Zivlet engine | Assessment after the fixes |
|---|---|---|
| Images (49) | ImageIO + libwebp in-process | **strong** (animated WebP, gain maps, ICC). AVIF on 26.0 unverified (G-0, C-16) |
| SVG (8) | resvg + krilla-svg | **strong** (vector PDF with real text) |
| Audio (56) | ffmpeg GPL full codecs | **strong** (Opus, Vorbis work) |
| Video (42) + GIF (6) | ffmpeg GPL + VT | **strong** once C-9 gating is in. Without it, AV1 → MP4 would be unplayable on M1/M2 |
| PDF (9) | PDFKit + Vision fusion | meets the bar, plus tables via `RecognizeDocumentsRequest` |
| Documents (65) | web/JS renderers + SDoc writers + cupertino-files | DOCX meets the bar. **Pages risk** (C-13). Aptos fonts (C-17) affect any renderer without Office fonts |
| Slides (6) | pptx-renderer; PPT needs LO/Keynote | **gap on 3 PPT pairs** (no Tier 1) unless `@silurus/ooxml-legacy-office` passes D-RENDER as a raster Tier 1 |
| Sheets (21) | SheetJS CE (+ umya for styles, after the fix) | meets the bar after C-12. Without it, xlsx → pdf looks visibly plain |
| Subtitles (4) | own | meets the bar |
| Archives (9) | libarchive | meets the bar. **Security fix C-5 required** |
| Tools (27) | mapped in §5 | covered. Redact Video performance (C-15), metadata privacy (C-14) |
| Actions (6) | AppKit | meets the bar. Drop-mask fix (C-8) applies to all wheels |

Missing routes or tools: none against the product spec's route matrix (45 inputs, 275 pairs; recounted per category, total 275 ✓) or its tool list (27 tools). The per-format extras in the spec are also covered by §5's input sets: Read QR for svg, avif, bmp, gif and pdf, and Metadata for gif. The doc tables should list them explicitly.

---

## 6. Size and maintenance

- **Size:** the media row is corroborated at about 25 MB (Homebrew dylib measurements). The unmeasured risk is Swift code and assets. C-3 saves about 1.5–2 MB of duplicate Rust crates. The umya addition costs about +1–1.5 MB (ESTIMATE). Net, the 70 MB target is unchanged and still unproven until the Phase 0 hello-DMG.
- **Maintenance risk ranking**, highest first:
  1. cupertino-files (C-13);
  2. pptx-renderer;
  3. svg2pdf (stale, replaced);
  4. SheetJS CE (CDN-only distribution; npm stuck at 0.18.5 with known CVEs, as 10 notes);
  5. ExifTool and FFmpeg: very active, which is a security-patch *cadence* load rather than a staleness risk;
  6. ZIPFoundation 0.9.20 (2025-09): slow but stable.

---

## RECOMMENDATION

**Choice.** Keep the strategy in 10 (native-first, process-isolated, GPL-3.0-or-later; FFmpeg 9.0.2 GPL build; ImageIO/Core Image + libwebp; PDFKit + qpdf; Tier 1 web/JS document stack with optional LibreOffice and iWork; ExifTool on bundled Perl; libarchive; permission-free hybrid trigger), with the corrections from this review now written into 10:
1. FFmpeg 9 sonames derived from the build.
2. Perl lib in `Resources/perl5`.
3. resvg 0.47 + krilla-svg instead of svg2pdf.
4. ffmpeg demuxer and protocol confinement.
5. Quarantine propagated to every output.
6. AVFoundation-playable gating for stream copy.
7. Operation-mask-tolerant drops.
8. render width 1.
9. umya-spreadsheet for styled XLSX in Phase 2.
10. D-PAGES at gate B, with the @silurus PPT/PPTX evaluation.
11. Cover-art stripping.
12. sendcmd/mask redaction.
13. A self-hosted Tart CI host.
14. A realistic 1.0 scope or date (O-18).

**Rationale.** None of the attacks broke the architecture or the licence: every component checks out as GPLv3-compatible, every version exists as stated, and every macOS 26 API used without `#available` is documented at 26.0 or earlier. What broke were specific mechanisms:
- two exploitable security gaps (C-4, C-5);
- one core-UX failure mode (C-8);
- two quality regressions hidden behind optimistic defaults (C-9, C-12);
- a CI plan that hosted runners can't execute (C-10);
- a schedule about 2× too short (C-18).

All of them can be fixed without changing the stack.

**Risks that remain.**
- ImageIO AVIF writing and the WKWebView print path on 26.0 are still unverified (G-0 on the new Tart host).
- cupertino-files may simply not reach the D-PAGES bar.
- Pasteboard-privacy enforcement could later extend beyond the General pasteboard.
- Office Aptos documents will reflow without LibreOffice or local Office fonts.
- The self-hosted CI Mac is a single point of failure.
- The ExifTool, FFmpeg and libarchive security cadence demands fast releases.

**Fallback.**
- If D-PAGES fails: Pages output via the Pages app (iW) only, and Pages input via the embedded preview with a notice.
- If D-PRINT2 fails: render width stays 1.
- If umya styles miss the bar: LO "Best fidelity" for styled sheets.
- If AV1 hardware detection proves unreliable: never copy AV1 into MP4/MOV.
- If the self-hosted CI slips: a manual clean-VM release checklist on the owner's Mac per release, as a stopgap only.
- If the schedule can't stretch: ship 1.0 as Phases 1–2 (221 pairs, 19 tools, 6 actions) and label the remaining routes "coming in 1.x" in the catalog, never as broken slices.

---

### Sources

- FFmpeg downloads and versions: https://ffmpeg.org/download.html ; Changelog `release/9.0`: https://github.com/FFmpeg/FFmpeg/blob/release/9.0/Changelog ; stream specifiers: https://github.com/FFmpeg/FFmpeg/blob/release/9.0/doc/fftools-common-opts.texi
- crates.io: svg2pdf https://crates.io/crates/svg2pdf , krilla-svg https://crates.io/crates/krilla-svg , resvg https://crates.io/crates/resvg , imagequant https://crates.io/crates/imagequant , umya-spreadsheet https://crates.io/crates/umya-spreadsheet , calamine https://crates.io/crates/calamine
- SVT-AV1 parameters (v4.2.0): https://gitlab.com/AOMediaCodec/SVT-AV1/-/blob/v4.2.0/Docs/Parameters.md
- SheetJS CE 0.20.3 build: https://cdn.sheetjs.com/xlsx-0.20.3/package/xlsx.mjs
- npm: @aiden0z/pptx-renderer, cupertino-files, @silurus/ooxml, @silurus/ooxml-legacy-office, docx-preview, mammoth, mtx-decompressor, exceljs (`npm view`, 2026-10-20)
- GitHub repos and releases: libvpx, opus, libarchive, qpdf, resvg, Sparkle (CHANGELOG, `SUConstants.m`), swift-subprocess, oxipng, libimagequant, libwebp, xz, zstd, dav1d, ZIPFoundation, SwiftSoup, KeyboardShortcuts, den-frie-vilje/cupertino-files, aiden0z/pptx-renderer, yukiyokotani/office-open-xml-viewer
- ExifTool version: https://exiftool.org/ver.txt ; LibreOffice stable index: https://download.documentfoundation.org/libreoffice/stable/
- LibreOffice Team ID (third-party): [appcatalog.cloud — LibreOffice](https://appcatalog.cloud/apps/libreoffice)
- Apple documentation JSON: RecognizeDocumentsRequest, DocumentObservation.Container.Text (`detectedData`), GenerateIterativeSegmentationRequest, TrackObjectRequest, DetectBarcodesRequest, GenerateForegroundInstanceMaskRequest, PDFDocumentWriteOption.saveTextFromOCROption, NSScreen.displayLink(target:selector:), CIToneMapHeadroom; [NSPasteboard.AccessBehavior.default](https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum/default.md)
- Pasteboard privacy background: [Michael Tsai, 2025-05-12](https://mjtsai.com/blog/2025/05/12/) ; [appletreats: macOS 16 will warn when apps access pasteboard](https://appletreats.substack.com/p/macos-16-will-warn-when-apps-access) ; [MacTech coverage](https://www.mactech.com/2025/05/13/apple-clipboard-tweak-prevents-mac-apps-from-accessing-iphone-data-without-user-permission/amp/) ; [DEV Community note on enforcement status](https://dev.to/jrw0ng/macos-tahoe-has-built-in-clipboard-history-heres-what-its-still-missing-for-developers-2026-4eko)
- GitHub runners: https://github.com/actions/runner-images (README, `macos-26-arm64-Readme.md`); nested virtualization: [GitHub-hosted runners reference](https://docs.github.com/ru/actions/reference/github-hosted-runners-reference) , [runner-images issue #9254](https://github.com/actions/runner-images/issues/9254) , [mirego/ekiden](https://github.com/mirego/ekiden)
- Local measurements (dev Mac, 2026-10-20): `sw_vers`; Homebrew FFmpeg 8.1.2 dylib sizes; `ffmpeg -h muxer=ogg`; `/Applications` inventory (Word, Keynote, Pages, Numbers); Word `DFonts` listing (Aptos family)
