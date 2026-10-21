# 13 — Image, PDF, Metadata, Archive, Subtitle and Vision Engine

Status: design recommendation (engine track: images-pdf). Date: 2026-10-20.
Scope: raster images, SVG, PDF, metadata, archives, subtitles, Vision (background removal, redaction detection, QR, OCR).
Constraints (from `00-decisions.md`): direct download, notarized Developer ID, **not sandboxed**, **macOS 26+**, Apple silicon first, Swift 6 + SwiftUI/AppKit, fully free and open source. The app license is expected to be **GPLv3**, so GPL/LGPL/Apache-2.0/BSD/MIT components are all allowed.
Rule: Zivlet is a clean-room implementation; never copy code from the reference app or from Open-Tangerine. Common approaches in existing converter apps are a baseline we have to beat, not a template.

Evidence labels: **PROBED** = measured on this machine by running code; **DOC** = vendor documentation, SDK header or release page; **EST** = estimate that a spike must confirm.

Probe machine: macOS **27.0** (build 26A428), arm64, Swift 6.4, SDKs `MacOSX26.sdk` and `MacOSX27.0.sdk`. Our minimum OS is 26, so every PROBED result below must be re-run on a macOS 26.x VM in CI (spike S-0).

---

## 0. TL;DR — engine per capability

| Capability | Primary engine | Add-on (bundled) | Rejected / deferred |
|---|---|---|---|
| Raster decode (JPEG, PNG, HEIC/HEIF, AVIF, **JPEG XL**, **WebP**, TIFF, BMP, GIF, ICO/CUR, ICNS, **PSD**, **RAW** ×40 vendors, EXR, DDS, TGA, JPEG 2000, DICOM) | **ImageIO** (PROBED, 62 readable UTIs) | — | libvips |
| Raster encode JPEG, PNG, HEIC, AVIF, TIFF, BMP, GIF, ICO (≤256 px), ICNS, PSD (flattened), JPEG 2000, EXR | **ImageIO** (PROBED, 22 writable UTIs) | — | — |
| WebP encode (still, animated, target size) | — | **libwebp 1.6.0** (BSD-3), linked in-process | ffmpeg route, `cwebp` CLI |
| JPEG XL encode | — | **libjxl 0.12.0** (BSD-3 + patent grant), P1 | — |
| Better PNG/JPEG compression | ImageIO | **libimagequant** (GPL-3.0+) + **oxipng 10.2** (MIT) for PNG, P1; **jpegli** (from libjxl) for JPEG, P2 | mozjpeg |
| Edit, adjust, crop, annotate, RAW develop | **Core Image** (`CIRAWFilter`, 252 filters PROBED) + CoreGraphics/CoreText | — | — |
| SVG → raster | **resvg 0.48.1** (Apache-2.0 OR MIT) via its C API | fallback: `NSImage` CoreSVG (PROBED: works, but ignores the CSS `font` shorthand) | librsvg (LGPL, cairo/pango/glib stack) |
| SVG → PDF (vector) | **svg2pdf 0.13** (Apache-2.0 OR MIT, same `usvg` tree as resvg) | fallback: offline `WKWebView.createPDF` | — |
| PDF merge / split / reorder / rotate / images→PDF / PDF→images | **PDFKit + Quartz** | — | pdfium, MuPDF |
| PDF compress (lossy, image downsampling) | **Quartz filter built at runtime** (`QuartzFilter(properties:)`, PROBED 14.7 MB → 0.86–6.8 MB with controllable quality and DPI) | **qpdf 12.4.2** (Apache-2.0) structural pass: object streams, Flate recompression, metadata history scrub | Ghostscript (AGPL, heavy); PDFKit `saveImagesAsJPEG` (PROBED: no-op on unmodified docs) |
| PDF linearize / repair / AES-256 encrypt / decrypt | — | **qpdf** (libqpdf via `qpdfjob` JSON C API) | — |
| PDF redaction | v1: **rasterise affected pages** (Quartz) + optional OCR layer for kept text | v2 decision gate: **MuPDF** `pdf_redact_page` (AGPL; FSF says AGPLv3 and GPLv3 may be combined) | PDFKit annotations (not redaction) |
| Image metadata read / edit / strip (all formats incl. HEIC, AVIF, JXL, WebP, PNG, RAW, MP4/MOV, PDF) | **ExifTool 13.59** (Artistic/GPL) in a persistent `-stay_open` process | Perl: **bundled trimmed relocatable Perl 5.42/5.44** (primary) with `/usr/bin/perl` 5.34.1 as fallback | exiv2 (cannot write HEIC/AVIF/JXL); ImageIO-only (PROBED: HEIC/PSD writes silently no-op, AVIF refused) |
| Quick metadata display (no edit) | ImageIO `CGImageSourceCopyMetadataAtIndex`, AVFoundation `AVAsset.load(.metadata)`, PDFKit `documentAttributes` | — | — |
| Archive extract (ZIP, TAR, GZ/BZ2/XZ/ZSTD, **RAR4, RAR5 incl. solid**, 7z, ISO, CAB, LHA, XAR, CPIO) | **libarchive 3.8.10** (BSD-2), bundled static | — | system `/usr/bin/tar`, `ditto`, `unzip` subprocesses; system libarchive (no public headers) |
| Archive create (ZIP incl. AES-256, TAR(.gz/.xz/.zst), **7z** LZMA2) | **libarchive** | `ditto -c -k --sequesterRsrc` only for "Mac-faithful ZIP" (resource forks, xattrs) | RAR creation (proprietary format; dropped) |
| Encrypted RAR / encrypted 7z extract | — | deferred; optional **7-Zip 26.04** `7zz` built **without RAR** codecs, 7z AES only | unRAR code (licence is GPL-incompatible) |
| Subtitles SRT ↔ VTT (+ read ASS/SSA/SBV later) | **own Swift module** | — | SwiftSubtitles (MIT, fine but low activity) |
| QR / barcode read | Vision `DetectBarcodesRequest` (PROBED) | — | ZXing ports |
| Background removal | Vision `GenerateForegroundInstanceMaskRequest` (PROBED 0.5 s at 1600×1000) | macOS 27: `GenerateIterativeSegmentationRequest` (seed point / box / scribble) | bundled CoreML models |
| Face / text / PII detection for redaction | Vision `DetectFaceRectanglesRequest`, `RecognizeTextRequest`, **`RecognizeDocumentsRequest` + `DataDetectorMatch`** (PROBED: finds e-mail and phone) | — | regex-only PII |
| OCR (PDF → DOCX/MD, searchable PDF) | `RecognizeDocumentsRequest` (macOS 26, paragraphs, tables, lists) | — | Tesseract |

**Net new native dependencies:** libwebp, libarchive (+xz, zstd, lz4), qpdf (+libjpeg-turbo), one Rust static library (`resvg` + `svg2pdf` + `oxipng` + `imagequant`), ExifTool + trimmed Perl. P1/P2: libjxl. Gated: MuPDF, 7zz. Estimated added size: **~25–35 MB** (EST, §10).

---

## 1. What we have to beat (common shortcuts we avoid)

| Area | Common shortcut | Zivlet approach |
|---|---|---|
| WebP | Render a temp PNG, pipe it through an external encoder process, then patch metadata back in. Target size via an external CLI. No animated WebP. | Several processes and a temp file per image, and animation is lost. We link libwebp and use `WebPConfig.target_size` / `WebPAnimEncoder` / `WebPMux` directly. |
| AVIF | Fall back to an external AV1 encoder that may not be present. | ImageIO AVIF is writable on 26/27; no fallback needed (re-verify on 26.0). |
| SVG | Offline WKWebView render. Input only. | Off-main-thread resvg, deterministic, ~ms per file; vector SVG → PDF. |
| PDF compress | Opaque Quartz/PDFKit save options. | Runtime Quartz filter with explicit quality/DPI search + qpdf structural pass + "never bigger than input" guard. |
| Metadata | ExifTool on the deprecated system `/usr/bin/perl`, one Perl start-up per file. | A fail-closed read → plan → write → verify contract (§5.4), a bundled Perl, and a persistent ExifTool process (no ~0.2 s Perl start-up per file, EST). |
| Archives | `/usr/bin/tar`, `ditto`, `zip`, `gzip` subprocesses; a store-only RAR writer. | In-process libarchive with traversal/symlink/bomb guards; 7z and AES-ZIP creation; no RAR writing. |
| Vision | Barcodes, faces, text. No background removal. | Foreground masks, document-level OCR with data detectors for one-click PII redaction, macOS 27 interactive segmentation. |

---

## 2. Raster images

### 2.1 ImageIO on macOS 26/27 — PROBED capability matrix

`CGImageDestinationCopyTypeIdentifiers()` (22 types) and `CGImageSourceCopyTypeIdentifiers()` (62 types), macOS 27.0:

| Format | Read | Write | Notes |
|---|---|---|---|
| JPEG | ✓ | ✓ | 12 MP synthetic image, q 0.8: 1.48 MB in **0.05 s** (PROBED). |
| PNG | ✓ | ✓ | 12 MP: 12.1 MB in 0.41 s. ImageIO PNG is not size-optimised → oxipng/libimagequant (§2.4). |
| HEIC / HEIF / HEICS | ✓ | ✓ (HEIC, HEICS) | q 0.6: 526 KB in 0.18 s (hardware HEVC). HDR gain-map output via `kCGImageDestinationEncodeToISOHDR` (DOC, macOS 15+). |
| AVIF | ✓ | ✓ | q 0.6: **335 KB in 0.29 s** (PROBED). No knobs for speed, chroma subsampling or bit depth. `public.avis` (animated) is **read-only**. |
| **WebP** | ✓ (incl. animated) | **✗** | `CGImageDestinationCreateWithURL(…, "org.webmproject.webp")` returns nil (PROBED). |
| **JPEG XL** | ✓ | **✗** | Read-only. |
| TIFF | ✓ | ✓ | Multi-page read and write via frame index. |
| BMP | ✓ | ✓ | — |
| GIF | ✓ | ✓ | Animated read/write via `kCGImagePropertyGIFDictionary` (`DelayTime`, `LoopCount`). No palette optimisation; video → GIF belongs to the ffmpeg engine. |
| ICO / CUR | ✓ / ✓ | ICO ✓ | Multi-size ICO 16/32/48/256 written and read back as 4 frames. **A 512 px frame makes `Finalize` fail** (PROBED) → clamp to 256. |
| ICNS | ✓ | ✓ | 16…1024 multi-size works (PROBED). |
| PSD | ✓ | ✓ | Read = **flattened composite only** (files saved without "Maximize Compatibility" may have no composite → show an error). Write = flattened single layer (40 MB for 12 MP). |
| Camera RAW | ✓ (≈40 UTIs: CR2/CR3/NEF/ARW/RAF/ORF/RW2/DNG…) | ✗ | Use `CIRAWFilter` for exposure, white balance, boost and noise reduction before export. |
| OpenEXR, Radiance HDR | ✓ | EXR ✓ | Tone-map to SDR with `CIToneMapHeadroom` (PROBED present) when the output is 8-bit. |
| JPEG 2000, TGA, DDS, KTX/KTX2, ASTC, PVR, PBM, DICOM, MPO, PICT, SGI | ✓ | most ✓ | Free extra inputs; expose only a curated subset in the wheel. |
| SVG | ✗ in ImageIO | ✗ | `NSImage` decodes it through `_NSSVGImageRep` (PROBED); see §3. |

**Rules:**
- Always feature-detect with `CGImageDestinationCopyTypeIdentifiers()` at launch and cache. Never hard-code from this table.
- Decode with `CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceThumbnailMaxPixelSize` + `kCGImageSourceCreateThumbnailWithTransform: true` for resizing (fast, memory-bounded, applies EXIF orientation).
- Preserve colour: keep the source ICC profile (Display P3 from iPhones) unless the user picks "Web (sRGB)". Convert with `CGImage.copy(colorSpace:)` or Core Image's working space.
- Preserve animation: if the source frame count > 1 and the target supports animation (GIF, WebP via libwebp, HEICS, APNG via ImageIO PNG `kCGImagePropertyAPNGDictionary`), write all frames. Otherwise warn "Animation flattened to first frame".
- HDR: when the source has a gain map (`kCGImageSourceDecodeToHDR` / ISO HDR) and the target is HEIC/AVIF/JPEG, keep it with `kCGImageDestinationEncodeToISOHDR`; else tone-map. Feature-gate per OS (spike S-3).

### 2.2 libvips vs direct libraries

| | libvips 8.18.7 (LGPL-2.1) | Direct: ImageIO + libwebp (+ libjxl) |
|---|---|---|
| Coverage gain over ImageIO | WebP/JXL write, AVIF knobs, animated WebP, streaming huge images, smart crop | WebP write/anim/target size; JXL write |
| Footprint | `@img/sharp-libvips-darwin-arm64` 1.3.4 (sharp's prebuilt libvips + deps) unpacks to **18.2 MB** (npm registry); pulls glib, gobject, libheif, aom, librsvg/cairo/pango, lcms2, expat… | libwebp static ~0.5–1 MB (EST); libjxl ~3–5 MB with highway + brotli (EST) |
| Duplication | Re-implements decode/colour/resize that ImageIO and Core Image already do with hardware HEVC, Apple RAW and P3 colour management | None |
| Concurrency | GObject ref-counting, global init and cache; fine but foreign to Swift 6 strict concurrency | Plain C structs, easy to wrap in `Sendable` value types |
| Licence | LGPL (fine for GPLv3) | BSD-3 |

**Decision: no libvips.** ImageIO already covers 20 of the 22 formats we need to write, and the missing two (WebP, JXL) are single focused libraries. libvips would add ~18 MB and a second colour pipeline that disagrees with Apple's.

### 2.3 libwebp 1.6.0 (BSD-3) — required

Latest tag `v1.6.0` (GitHub, the only newer tag is a spec tag `webp-rfc9649`). Libraries used: `libwebp` (encode), `libwebpmux` (ICCP/EXIF/XMP chunks, animation container), `libsharpyuv` (better RGB→YUV, already default in 1.6), `libwebpdemux` (only if we ever decode animation ourselves; ImageIO already decodes).

```bash
cmake -S libwebp -B build -G Ninja \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DBUILD_SHARED_LIBS=OFF -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF \
  -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF \
  -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF \
  -DWEBP_BUILD_EXTRAS=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build
xcodebuild -create-xcframework -library build/libwebp.a -headers include/ … -output WebP.xcframework
```

Swift API (our module `ZivletWebP`):
- Still: `WebPConfigInit` → `config.quality`, `config.method = 4…6`, `config.use_sharp_yuv = 1`, `config.lossless` / `config.exact` for alpha. `WebPPictureImportRGBA` from a `CGImage` drawn into an sRGB/P3 8-bit RGBA buffer (premultiplied → unpremultiply first).
- **Target size** natively: `config.target_size = bytes; config.pass = 6` (the same algorithm `cwebp -size` uses), so no outer binary search is needed for WebP.
- Metadata: `WebPMuxSetChunk(mux, "ICCP"|"EXIF"|"XMP ", …)` from the source's ICC data and the ExifTool/ImageIO-produced EXIF/XMP blobs.
- Animation: `WebPAnimEncoderNew` / `WebPAnimEncoderAdd(frame, timestamp_ms)` / `WebPAnimEncoderAssemble`, frames from `CGImageSourceCreateImageAtIndex` with GIF/HEICS/APNG delays.
- Never write lossless WebP as an automatic fallback when it would be bigger than the source (a known failure mode); use the global "never bigger than input" guard (§2.6).

### 2.4 Optional compression boosters

| Library | Version / licence | Use | Priority |
|---|---|---|---|
| **libjxl** | 0.12.0 (2026-07-01), BSD-3 + PATENTS grant | JPEG XL encode (lossy, lossless, **lossless JPEG recompression** ≈ −20% with bit-exact reversibility). Decode stays in ImageIO. | P1 (Clop offers JXL) |
| **jpegli** | ships inside the libjxl repo, BSD-3 | libjpeg-API-compatible JPEG encoder with better quality per byte than libjpeg-turbo; drop-in for "Compress JPEG" when we already build libjxl | P2; A/B against ImageIO with SSIMULACRA2/butteraugli before switching |
| **libimagequant** (via Rust crate `imagequant`) | GPL-3.0-or-later (or commercial) — compatible with a GPLv3 app | Lossy PNG palette quantisation (pngquant-style, typically −60–80% on screenshots) | P1 for "Compress PNG" |
| **oxipng** | 10.2.1 (2026-09-02), MIT | Lossless PNG re-deflate (zopfli/libdeflate) | P1 |
| mozjpeg | BSD/IJG | Superseded by jpegli for our use | Rejected |

Build: libjxl with `-DJPEGXL_ENABLE_TOOLS=OFF -DJPEGXL_ENABLE_JPEGLI=ON -DJPEGXL_ENABLE_SJPEG=OFF -DJPEGXL_ENABLE_SKCMS=ON -DJPEGXL_BUNDLE_LIBPNG=OFF -DBUILD_TESTING=OFF -DBUILD_SHARED_LIBS=OFF` (it vendors highway + brotli as submodules).

### 2.5 Core Image for tools

- **Edit/Adjust**: `CIExposureAdjust`, `CIColorControls`, `CIHighlightShadowAdjust`, `CITemperatureAndTint`, `CIVibrance`, `CISharpenLuminance`, `CINoiseReduction`, `CIVignette`; render with a single `CIContext(options: [.workingColorSpace: extendedLinearDisplayP3, .cacheIntermediates: false])` per job.
- **RAW**: `CIRAWFilter(imageURL:)` → `exposure`, `neutralTemperature`, `boostAmount`, `luminanceNoiseReductionAmount`; `isGainMapEnabled` / `extendedDynamicRangeAmount` for HDR output.
- **Redact**: solid fill by default; `CIPixellate` with scale ≥ max(16 px, 4% of the short edge); `CIGaussianBlur` only with radius ≥ 30 px and a warning (light blur is reversible).
- **Add BG / Collage / Annotate**: CoreGraphics + CoreText into a P3 `CGContext`; masks from Vision (§8.2) composited with `CIBlendWithMask`.
- **QR generate (bonus)**: `CIQRCodeGenerator` (PROBED present).

### 2.6 Compress to target size (images)

1. If the target is WebP → libwebp `target_size` (single call).
2. Else binary-search `kCGImageDestinationLossyCompressionQuality` in [0.30, 0.92] (max 7 encodes, encode to `CFMutableData`, not disk). If the smallest quality still misses, step `kCGImageDestinationImageMaxPixelSize` down by 15% and repeat (max 3 steps). Report "Smallest attempt was X", and keep the best attempt instead of failing.
3. **Guard**: for any compress/size-oriented action, if the output ≥ input size, keep the original and report "Already optimal".

---

## 3. SVG rendering

### 3.1 Options

| Engine | Version / licence | Fidelity | Integration cost | Verdict |
|---|---|---|---|---|
| `NSImage` / CoreSVG (`_NSSVGImageRep`) | system | PROBED on macOS 27 with gradients, `feGaussianBlur`, `clipPath`, `pattern`, dashed strokes, `<style>` classes: shapes, filters, clip and pattern correct; **`font: bold 36px Helvetica` shorthand ignored** (text fell back to small Times). Private rep class; behaviour changes with OS. | zero | Fallback only |
| **resvg** | 0.48.1 (2026-08-02), **Apache-2.0 OR MIT** (relicensed from MPL), Rust, linebender org | ~1600-test suite, the best static-SVG conformance among non-browser renderers (its published support table). Unsupported: SVG fonts, `color-profile`, external `use`; no scripting/animation (we do not want those). | C API crate `crates/c-api` (`resvg.h`, cbindgen) → static lib; the CLI is < 5 MB with no external deps (README) | **Primary for SVG → PNG/JPEG/WebP/HEIC/TIFF/ICO** |
| **svg2pdf** | 0.13.0, Apache-2.0 OR MIT (typst) | Converts the same `usvg` tree to **vector PDF** (text as real text where possible) | Same Rust lib | **Primary for SVG → PDF** |
| librsvg | 2.61 line, LGPL-2.1 | Good | Drags in cairo, pango, harfbuzz, glib, gdk-pixbuf (~15–20 MB, EST); GObject init | Rejected |
| WKWebView offscreen | system | Full browser fidelity incl. CSS fonts and web fonts | Main-actor, async, ~100–300 ms start-up (EST), must block network (content rules) | Fallback for SVGs that resvg rejects, and for SVG → PDF if svg2pdf fails |

### 3.2 Design

One Rust static library `libzivlet_rs.a` (target `aarch64-apple-darwin`, `panic = "abort"`, `lto = true`, `opt-level = "s"`) exporting a tiny C ABI:

```c
// zivlet_rs.h
int32_t sat_svg_render_rgba(const uint8_t *svg, size_t len, float scale, uint32_t max_px,
                            uint8_t **out_rgba, uint32_t *w, uint32_t *h);   // resvg + tiny-skia
int32_t sat_svg_to_pdf(const uint8_t *svg, size_t len, uint8_t **out_pdf, size_t *out_len); // svg2pdf
int32_t sat_png_optimize(const uint8_t *png, size_t len, uint8_t level, uint8_t **out, size_t *out_len); // oxipng
int32_t sat_png_quantize(const uint8_t *rgba, uint32_t w, uint32_t h, uint8_t min_q, uint8_t max_q,
                         uint8_t **out_png, size_t *out_len);               // imagequant
void    sat_free(void *p);
```

- `usvg::Options`: load system fonts once (`fontdb.load_system_fonts()`) into a process-wide immutable `Arc<Database>`; `resources_dir = None`; **disable external file and URL loading** (`image_href_resolver` that only accepts `data:` URIs) — prevents local file disclosure from untrusted SVGs.
- `svgz`: gunzip in Swift (`Compression` framework/zlib) before passing bytes; cap decompressed size at 64 MB.
- Default raster size: intrinsic size × (user scale, default 2×), clamp longest edge to 8192 px.
- Fallback chain: resvg error → `NSImage` → WKWebView. Record which renderer was used in the job report (transparency goal).

Build: `cargo build --release --target aarch64-apple-darwin` in an Xcode "Run Script" or a prebuilt XCFramework committed via release artifacts; pin with `Cargo.lock` and `cargo-deny` licence checks.

---

## 4. PDF

### 4.1 Engines compared

| Engine | Version / licence | Strengths | Weaknesses | Role |
|---|---|---|---|---|
| **PDFKit / Quartz** | system | Merge, split, reorder, rotate, page thumbnails, `PDFPage(image:)`, `CGContext.drawPDFPage` rasterisation (Preview-grade renderer), password open/save (`.ownerPasswordOption`, `.userPasswordOption`), OCR text layer (`.saveTextFromOCROption`, macOS 13+ DOC), Quartz filters | Writing re-serialises through Quartz: may drop tagged structure, invalidate signatures, flatten or lose some forms (spike S-PDF-2). Cannot linearize. `saveImagesAsJPEG` / `optimizeImagesForScreen` are **no-ops on an unmodified document** (PROBED) | **Primary** |
| **qpdf** | 12.4.2 (2026-09-27), Apache-2.0, C++17 | Lossless structural rewrite: `--object-streams=generate`, `--recompress-flate --compression-level=9`, `--linearize`, `--pages` merge, `--split-pages`, `--decrypt`, AES-256 `--encrypt`, automatic xref repair, `--optimize-images --jpeg-quality=N` (re-encodes non-JPEG images, **no downsampling**), drops old incremental revisions | No rendering, no downsampling | **Bundled**, P1 |
| pdfium (bblanchon/pdfium-binaries) | chromium/8111 (2026-10-19, weekly), BSD-3 (+Apache-2.0 parts); `pdfium-mac-arm64.tgz` 3.5 MB | Chrome's renderer, robust with broken files, page-object editing, per-character text boxes, form flattening (`FPDFPage_Flatten`) | Duplicates PDFKit; C API only; weekly churn | Not in v1. Keep as fallback if S-PDF-1 finds PDFKit rendering failures on a real-world corpus |
| MuPDF | 1.27.x / 1.28 line, **AGPL-3.0** (or commercial) | Best-in-class **true redaction** (`pdf_redact_page` removes text, vectors and image pixels under the box), `pdf_rewrite_images` / `mutool clean` image subsampling + JPEG/J2K/JBIG2 recompression, fast rendering | AGPL. A Ghostscript bug (708567, 1.26.1) reports broken images from `pdf_rewrite_images` with some settings | v2 decision gate for redaction (§4.5) |
| Ghostscript | 10.08.0 (`gs10080`, 2026-09-08), AGPL-3.0 | Strongest general-purpose compressor (`-sDEVICE=pdfwrite -dPDFSETTINGS=/ebook`), PDF/A conversion | Re-distills the whole file (fonts subset, forms lost), slow, ~25–40 MB installed (EST), long CVE history, must run with `-dSAFER` | **Rejected for v1**; revisit only if users need PDF/A |

**Licence check for MuPDF/Ghostscript:** the FSF GPL FAQ says "Each of these licenses [GPLv3 and AGPLv3] explicitly permits linking with code under the other license." So a GPLv3 Zivlet can ship MuPDF. The AGPL §13 network clause only bites on network-served modified versions, which a desktop app is not. The cost is that the combined work carries AGPL terms for the MuPDF part. Launching `mutool` as a separate executable is plain aggregation and avoids even that question.

### 4.2 Operation map

| Operation | Implementation |
|---|---|
| Merge PDFs | `PDFDocument()` + `insert(page.copy(), at:)` from each source, keep outlines of the first doc; if any source is encrypted/signed/has AcroForm → qpdf `--empty --pages a.pdf b.pdf -- out.pdf` (keeps forms and structure better). |
| Split / extract pages | PDFKit per range, or qpdf `--split-pages=n` for very large files (streams, no re-serialisation). |
| Organize (reorder, rotate, delete) | PDFKit (`PDFPage.rotation`, `exchangePage`, `removePage`), UI with `PDFThumbnailView`. |
| Images → PDF | `CGContext(url:mediaBox:)`; for JPEG sources create the `CGImage` with `CGImage(jpegDataProviderSource:…)` so Quartz embeds the **original JPEG bytes** (no generational loss); HEIC/PNG via ImageIO decode. Page size options: image size at 72/150/300 DPI, A4, Letter, with margins. |
| PDF → images | `CGContext.drawPDFPage` into a bitmap at user DPI (default 150, presets 72/150/300, clamp 16 384 px and 200 MP); `Page 001.png` naming in a `"<name> Pages"` folder. Honour `CropBox`, rotation, white background for JPEG. |
| Compress (lossy) | §4.3 |
| Compress (lossless / "Optimize") | qpdf `--object-streams=generate --recompress-flate --compression-level=9 --remove-unreferenced-resources=yes`. Safe for forms and signatures-less files. |
| Linearize ("Fast web view") | qpdf `--linearize`. |
| Repair | qpdf (xref reconstruction is automatic), then re-open in PDFKit to verify. |
| Protect / unlock | qpdf `--encrypt user owner 256 --` / `--decrypt` (needs the password). Never remove protection without the password. |
| Strip metadata | qpdf rewrite **after** ExifTool/PDFKit edits: ExifTool writes PDF edits as **incremental updates**, so the old Info/XMP stay in the file until rewritten. Pipeline: PDFKit/ExifTool clear Info + XMP → qpdf full rewrite (drops prior revisions) → re-read with ExifTool to verify nothing remains. |
| OCR / searchable PDF | Render page → `RecognizeDocumentsRequest` → either PDFKit `.saveTextFromOCROption` (DOC, needs a spike to confirm it embeds Apple's OCR) or draw invisible text (`CGContext.setTextDrawingMode(.invisible)`) at observation boxes on top of the page image. |
| Redact | §4.5 |

### 4.3 PDF compression — PROBED results and design

Test file: 4 pages, each a distinct 3000×2250 Flate-compressed bitmap placed at 540×405 pt = **14 737 KB**.

| Method | Result | Time |
|---|---|---|
| `PDFDocument(url:).write(withOptions: [.saveImagesAsJPEGOption: true])` | 14 737 KB (unchanged) | 0.01 s |
| …`+ .optimizeImagesForScreenOption` | 14 737 KB (unchanged) | 0.01 s |
| Same options after only changing `documentAttributes` | 14 737 KB (unchanged) | — |
| Same options on a **fresh `PDFDocument` with copied pages** | 9 896 KB (JPEG, full res) / **2 313 KB** (+screen: 1080 px) | — |
| System `Reduce File Size.qfilter` (q 0.7, max 2400 px, 144 DPI) | 2 174 KB | 0.69 s |
| **Runtime `QuartzFilter(properties:)` q 0.85, 300 DPI** | 6 780 KB (images 2250 px) | 0.55 s |
| Runtime filter q 0.6, 150 DPI | 2 021 KB (1125 px) | 0.31 s |
| Runtime filter q 0.4, 96 DPI | 860 KB (720 px) | 0.26 s |

Conclusions:
- PDFKit's built-in options only apply when pages are re-serialised and expose **no quality knob**. Do not use them.
- A **runtime Quartz filter** gives two real knobs (JPEG quality and effective DPI, computed from the placed size) and keeps text and vectors as vectors. The dictionary shape matches `/System/Library/Filters/Reduce File Size.qfilter`:

```swift
let props: [String: Any] = [
  "Name": "Zivlet Compress", "FilterType": 1, "Domains": ["Applications": true],
  "FilterData": ["ColorSettings": ["ImageSettings": [
     "ImageCompression": "ImageJPEGCompress", "Compression Quality": quality,      // 0…1
     "ImageScaleSettings": ["ImageResolution": dpi, "ImageScaleInterpolate": true,
                            "ImageSizeMax": maxPx, "ImageSizeMin": 0]]]]]
let filter = QuartzFilter(properties: props)
document.write(to: tmpURL, withOptions: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter!])
```

Presets: **Light** (q 0.85, 220 DPI), **Balanced** (q 0.7, 150 DPI), **Strong** (q 0.5, 110 DPI). **Target size**: binary search over a 2-D ladder (DPI 72–220, q 0.35–0.85), max 6 passes, keep best, then a qpdf lossless pass (object streams + Flate 9; typically a few % more).

Safety:
- Pre-flight with PDFKit/qpdf `--json` inspection: if the file has AcroForm fields, digital signatures, tagged structure (`/StructTreeRoot`), embedded files or JavaScript, show "Compression will flatten/remove: …" and offer **lossless optimize only** (qpdf). Spike S-PDF-2 lists exactly what Quartz drops.
- Never output a bigger file; never output if page count or page boxes differ (verify by re-opening).
- v2 (effort L): our own **qpdf-based image recompressor** — walk image XObjects with `QPDFPageObjectHelper::forEachImage`, decode with `getStreamData(qpdf_dl_all)`, downsample with vImage, re-encode JPEG via ImageIO/jpegli, `replaceStreamData` with `/DCTDecode` and updated `/Width /Height /ColorSpace`, handle `/SMask` separately, skip JBIG2/CCITT/indexed/16-bit/`/Decode` arrays. This leaves forms, tags and structure untouched. It is the "custom image recompression" alternative to Ghostscript, and the reason to bundle libqpdf rather than only the CLI.

### 4.4 qpdf integration

```bash
cmake -S qpdf -B build -G Ninja -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DREQUIRE_CRYPTO_NATIVE=ON -DUSE_IMPLICIT_CRYPTO=OFF \
  -DBUILD_DOC=OFF -DINSTALL_EXAMPLES=OFF -DCMAKE_BUILD_TYPE=Release
```
- Depends on zlib (SDK) and libjpeg (build libjpeg-turbo 3.1.x static, BSD/IJG). Native crypto avoids OpenSSL/GnuTLS.
- Call it through the **`qpdfjob` C API with JSON jobs** (`qpdfjob_run_from_json`), whose keys mirror the CLI. This keeps Swift free of C++ interop for v1; the v2 recompressor uses a small C++ shim.
- Run inside the engine helper process (see the architecture doc) so a crash on a hostile PDF never takes down the wheel.
- Size: libqpdf static ~4–6 MB (EST).

### 4.5 Redaction (images and PDF)

- **Images**: burn-in only (solid fill or heavy pixellate), then **always strip metadata including the EXIF thumbnail** (a stale thumbnail leaks the unredacted image).
- **PDF v1 (no new licence)**: for each page with at least one redaction box: render at 300 DPI (Quartz), burn the boxes, replace the page with the image page; unaffected pages are copied untouched. Optionally re-add an invisible OCR text layer from the **rendered, redacted** bitmap (so redacted words can never be in it). Then qpdf rewrite (drops revisions) + ExifTool metadata clear. Verification: extract text from the output page and assert none of the redacted strings appear.
- **PDF v2 (decision gate)**: MuPDF `pdf_redact_page` with pixel-level image redaction and line-art removal options (`pdf_redact_options`; verify field names against the 1.27/1.28 headers) keeps the page vector and selectable. Requires accepting AGPL for that component (§4.1). Ship as a separate `mutool`-like helper (`zivlet-redact`) built from MuPDF with `-DTOFU -DNO_CJK` style font trimming (size EST 8–15 MB).

---

## 5. Metadata

### 5.1 Native ImageIO — PROBED limits

Writing GPS latitude with `CGImageDestinationCopyImageSource(…, [kCGImageDestinationMetadata: md, kCGImageDestinationMergeMetadata: true])`, then reading it back with `CGImageSourceCopyMetadataAtIndex`:

| Format | Call result | Tag actually present after write | `kCGImageMetadataShouldExcludeGPS` |
|---|---|---|---|
| JPEG | ok | ✓ | ok, but the output had **0** enumerable tags (it removed more than GPS) |
| PNG | ok | ✓ | ok |
| HEIC | ok, file size **unchanged** | **✗ (silent no-op)** | ok, no change |
| PSD | ok | **✗ (silent no-op)** | ok |
| AVIF | **error**: "image type 'public.avif' is not supported for lossless metadata modification at this time" | — | fails |

Also, `kCGImagePropertyTIFFArtist` set through `CGImageMetadataSetValueMatchingImageProperty` did not round-trip on any format. ImageIO is **fine for reading** and for metadata on a **re-encode** (pass the properties dictionary to `CGImageDestinationAddImage`), but it is **not a safe lossless editor or stripper**. iPhone photos are HEIC, so this rules it out as the main path.

### 5.2 exiv2 vs ExifTool

| | exiv2 0.28.9 (2026-08-30) | ExifTool 13.59 (2026-05-27) |
|---|---|---|
| Licence | GPL-2.0-or-later (OK for GPLv3) | Same terms as Perl (Artistic or GPL-1.0+) → usable under GPL |
| Language | C++ library; BMFF support behind `EXIV2_ENABLE_BMFF` with a patent disclaimer | Pure Perl |
| HEIC / AVIF / JXL / CR3 | **read only** (BMFF writing is not implemented in 0.28) | read **and write** |
| WebP, PNG, JPEG, TIFF, DNG | read/write | read/write |
| MP4/MOV/M4A, PDF | no / no | read/write (QuickTime keys/ItemList/UserData; PDF via incremental update) |
| Maker notes, XMP edge cases, C2PA/JUMBF | partial | the reference implementation |
| Cost | in-process, fast | needs a Perl interpreter; ~4.3 MB of library (EST), process start-up |

**Decision: ExifTool** is the authoritative reader/writer/stripper. exiv2 adds nothing we need that ExifTool cannot do, and fails on the most common input (HEIC).

### 5.3 Perl availability

- **PROBED**: macOS 27.0 still ships `/usr/bin/perl` → perl **5.34.1** (`/System/Library/Perl/5.34`), plus `/usr/bin/ruby` and `/usr/bin/python3` (CLT shim).
- Apple deprecated bundled scripting runtimes in the Catalina-era release notes (2019): future macOS versions "won't include scripting language runtimes by default". Python 2 was actually removed in macOS 12.3, so the threat is real. Perl 5.34 is also upstream-EOL.
- **Decision: bundle a trimmed relocatable Perl** and use it by default; fall back to `/usr/bin/perl` only if the bundled one fails its self-test. Options:
  - Build from perl.org source 5.42.x: `./Configure -des -Dprefix=/ -Duserelocatableinc -Dman1dir=none -Dman3dir=none -Uusethreads -Dcc=clang -Accflags='-arch arm64 -mmacosx-version-min=26.0'`, then copy only the modules ExifTool loads (record with `perl -MDevel::Trace` / `%INC` dump over our metadata test corpus). EST 3–6 MB.
  - Or take `skaji/relocatable-perl` 5.44.0.0 `perl-darwin-arm64.tar.xz` (11.2 MB compressed) and prune. Its licence field is unasserted on GitHub, so building ourselves is cleaner.
  - Sign the `perl` binary with our Developer ID and hardened runtime (it loads no external dylibs except libSystem).
- Process model: one long-lived `exiftool -stay_open True -@ -` process per engine helper, commands separated by `-execute<N>`, JSON output (`-j -G1 -a -s -n -struct`), so Perl start-up is paid once. Restart after 500 jobs or any timeout (10 s default, per command).
- Environment: `PATH=/usr/bin:/bin`, `PERL5LIB` unset except our lib, `LC_ALL=C.UTF-8`, `-config ''` (no user config), `-charset filename=utf8`, a private `TMPDIR`.

### 5.4 Safety contract (Zivlet's own design)

1. **Read** → JSON model (group, tag, value, writable, removable) for the editor UI.
2. **Plan** → explicit change list (set / delete / delete-all-except-{ICC, Orientation, colour}).
3. **Write** to a temp file beside the original (`-o tmp`), never `-overwrite_original` in place.
4. **Verify** (fail closed): re-read; every planned change applied; nothing unplanned changed; **image data hash unchanged** (`exiftool -ImageDataHash` with `-api ImageHashType=SHA256`, introduced in the 12.5x series; confirm the exact option names against 13.59 docs in S-M1); for "Remove all": no GPS, no maker notes, no XMP/IPTC, no thumbnail, no C2PA left (unless the user keeps C2PA).
5. Publish atomically (`replaceItemAt`/rename), then reveal.

Audio/video metadata: ExifTool for MP4/MOV/M4A/HEIF-video edits; ffmpeg `-map_metadata -1 -map_chapters -1 -c copy` for MKV/WebM/OGG strips (video engine doc). PDF: §4.2 strip pipeline.

---

## 6. Archives

### 6.1 System tools — PROBED

- `/usr/bin/tar` is **bsdtar 3.5.3 – libarchive 3.7.4** (zlib 1.2.12, liblzma 5.4.3, bz2 1.0.8; no zstd/lz4 listed).
- Using libarchive's own uuencoded test fixtures: lists and extracts **RAR4** (incl. symlinks), **RAR5 solid** (7 files OK); **RAR5 encrypted** lists entries but cannot extract (libarchive does not decrypt RAR).
- Creates 7z (`--format 7zip`, `--options 7zip:compression=lzma2`) and AES ZIP (`zip:encryption=aes256`, asks for a passphrase).
- The SDK ships `libarchive.tbd` but **no `archive.h`**: linking the system copy means vendoring headers for an undocumented version. Do not depend on it.

### 6.2 Decision: bundled libarchive 3.8.10 (2026-10-14), BSD-2

| Format | Read | Write |
|---|---|---|
| ZIP (incl. ZIP64, UTF-8 names, AES/ZipCrypto) | ✓ (decrypt with passphrase) | ✓ (AES-256 with passphrase) |
| TAR (ustar/pax/GNU) + gzip/bzip2/xz/lzma/zstd/lz4 | ✓ | ✓ |
| 7-Zip (LZMA/LZMA2/PPMd/BZip2/Deflate, BCJ/BCJ2 filters) | ✓ (no AES) | ✓ (no AES) |
| RAR 1.5–4.x, RAR5 (solid, multi-volume) | ✓ (no encryption) | ✗ (no one may legally reimplement RAR compression from unRAR; we do not ship a RAR writer) |
| ISO9660/Joliet/RockRidge, CAB, LHA/LZH, XAR, CPIO, AR | ✓ | ISO/XAR/CPIO ✓ |

Build (static, arm64, macOS 26):
```bash
# deps: xz 5.8.4 (0BSD), zstd 1.5.7 (BSD), lz4 1.10 (BSD-2); zlib + bzip2 from the SDK
cmake -S libarchive -B build -G Ninja -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DBUILD_SHARED_LIBS=OFF -DENABLE_TAR=OFF -DENABLE_CPIO=OFF -DENABLE_CAT=OFF -DENABLE_UNZIP=OFF \
  -DENABLE_TEST=OFF -DENABLE_OPENSSL=OFF -DENABLE_MBEDTLS=OFF -DENABLE_NETTLE=OFF \
  -DENABLE_LZMA=ON -DENABLE_ZSTD=ON -DENABLE_LZ4=ON -DENABLE_BZip2=ON -DENABLE_ZLIB=ON \
  -DENABLE_ICONV=ON -DENABLE_ACL=ON -DENABLE_XATTR=ON -DENABLE_LIBXML2=OFF -DENABLE_EXPAT=OFF
```
(ZIP AES uses CommonCrypto on macOS, so no OpenSSL. XAR needs libxml2/expat; leave XAR read off unless needed.)

### 6.3 Extraction hardening (mandatory)

- `archive_write_disk_set_options(ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM | ARCHIVE_EXTRACT_SECURE_NODOTDOT | ARCHIVE_EXTRACT_SECURE_SYMLINKS | ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS | ARCHIVE_EXTRACT_UNLINK)`; never `ARCHIVE_EXTRACT_OWNER`, strip setuid/setgid bits.
- Extract into a hidden staging folder beside the archive, then rename to `"<name>"` (or `"<name> 2"`), so partial output never appears.
- Bomb limits: total uncompressed ≤ min(20× archive size + 1 GB, free disk − 2 GB), ≤ 100 000 entries, ratio check per entry; nested archives are not auto-extracted.
- Normalise names (NFC → NFD for APFS display), reject entries containing NUL; apply `com.apple.quarantine` from the archive to extracted files (copy the xattr) so Gatekeeper still checks downloaded executables.
- Passwords: prompt in the tool window; never log.

### 6.4 Creation

- **ZIP (default)**: libarchive zip writer, Deflate level 6, UTF-8 flag, skip `.DS_Store`/`__MACOSX`/`._*` by default; folder drop → `Folder.zip`.
- **"Mac-faithful ZIP"** (Settings toggle, for bundles with resource forks/xattrs): `/usr/bin/ditto -c -k --sequesterRsrc --keepParent src out.zip` (system tool, stable since 10.x).
- **7z**: LZMA2 level 5 via libarchive (no encryption). **Password ZIP**: AES-256.
- **TAR / tar.gz / tar.xz / tar.zst**: libarchive.
- **RAR output: dropped.** A store-only RAR writer would add no compression and reimplement a proprietary format; 7z/ZIP replace it. Show RAR as input-only in the matrix.

### 6.5 Encrypted RAR / 7z

Deferred. If demand appears: bundle **7-Zip 26.04** (`7z2604-src.tar.xz`, 1.56 MB source; macOS binary archive 1.86 MB) built as `7zz` with RAR codecs disabled (the RAR decoder carries the unRAR restriction, which is GPL-incompatible), giving 7z-AES extraction. Encrypted RAR remains unsupported ("Use The Unarchiver/Keka for encrypted RAR").

---

## 7. Subtitles — own Swift module `ZivletSubtitles`

Why own code: the formats are small, and correctness lives in edge cases we must control (encodings, malformed timestamps, styling). `dagronf/SwiftSubtitles` (MIT, 98★, last push 2025-08) is a reasonable reference for format coverage but not a dependency we need.

Model: `struct Cue: Sendable, Hashable { let id: String?; let start: Duration; let end: Duration; let text: AttributedString / [Span]; let settings: VTTCueSettings? }`, `struct SubtitleDocument { let cues: [Cue]; let header: VTTHeader?; let styles: [String] }` (immutable; transforms return new documents).

Parsing rules:
- **Encoding**: BOM sniff (UTF-8/16/32); else strict UTF-8; else `NSString.stringEncoding(for:encodingOptions:convertedString:usedLossyConversion:)` with suggested Windows-1252, ISO-8859-x, Shift-JIS, GB18030, EUC-KR; record the detected encoding in the report. Always write UTF-8 (VTT requires it).
- **SRT**: blank-line separated blocks, tolerant of missing indices, CRLF/CR, `,` or `.` milliseconds, 1–3 digit fraction, `X1:` coordinates ignored, tags `<b><i><u><font color>`, `{\an8}`-style ASS overrides stripped or mapped to VTT `line:`.
- **VTT**: `WEBVTT` header (+ optional text), `NOTE`, `STYLE`, `REGION` blocks, timestamps with optional hours, cue settings (`vertical`, `line`, `position`, `size`, `align`), `<c.class>`, `<v Speaker>`, `<ruby>`, timestamp tags `<00:00:01.000>` (dropped when writing SRT).
- Validation: end ≥ start (fix by clamping and warn), monotonic order (sort, stable), overlapping cues allowed.
- Extras (cheap, high value): shift all times ±N ms, FPS conversion (23.976 ↔ 25), strip formatting, merge cues, and **later** ASS/SSA/SBV read.
- Embedding/extracting subtitles in video (`mov_text`, WebVTT in MKV) belongs to the ffmpeg engine.
- Tests: golden files per edge case, plus fuzzing with Swift `-sanitize=fuzzer` on the parser.

---

## 8. Vision on macOS 26/27

All Swift-native requests below exist in `MacOSX27.0.sdk` Vision swiftinterface (DOC); availability as annotated.

### 8.1 PROBED timings (1600×1000 synthetic image, macOS 27, M-series)

| Request | Result | Time |
|---|---|---|
| `DetectBarcodesRequest` (macOS 15) | QR payload `https://example.org/zivlet` | 2.63 s **first call** (model load) |
| `RecognizeTextRequest` `.accurate` (macOS 15) | 6 lines, correct | **57.8 s on first ever call** (one-time model preparation), fast afterwards |
| `RecognizeDocumentsRequest` (macOS 26) | paragraphs correct; **`detectedData` found the e-mail address and phone number** as typed `DataDetector.Match` values | 0.25 s (warm) |
| `GenerateForegroundInstanceMaskRequest` (macOS 15) | 1 instance (the subject disc) | 0.50 s |
| `DetectFaceRectanglesRequest` | 0 (no faces in the image) | fast |

Implication: **warm up** Vision models in the background after first launch (run each request once on a 64×64 image at low QoS), and show a determinate "Preparing text recognition…" state if a user triggers OCR before warm-up completes. Re-measure the cold start on macOS 26 (S-V1).

### 8.2 Background removal

```swift
let request = GenerateForegroundInstanceMaskRequest()
let handler = ImageRequestHandler(cgImage, orientation: orientation)
guard let obs = try await handler.perform(request) else { throw .noSubject }
let masked = try obs.generateMaskedImage(for: obs.allInstances, imageFrom: handler, croppedToInstancesExtent: crop) // CVPixelBuffer w/ alpha
// or: let mask = try obs.generateScaledMask(for: obs.allInstances, scaledToImageFrom: handler) → CIBlendWithMask
```
- Instance picking in the tool window: `obs.instanceAtPoint(NormalizedPoint)` to toggle subjects.
- **macOS 27 bonus**: `GenerateIterativeSegmentationRequest(seedPoint:)`, `(seedBox:)`, `(seedScribbleBuffer:)` for "tap/brush to select" refinement; it is a `DownloadableAssetsRequest` (`assetStatus`, `downloadAssets(progress:)`), so handle "not ready" and download state. Gate with `if #available(macOS 27, *)`.
- Output: PNG/HEIC/WebP/AVIF with alpha (JPEG target → ask for a background colour, feeding "Add BG"). Edge refinement: 1 px feather via `CIMorphologyMinimum` + `CIGaussianBlur` on the mask (optional).

### 8.3 Redaction detection

- Faces: `DetectFaceRectanglesRequest` (expand boxes 15%).
- Text: `RecognizeDocumentsRequest` → paragraphs/lines with boxes; **PII auto-select** from `Container.Text.detectedData` (emails, phone numbers, postal addresses, links, dates, flight numbers, money) plus our own regexes for IBAN/credit cards (Luhn check) and national IDs. Word-level boxes from `RecognizeTextRequest` candidates `boundingBox(for: range)` when a match is sub-line.
- Barcodes/QR (they can encode PII): `DetectBarcodesRequest`.
- Humans/licence plates: `DetectHumanRectanglesRequest`; plates via `DetectRectanglesRequest` + text heuristics (P2).
- Video redaction: detect on keyframes, track with `TrackObjectRequest`, render with `AVVideoComposition` Core Image handler (video engine doc).

### 8.4 QR / barcode reading

`DetectBarcodesRequest` with `symbologies` = `.qr, .microQR, .aztec, .dataMatrix, .pdf417, .ean8, .ean13, .upce, .code39, .code93, .code128, .itf14, .gs1DataBar, .codabar, .msiPlessey`. For PDFs render each page at 200 DPI. Result card shows the payload with Copy, an explicit Open button only for `http(s)` (full URL shown, never auto-open), Wi-Fi/vCard parsing. `RecognizeDocumentsRequest.barcodeDetectionOptions.enabled = true` returns barcodes inside documents in the same pass (PROBED: off by default).

### 8.5 OCR for PDF → DOCX/MD/searchable PDF

`RecognizeDocumentsRequest` (macOS 26 is our floor, so no `VNRecognizeTextRequest` fallback needed): `textRecognitionOptions.recognitionLanguages`, `automaticallyDetectLanguage = true`, `useLanguageCorrection = true`, `customWords` from the file name/title. Map `tables` (rows/columns of cells with `rowRange`/`columnRange`) → DOCX tables / Markdown pipe tables; `lists` → bullet/number lists; paragraphs → paragraphs with reading order. Only OCR pages without a usable text layer (PDFKit `page.string` empty or < 20 chars per page area).

---

## 9. Cross-cutting engine rules

1. **One engine helper process** (non-sandboxed XPC service or helper tool) hosts all C/C++/Rust parsers (libwebp, libjxl, libarchive, qpdf, resvg) and the ExifTool process, so a crash on a hostile file is contained. The wheel/UI process only talks Codable job messages.
2. **Immutable job values** (`struct ImageJob: Sendable`) in, `JobResult` out; engines are stateless actors except the warm ExifTool session and Vision warm-up flags.
3. **Write beside original via staging**: temp name in the same directory → verify → atomic rename → reveal. Never overwrite the source.
4. **Fail closed with precise messages** (unsupported pair, password needed, encrypted RAR unsupported, would be bigger, verification failed).
5. **Capability probe at launch** (ImageIO UTIs, Vision availability, bundled library versions), cached per OS build, drives the wheel and the Settings matrix so we never advertise a pair that cannot run (for example, a WebM output that is not actually playable).
6. **Fixture corpus in CI** on macOS 26.x and the newest beta: every advertised pair plus metadata, archive-hostility (zip-slip, symlink, bomb) and PDF (forms, signed, encrypted, broken xref) fixtures.

---

## 10. Size and licence budget

| Component | Licence | GPLv3-compatible | Size in bundle |
|---|---|---|---|
| libwebp 1.6.0 (+mux, sharpyuv) | BSD-3 | ✓ | ~0.7 MB (EST) |
| libjxl 0.12.0 (+highway, brotli, jpegli) — P1 | BSD-3 + patent grant | ✓ | ~3–5 MB (EST) |
| Rust lib: resvg 0.48.1, svg2pdf 0.13, oxipng 10.2, imagequant | Apache-2.0/MIT; imagequant GPL-3.0+ | ✓ | ~4–6 MB (EST; resvg CLI alone < 5 MB) |
| qpdf 12.4.2 + libjpeg-turbo | Apache-2.0 (GPLv3-compatible), BSD/IJG | ✓ | ~4–6 MB (EST) |
| libarchive 3.8.10 + xz 5.8.4 + zstd 1.5.7 + lz4 | BSD-2 / 0BSD / BSD | ✓ | ~1.5–2 MB (EST) |
| ExifTool 13.59 (lib only, no `Lang/`) | Artistic / GPL-1.0+ | ✓ | ~4.3 MB (EST) |
| Trimmed relocatable Perl 5.42.x | Artistic / GPL-1.0+ | ✓ | ~3–6 MB (EST) |
| **Total v1** | | | **~18–30 MB** (EST), plus libjxl if P1 lands |
| Gated: MuPDF helper | AGPL-3.0 | ✓ (FSF FAQ) | 8–15 MB (EST) |
| Gated: 7zz without RAR | LGPL-2.1 + BSD-3 | ✓ | ~2–3 MB (EST) |
| Rejected: Ghostscript | AGPL-3.0 | ✓ | 25–40 MB (EST) |
| Rejected: unRAR | unRAR licence | **✗** | — |

Every bundled binary/dylib is signed with the hardened runtime; `perl` needs no extra entitlements. Licence texts go into `Acknowledgements` generated from SPDX data (`cargo-about` for Rust, a manifest for C libs).

---

## 11. Spikes (do before committing)

| ID | Question | Pass criterion |
|---|---|---|
| S-0 | Re-run every PROBED table on macOS 26.0 and 26.x (VM) | Same ImageIO write UTIs (esp. `public.avif`), Vision requests available |
| S-3 | HDR gain-map round-trip HEIC → HEIC/AVIF/JPEG with ISO HDR options | Gain map present in output (ExifTool `-MPF:all`/`-XMP-hdrgm:all`) |
| S-PDF-1 | PDFKit render vs pdfium on a 300-file real-world corpus (scans, forms, broken xref, CJK) | < 1% visual failures; else adopt pdfium for rasterising |
| S-PDF-2 | What the Quartz-filter rewrite loses: forms, signatures, tags, links, outlines, attachments, layers | Documented list driving the pre-flight warning |
| S-PDF-3 | `.saveTextFromOCROption` actually embeds a text layer on macOS 26 | Text extractable after save; else draw invisible text ourselves |
| S-M1 | Trimmed Perl: module list for ExifTool over the metadata corpus; size; Gatekeeper/notarization of the bundled `perl` | All ExifTool tests pass with bundled Perl only; < 6 MB |
| S-M2 | ExifTool `-stay_open` throughput (100 HEIC reads, 100 strips) | ≥ 20 files/s read, no leaks over 1 000 jobs |
| S-A1 | libarchive hostile corpus (zip-slip, absolute paths, symlink escape, 42.zip, RAR5 multi-volume) | All refused or contained; RAR5 multi-volume extracts when all parts dropped |
| S-S1 | resvg vs WKWebView diff on 500 real-world SVGs (icons, illustrations, charts with CSS text) | ≥ 97% visually equal (DSSIM < 0.01); failures route to WKWebView |
| S-V1 | Vision cold-start on macOS 26 and warm-up effectiveness | First user OCR < 3 s after warm-up |
| S-C1 | Compression quality A/B: ImageIO JPEG vs jpegli, ImageIO AVIF vs libavif, at equal SSIMULACRA2 | Decide P2 adoption of jpegli/libavif |

---

## 12. RECOMMENDATION

**Choice (per capability)**
1. **Raster images:** ImageIO + Core Image as the core (decode 62 formats incl. WebP, JXL, PSD, RAW; encode JPEG/PNG/HEIC/AVIF/TIFF/BMP/GIF/ICO/ICNS/PSD). Add **libwebp 1.6.0** linked in-process for WebP still/animated/target-size with metadata. P1: **libjxl 0.12** (JXL encode), **libimagequant + oxipng** (PNG compression). No libvips.
2. **SVG:** **resvg 0.48.1** for raster output and **svg2pdf 0.13** for vector PDF, shipped in one Rust static library with external resource loading disabled. Fallbacks: `NSImage` (CoreSVG), then offline WKWebView.
3. **PDF:** **PDFKit/Quartz** for merge/split/organize/images↔PDF/rasterise; **runtime Quartz filters** for lossy compression and target size (PROBED controllable); **qpdf 12.4.2** (libqpdf via `qpdfjob` JSON) for lossless optimize, linearize, repair, AES-256, and scrubbing incremental revisions. Redaction v1 = rasterise affected pages; MuPDF true redaction is a v2 decision gate. No Ghostscript, no pdfium in v1.
4. **Metadata:** **ExifTool 13.59** as the only writer/stripper, in a persistent `-stay_open` process with a fail-closed read → plan → write → verify contract (own code). Run it on a **bundled trimmed Perl**, falling back to `/usr/bin/perl` (still 5.34.1 on macOS 27). ImageIO/AVFoundation/PDFKit only for fast read-only display.
5. **Archives:** bundled **libarchive 3.8.10** (+xz/zstd/lz4) for all extraction (incl. RAR4/RAR5) and creation (ZIP, AES-ZIP, 7z, tar.*), with strict extraction hardening. `ditto` only for the "Mac-faithful ZIP" option. No RAR creation. Encrypted RAR unsupported; 7z-AES via RAR-less `7zz` only if requested.
6. **Subtitles:** own Swift `ZivletSubtitles` (SRT/VTT now, ASS/SSA/SBV read later) with encoding detection and fuzz tests.
7. **Vision:** `GenerateForegroundInstanceMaskRequest` (background removal), `DetectFaceRectanglesRequest` + `RecognizeDocumentsRequest` with `detectedData` (PII auto-redaction), `DetectBarcodesRequest` (QR), `RecognizeDocumentsRequest` (OCR with tables/lists). macOS 27 adds `GenerateIterativeSegmentationRequest` behind `#available`. Warm models up in the background.

**Rationale.** Apple frameworks on macOS 26+ already cover almost all decoding and most encoding with hardware acceleration and correct colour management. So we only add small, focused, permissively licensed libraries where we PROBED a real gap: WebP/JXL encode, a spec-complete SVG renderer, lossless PDF structure work, metadata writing for HEIC/AVIF, and in-process archive handling. This targets better results than the common shortcuts in §1 on correctness (animated WebP, working AVIF, no temp-PNG round-trips, true metadata scrubbing of PDFs, archive safety), speed (in-process, persistent ExifTool, no WKWebView for SVG) and robustness (no reliance on a deprecated system Perl), at an estimated +18–30 MB.

**Risks**
- Quartz-filter PDF compression may flatten or drop forms, signatures and tagged structure (S-PDF-2). Mitigation: pre-flight detection, lossless-only mode, v2 qpdf-based image recompressor.
- PDFKit write options and `NSImage` SVG behaviour are undocumented or private and can change per OS. Mitigation: capability probes + fixture CI on each beta; resvg is primary for SVG.
- ImageIO metadata APIs report success while silently not writing (HEIC/PSD, PROBED). Mitigation: ExifTool only, and verify every write.
- A bundled Perl adds a signed interpreter to maintain (security updates). Mitigation: pin, track perl5 security releases, fallback to `/usr/bin/perl`.
- Vision first-run model preparation took ~58 s for text recognition (PROBED, macOS 27). Mitigation: background warm-up, progress UI.
- Hostile inputs to C/C++ parsers (libarchive, qpdf, libwebp, ExifTool). Mitigation: helper-process isolation, size/ratio limits, fuzzing in CI.
- AGPL (MuPDF) adoption for true redaction is a project-level licence decision; unRAR must never be bundled.
- Sizes marked EST may be off by ±50% until the spikes measure them.

**Fallback**
- WebP: if linking libwebp is blocked for any reason, use the bundled LGPL ffmpeg's `libwebp` encoder (which the video track builds anyway).
- SVG: resvg → `NSImage` → WKWebView, chosen per file automatically.
- PDF compression: if Quartz filters break on a file, run qpdf `--optimize-images --jpeg-quality=N` (no downsampling) + object streams; if that's still not enough, the qpdf-based recompressor (v2).
- PDF rendering failures in PDFKit: adopt pdfium (BSD, 3.5 MB arm64 build) for rasterisation only.
- Metadata: if the bundled Perl fails self-test, use `/usr/bin/perl`; if neither works, disable editing and offer re-encode-based stripping through ImageIO (lossy for JPEG, so warn).
- Archives: if a format is unreadable by libarchive (encrypted RAR), show an explicit message recommending a dedicated unarchiver.
- Redaction: rasterised pages (v1) remain the default even if MuPDF is adopted later, as the zero-dependency safe path.
