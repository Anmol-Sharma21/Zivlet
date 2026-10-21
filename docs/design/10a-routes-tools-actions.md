# 10a — Zivlet Technical Strategy: routes, tools and actions (§4–§6)

Part of [10-tech-strategy](10-tech-strategy.md), split out to keep each file under 800 lines. Section numbers are unchanged, so a reference such as "10 §4" points to the matching section below. Bare section references to sections not in this file point to the parent document, whose header defines the evidence tags, `[challenge]` notes and **[OWNER]** markers used here.

---

## 4. Route-by-route engine table (all 275 pairs)

### 4.1 Engine codes

| Code | Meaning |
|---|---|
| **IIO** | ImageIO decode → (Core Image colour, tone mapping, orientation) → ImageIO encode. Feature-gated by the launch probe of `CGImageDestinationCopyTypeIdentifiers()`. |
| **WEBP** | libwebp in the worker (`WebPEncode`; `WebPAnimEncoder` for multi-frame sources; `WebPMux` writes ICC/EXIF/XMP) |
| **QZ** | Quartz `CGContext(url:mediaBox:)` / PDFKit. JPEG sources are embedded byte-for-byte via `CGImage(jpegDataProviderSource:)`. |
| **QZR** | Quartz rasterise PDF page → IIO encode (300 DPI default; multi-page output goes to a `<base> Pages/Page 001.<ext>` folder) |
| **RSVG / S2P** | resvg render (2× intrinsic, longest edge ≤ 8192) / krilla-svg vector PDF (replaces svg2pdf, see §3 challenge), both from `libzivlet_rs` |
| **FF[enc]** | ffmpeg child process with the named encoder; settings in §4.4–4.6 |
| **FUS** | PDFKit text layer + Vision `RecognizeDocumentsRequest` fusion → SDoc (12 §4.9) |
| **MAM** | mammoth (in zivlet-js) → HTML → SwiftSoup → SDoc |
| **CF-R / CF-W** | cupertino-files read (→ SDoc) / write (SDoc →) in zivlet-js |
| **NSAS** | NSAttributedString read (RTF/RTFD/clipping plist) → SDoc |
| **MD-R** | swift-markdown → SDoc (GFM tables, task lists) |
| **TXT-R** | encoding detection → paragraphs split on blank lines → SDoc |
| **EPUB-R** | ZIPFoundation + OPF spine + SwiftSoup → SDoc (DRM or obfuscated fonts are refused) |
| **W:docx / W:pages / W:md / W:txt / W:html / W:epub / W:rtf** | SDoc writers (own WordprocessingML; CF-W; swift-markdown formatter; EPUB 3 passing EPUBCheck; RTF via NSAttributedString) |
| **WKP** | SDoc → HTML + print CSS → RenderHost `WKWebView.printOperation` → PDF, with page numbers stamped by PDFKit |
| **WKP→R** | WKP, then QZR (one page → a file beside the original; several → a folder) |
| **DXP** | docx-preview in RenderHost (break hints honoured) → one `printOperation` (WebKit paginates the rest) |
| **PPTR** | pptx-renderer in RenderHost. Slide-size `@page`, one vector PDF. PNG/JPG come from a 2× `takeSnapshot` per slide. |
| **SJS** | SheetJS CE in zivlet-js (read any → workbook JSON; write xlsx/ods/csv/tsv) |
| **SJS→WKP** | workbook → styled HTML (gridlines, SSF number formats, merges, column widths, repeated header row, auto-landscape) → WKP |
| **LA** | libarchive streaming re-pack (read entries → write entries), with the §8.9 limits applied |
| **SUB** | ZivletSubtitles parse → immutable document → writer |
| **LO** | Tier 2a LibreOffice batch `soffice --headless --convert-to …` (only if installed or downloaded) |
| **iW** | Tier 2b Pages/Keynote/Numbers export via Apple Events (opt-in) |

Router policy for document routes (12 §6.2). The **Document fidelity** setting picks the engine:
- **Automatic** (default **[OWNER]**): use LO or iW for layout routes only when they are already present; otherwise Tier 1.
- **Fast**: Tier 1 only.
- **Best fidelity**: prefer LO or iW and prompt to download.

Every result records the engine used and any font substitutions.

### 4.2 Raster images: 49 pairs

Decode is always IIO (JPEG, PNG, WebP incl. animated, HEIC, TIFF incl. multi-page, AVIF, BMP).

| Input | → jpg | → png | → webp | → heic | → tiff | → avif | → bmp | → pdf | n |
|---|---|---|---|---|---|---|---|---|---|
| jpg | — | IIO | WEBP | IIO | IIO | IIO¹ | IIO | QZ (JPEG bytes embedded) | 7 |
| png | IIO² | — | WEBP | IIO | IIO | IIO¹ | IIO | QZ | 7 |
| webp | IIO² | IIO (APNG if animated) | — | IIO (HEICS if animated) | IIO | IIO¹ | IIO | QZ (first frame of an animation, with a note) | 7 |
| heic | IIO (gain map kept, I-HDR) | IIO | WEBP | — | IIO | IIO¹ | IIO | QZ | 7 |
| tiff | IIO | IIO | WEBP | IIO | — | IIO¹ | IIO | QZ (**multi-page TIFF → multi-page PDF**) | 7 |
| avif | IIO | IIO | WEBP | IIO | IIO | — | IIO | QZ | 7 |
| bmp | IIO | IIO | WEBP | IIO | IIO | IIO¹ | — | QZ | 7 |

¹ AVIF encode via ImageIO is PROBED writable on macOS 27 (335 KB in 0.29 s for 12 MP). If spike G-0/M-7 finds it unwritable on 26.x, the fallback is `ffmpeg -frames:v 1 -c:v libsvtav1 -svtav1-params avif=1 -pix_fmt yuv420p` (spike M-5).
² Alpha going to JPEG is flattened onto white (setting: background colour), and the result card notes it.

> [challenge] The footnote-1 AVIF fallback is weaker than ImageIO and should be labelled as such. `-svtav1-params avif=1` exists in SVT-AV1 4.2 (`Docs/Parameters.md`: "still-picture coding optimizations"), so the command is valid. However, with `-pix_fmt yuv420p` it **drops alpha** and chroma resolution, and the ffmpeg path does not carry ICC, EXIF or XMP. If G-0 finds AVIF unwritable on 26.x, use `-svtav1-params avif=1:tune=3` (IQ tune for stills) and `yuv444p` for graphics. Show "transparency/colour profile not preserved" on the card, or hide AVIF output for alpha sources on that OS. The proper fix is libavif (BSD-2-Clause) linked to its own encoder, at about +3 MB. That is gated on G-0 failing.

Rules for every image pair (13 §2.1):
- Keep the source ICC profile (Display P3) unless the format preset says "Web (sRGB)".
- Apply EXIF orientation once.
- Keep 16-bit where the target allows it.
- Carry animation into GIF, WebP, APNG or HEICS; otherwise warn "Animation flattened to first frame".
- Carry EXIF/XMP through re-encode via the properties dictionary.
- Tone-map HDR to 8-bit targets with `CIToneMapHeadroom`.
- Never output a lossless WebP that is larger than the source as a silent fallback.

### 4.3 SVG: 8 pairs (input only)

| Input | jpg | png | webp | heic | tiff | avif | bmp | pdf |
|---|---|---|---|---|---|---|---|---|
| svg (`.svgz` gunzipped in Swift, ≤ 64 MB) | RSVG→IIO | RSVG→IIO | RSVG→WEBP | RSVG→IIO | RSVG→IIO | RSVG→IIO | RSVG→IIO | **S2P** (vector, real text) |

If resvg fails, the fallback order is `NSImage` (CoreSVG; ignores the CSS `font` shorthand, PROBED), then an offline WKWebView render (`createPDF` for PDF). The renderer used goes into the result report. Spike I-S1 is the 500-SVG diff.

### 4.4 Audio: 56 pairs (ffmpeg only)

Every one of the 8 inputs (mp3, m4a, wav, flac, ogg, opus, aiff, wma) goes to each of the other 7 outputs: 8 × 7 = **56**. ffmpeg decodes every input natively, including WMA (`wmav2`), Opus and Vorbis. The output column decides the encoder:

| Output | Muxer / encoder | Default | Key rules (11 §10.1) |
|---|---|---|---|
| → mp3 | `mp3` / `libmp3lame` | VBR V2 (`-q:a 2`) | ≤ 48 kHz, > 2 ch → stereo. ID3v2.3 with Xing header. Cover art carried as APIC. |
| → m4a | `ipod` / `aac_at` | 192 kbps | ALAC (`alac_at`) as the "Lossless" option. Cover art and iTunes atoms. `+faststart`. |
| → wav | `wav` / `pcm_s16le`/`s24le`/`s32le`/`f32le` | match source depth | `-rf64 auto` (no 4 GB limit) |
| → flac | `flac` / `flac -compression_level 8` | — | 24-bit kept. Cover art as a PICTURE block. |
| → ogg | `ogg` / **`libvorbis` (forced)** | `-q:a 6` | The ogg muxer otherwise defaults to FLAC (VERIFIED-LOCAL). *[challenge: that default is build-dependent. It is FLAC only because the Homebrew 8.1.2 build lacks libvorbis; with libvorbis linked the default is Vorbis. Keep forcing `-c:a libvorbis`, and never fall back to the experimental native `vorbis` encoder.]* Cover art via a `METADATA_BLOCK_PICTURE` tag that we write. |
| → opus | `opus` / `libopus` | 128 kbps VBR, 48 kHz | > 2 ch → `-mapping_family 1`. Cover art via `METADATA_BLOCK_PICTURE`. |
| → aiff | `aiff` / `pcm_s16be`/`s24be`/`s32be` | match source depth | ID3 tags (cover art: spike M-6) |
| → wma | `asf` / `wmav2` | 192 kbps | ≤ 2 ch, ≤ 48 kHz. Cover art dropped (noted). |

Pairs, explicitly:
- mp3 → m4a, wav, flac, ogg, opus, aiff, wma
- m4a → mp3, wav, flac, ogg, opus, aiff, wma
- wav → mp3, m4a, flac, ogg, opus, aiff, wma
- flac → mp3, m4a, wav, ogg, opus, aiff, wma
- ogg → mp3, m4a, wav, flac, opus, aiff, wma
- opus → mp3, m4a, wav, flac, ogg, aiff, wma
- aiff → mp3, m4a, wav, flac, ogg, opus, wma
- wma → mp3, m4a, wav, flac, ogg, opus, aiff

All use FF with the encoder from the table. Lane: `audio`. Measured 0.08–0.09 s per 10 s of audio.

### 4.5 Video: 42 pairs (ffmpeg only)

| Output | Video (re-encode default) | Audio (re-encode default) | Streams copied when the codec fits |
|---|---|---|---|
| → mp4 | `h264_videotoolbox -q:v 60 -tag:v avc1`. 10-bit or HDR sources → `hevc_videotoolbox` Main10 `-tag:v hvc1`. | `aac_at 192k` | v {h264, hevc, av1, mpeg4}; a {aac, alac, mp3, ac3, eac3}. Text subtitles → `mov_text`. `+faststart`. |
| → mov | same as mp4. ProRes 422 option (`prores_videotoolbox`). Alpha sources → HEVC-alpha. | `aac_at 192k` (PCM with ProRes) | v {h264, hevc, prores, mjpeg, mpeg4}; a {aac, alac, pcm, mp3} |
| → mkv | VT H.264 only if a stream can't be copied (rare) | AAC only if needed | almost everything. `-map 0 -c copy` keeps subtitles, attachments and chapters (measured about 40 ms). |
| → webm | **`libvpx-vp9 -crf 32 -b:v 0 -row-mt 1 -tile-columns 2 -deadline good -cpu-used 5`**. Alpha → `yuva420p`. AV1 option: `libsvtav1 -preset 8 -crf 35 -pix_fmt yuv420p`. | **`libopus 128k`** at 48 kHz | v {vp8, vp9, av1}; a {opus, vorbis}. Text subtitles → WebVTT. |
| → avi | `mpeg4 -vtag xvid -q:v 3`, `-fps_mode cfr` | `libmp3lame` **CBR 192k** | v {mpeg4, mjpeg, h264}; a {mp3, pcm_s16le, ac3} |
| → wmv | `wmv2 -q:v 3`, `-fps_mode cfr` | `wmav2 192k` | v {wmv1, wmv2}; a {wmav2} |
| → gif | palette pipeline: `fps=15, scale=min(480,iw), palettegen stats_mode=diff → paletteuse sierra2_4a`; HDR tone-mapped first; warns if the result would be over 50 MB or the clip over 60 s | none | — |
| → mp3 | — (`-vn -sn -dn`, selected audio track) | `libmp3lame -q:a 2`, or copy if the track is already MP3 | mp3 track |

Common rules: per-stream copy (R-14); `-map_metadata 0 -map_chapters 0`; even dimensions; rotation honoured; HDR→SDR via `zscale + tonemap=hable` for 8-bit targets; `file:` absolute paths and never a path inside a filtergraph.

> [challenge] **Per-stream copy into MP4/MOV can produce files the Mac itself can't play (15 §C-9).**
> - **AV1 → MP4/MOV copy.** 11 §2 measured `VTIsHardwareDecodeSupported(av01) == false` on the M2 Pro dev Mac. AV1 hardware decode starts at M3, and AVFoundation has no software AV1 decoder. So "AV1 is copied into MP4" yields a file that QuickTime, Photos and Quick Look can't play on M1/M2 Macs. **Rule:** copy AV1 into MP4/MOV only when `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)` is true *and* the user hasn't chosen "Maximum compatibility" (the default). Otherwise re-encode with VT H.264/HEVC. AV1 copy into MKV and WebM is unchanged.
> - **HEVC copy.** Matroska and many camera files carry `hev1` (in-band parameter sets), which QuickTime refuses. Every HEVC copy into MP4/MOV adds `-tag:v hvc1`. The pair test asserts that AVFoundation can open the output (`AVURLAsset.load(.isPlayable)`).
> - **MPEG-4 Part 2 copy.** Xvid/DivX ASP with packed bitstream, QPel or GMC (common in AVI) plays badly or not at all in AVFoundation. Copy `mpeg4` only for Simple Profile without B-frames, and add `-bsf:v mpeg4_unpack_bframes` when needed; otherwise re-encode.
> - **Generalised check:** for MP4/MOV targets, each copied stream must pass an `AVFoundation-playable` predicate (codec plus profile plus hardware). Otherwise it is re-encoded. M-COPY tests this.

Pairs, explicitly (expected behaviour on typical sources):

| Input | Outputs (7) | Typical path |
|---|---|---|
| mp4 | mov, mkv, webm, avi, wmv, gif, mp3 | mov and mkv **remux**; webm VP9 + Opus; avi copies H.264 and re-encodes AAC → MP3; wmv re-encode; gif palette; mp3 extract |
| mov | mp4, mkv, webm, avi, wmv, gif, mp3 | mp4 and mkv remux (ProRes → mp4 re-encodes the video to VT H.264); others as above |
| mkv | mp4, mov, webm, avi, wmv, gif, mp3 | mp4/mov remux when H.264/HEVC + AAC; Opus/Vorbis/PCM audio is re-encoded to AAC; image subtitles dropped with a note; webm remux when VP9/AV1 + Opus |
| webm | mp4, mov, mkv, avi, wmv, gif, mp3 | mkv remux; mp4/mov re-encode VP9 → VT H.264 (AV1 is copied into MP4 **only on Macs with AV1 hardware decode**, [challenge] see note below); audio Opus → AAC |
| avi | mp4, mov, mkv, webm, wmv, gif, mp3 | mkv remux; mp4 copies MPEG-4 ASP or H.264 video and re-encodes audio to AAC; webm and wmv re-encode |
| wmv | mp4, mov, mkv, webm, avi, gif, mp3 | mkv remux (WMV2 + WMA in Matroska); the rest re-encode |

6 inputs × 7 = **42**. Lanes: `remux` (copy), `hwVideo` (VT), `swVideo` (VP9, AV1, x264), `audio` (mp3 extract).

### 4.6 GIF: 6 pairs

| Input | → mp4 | → mov | → mkv | → webm | → avi | → wmv |
|---|---|---|---|---|---|---|
| gif | FF VT H.264, `-fps_mode vfr`, alpha flattened onto white (noted) | FF **HEVC-alpha** (keeps transparency) | FF VT H.264, vfr, flattened | FF **VP9 `yuva420p`** (keeps alpha) | FF mpeg4, cfr at the rounded fps (≤ 50) | FF wmv2, cfr |

### 4.7 PDF: 9 pairs

| Pair | Engine | Notes |
|---|---|---|
| pdf → docx | FUS → W:docx | Two modes: **Editable paragraphs** (default) or **Preserve original pages** (300 DPI page images, zero margins). Report: "Layout approximated · N tables · M pages OCR'd". |
| pdf → pages | FUS → CF-W | Same two modes |
| pdf → pptx | QZR per page → PPTXImageWriter (one picture per slide, optional OCR text boxes) | Slide size taken from the page box |
| pdf → xlsx | FUS tables → SJS write (one sheet per table, numbers and dates sniffed) | "No tables found" result instead of an empty file |
| pdf → jpg | QZR 300 DPI, white background | folder `<base> Pages/` when there are several pages |
| pdf → png | QZR 300 DPI, alpha kept | same |
| pdf → epub | **Reflowable**: FUS → W:epub. **Fixed layout**: page images, EPUB 3 `pre-paginated`, optional invisible OCR text. | Mode labels are Zivlet's own copy |
| pdf → txt | PDFKit `page.string`; Vision for scanned pages (text-layer test: > 20 printable chars per 1000 pt² and < 5 % U+FFFD) | Reading order from Vision |
| pdf → md | FUS → W:md (headings by font-size clustering, GFM tables, lists) | |

Encrypted PDFs prompt for the password. If `allowsCopying` is false, extraction routes refuse with clear copy.

### 4.8 Documents: 65 pairs

| Input | Outputs | Engine per output |
|---|---|---|
| **docx** (8) | pages, pdf, txt, md, html, epub, png, jpg | pages: MAM → CF-W (iW: Pages save). **pdf: DXP** (LO if present in Automatic). txt/md/html: MAM → W:txt/md/html. epub: MAM → W:epub (chapters split on H1, H2 fallback). png/jpg: DXP → QZR. |
| **pages** (8) | docx, pdf, txt, md, html, epub, png, jpg | CF-R → SDoc → W:docx/txt/md/html/epub. pdf: CF-R → WKP (iW Pages export when enabled). png/jpg: the pdf path → QZR. Last resort is the embedded `preview.jpg`, with a notice. |
| **md** (8) | docx, pages, pdf, txt, html, epub, png, jpg | MD-R → W:docx / CF-W / WKP / W:txt / W:html / W:epub / WKP→R / WKP→R |
| **rtf** (9) | docx, pages, pdf, txt, md, html, epub, png, jpg | NSAS → W:docx / CF-W / WKP / W:txt / W:md / W:html / W:epub / WKP→R / WKP→R |
| **rtfd** (9) | same 9 | NSAS (attachments become SDoc assets) → same writers |
| **textClipping** (9) | same 9 | clipping plist (`public.utf8-plain-text` / `public.rtf` data) → NSAS or TXT-R → same writers |
| **txt** (8) | docx, pages, pdf, md, html, epub, jpg, png | TXT-R (BOM, then strict UTF-8, then `NSString` encoding detection) → W:docx / CF-W / WKP / W:md / W:html / W:epub / WKP→R / WKP→R |
| **epub** (6) | pdf, docx, pages, txt, md, html | pdf: spine XHTML in RenderHost (book CSS kept, scripts off) → print per spine item → PDFKit merge. Others: EPUB-R → W:docx / CF-W / W:txt / W:md / W:html. |

Count: 8 + 8 + 8 + 9 + 9 + 9 + 8 + 6 = **65**. Lanes: `js` (MAM, CF), `render` (WKP, DXP), `cpu` (writers).

### 4.9 Slides: 6 pairs

| Pair | Tier 1 | Tier 2 | Notes |
|---|---|---|---|
| pptx → pdf | **PPTR** (vector, charts via bundled ECharts, no network) | LO `impress_pdf_Export`; iW Keynote | |
| pptx → jpg | PPTR snapshot @2× | LO/Keynote → PDF → QZR | folder `<base> Slides/Slide 001.jpg` |
| pptx → png | PPTR snapshot @2× | same | same folder rule |
| ppt → pdf | **none** | **LO (required) or iW Keynote** | The slice shows "Needs Office Engine or Keynote" with a one-click install card **[OWNER]** |
| ppt → jpg | none | LO → PDF → QZR, or Keynote slide images | LibreOffice's own `--convert-to png` renders only the first slide (MEASURED) |
| ppt → png | none | same | |

Parity caveat: **3 of the 275 pairs (PPT) need an optional engine.** Spike D-RENDER also tries the experimental `@silurus/ooxml` legacy reader as a raster-only Tier 1.

### 4.10 Spreadsheets: 21 pairs

| Input | Outputs | Engine |
|---|---|---|
| xlsx (4) | ods, csv, tsv, pdf | SJS (ods: "Formatting simplified" note when the source is styled). pdf: SJS→WKP, or LO `calc_pdf_Export` when present (print areas, charts). |
| xls (5) | xlsx, ods, csv, tsv, pdf | SJS reads BIFF2–8; same writers |
| ods (4) | xlsx, csv, tsv, pdf | SJS |
| csv (4) | xlsx, ods, tsv, pdf | SJS (delimiter and locale sniffing; optional UTF-8 BOM output for Excel) |
| tsv (4) | xlsx, ods, csv, pdf | SJS |

> [challenge] **Fidelity gap on xlsx → pdf (15 §C-12).** Style-aware spreadsheet stacks (for example Apache POI with PDFBox, or LibreOffice) read cell styles. SheetJS **Community Edition** 0.20.3 parses values, number formats, merges and (with `cellStyles`) column widths. The only per-cell style it attaches is the **fill**: `p.s = styles.Fills[fillid]` (VERIFIED in `xlsx.mjs` from cdn.sheetjs.com). Fonts (bold, size, colour), borders and alignment are parsed into tables but never reach the cells. Full style objects are a SheetJS Pro feature. SJS→WKP therefore prints a plain grid where a style-aware renderer prints coloured headers and borders, and xlsx → ods also drops formatting. **Change:** move the styled reader forward from Phase 4 to Phase 2. Use `umya-spreadsheet 3.1.x` (MIT, Rust, actively maintained: 2026-10-12) in `libzivlet_rs` to read XLSX styles for the HTML print path, and keep SheetJS CE for XLS/ODS/CSV reading and all writers. XLS (BIFF) styling stays unsupported in Tier 1 (LO path).

A multi-sheet source going to csv/tsv produces the folder `<base> Sheets/<Sheet>.csv`. A single sheet becomes a file beside the original. If spike D-SHEET fails (2 M cells in < 15 s, < 1.5 GB RSS), the reader and writer swap to calamine 0.37 + rust_xlsxwriter behind the same `Sheets` protocol.

### 4.11 Subtitles: 4 pairs

| Pair | Engine |
|---|---|
| srt → vtt | SUB (UTF-8 out, `WEBVTT` header, `,` → `.` milliseconds, `{\anN}` → `line:`) |
| srt → txt | SUB (cue text only, tags stripped, one paragraph per cue) |
| vtt → srt | SUB (cue settings, `<c>`, `<v>` and timestamp tags dropped; indices renumbered) |
| vtt → txt | SUB |

### 4.12 Archives: 9 pairs

| Pair | Engine | Notes |
|---|---|---|
| zip → tar | LA | ZIP with AES/ZipCrypto prompts for the password |
| zip → gz | LA → `.tar.gz` | parity: "GZIP" means tar.gz |
| tar → zip | LA (zip, Deflate 6, UTF-8 flag) | |
| tar → gz | LA (gzip filter) | |
| gz → zip | LA | `.tar.gz`/`.tgz` → entries. A plain single-file `.gz` becomes one entry named after the base. |
| gz → tar | LA | same |
| rar → zip | LA (RAR4, RAR5, solid; multi-volume when all parts are dropped) | Encrypted RAR → "Use The Unarchiver or Keka" |
| rar → tar | LA | |
| rar → gz | LA → `.tar.gz` | |

Re-packing streams entry by entry without extracting to disk, but the same entry-count, size and ratio limits as Extract apply (§8.9).

### 4.13 Count check

| Category | Pairs | Engine family |
|---|---|---|
| Raster images | 49 | IIO / WEBP / QZ |
| SVG | 8 | RSVG / S2P |
| Audio | 56 | FF |
| Video | 42 | FF |
| GIF | 6 | FF |
| PDF | 9 | FUS / QZR / SJS / CF-W |
| Documents | 65 | SDoc + WKP / DXP (LO, iW optional) |
| Slides | 6 | PPTR (3) / LO or iW (3) |
| Spreadsheets | 21 | SJS (+ LO for styled PDF) |
| Subtitles | 4 | SUB |
| Archives | 9 | LA |
| **Total** | **275** | 272 work out of the box; 3 (PPT) need LO or Keynote |

CI enforces this with `@Test(arguments: Catalog.allPairs)`: every pair must resolve to at least one available engine on a clean macOS 26 VM, or be explicitly marked `requiresOptionalEngine`.

### 4.14 Zivlet extras beyond the 275 (behind the same catalog)

| Extra | Engine | Phase |
|---|---|---|
| png/jpg/heic → docx (OCR) | Vision `RecognizeDocumentsRequest` → W:docx | 3 |
| video → m4a (stream copy when the track is AAC) | FF | 2 |
| video/gif → animated WebP; WebP (animated) input | FF `libwebp_anim`; FFmpeg 9 animated-WebP decoder | 2 |
| WebM AV1 option | FF `libsvtav1` | 2 |
| RAW/PSD/JXL/EXR/JP2 inputs; ICO (≤ 256 px) / ICNS outputs | IIO (+ `CIRAWFilter`) | 3 |
| JPEG XL output | libjxl 0.12 | 4 |
| odt/doc/odp inputs | LO (T2) | 3 (with LO) |
| keynote/numbers inputs | CF-R / iW | 4 |
| md ↔ html | MD-R / SwiftSoup | 3 |
| 7z/xz/zst/iso/cab inputs; 7z, AES-ZIP, tar.xz/zst outputs | LA | 4 |
| ASS/SSA/SBV subtitle input; time shift, fps conversion | SUB | 4 |

---

## 5. Tools: all 27

The input sets are Zivlet's tool scope (single file / multiple files). Output naming follows OWN-3 (00-decisions), and the `<base> <Suffix> 2.<ext>` collision rule is in §8.5.

| # | Tool | Inputs: single / multi | Engine and recipe | Output | Phase |
|---|---|---|---|---|---|
| 1 | **Compress** | images (jpg png webp heic tiff), audio (mp3 m4a wav flac), video (mp4 mov mkv), pdf / same | **Images:** IIO quality binary search [0.30, 0.92], at most 7 in-memory encodes, then max-pixel steps of −15 %. **WebP:** `config.target_size` + `pass 6`. **PNG:** imagequant + oxipng. **Audio:** same codec at a lower bitrate; wav and aiff → FLAC. **Video:** preset = VT HEVC `-q:v` 55/45 + an optional height cap; target size **Fast** = VT ABR with verify, retried ×0.92 up to 3 times; **Accurate** = x264 2-pass. **PDF:** runtime Quartz filter presets (Light q0.85/220 DPI, Balanced 0.7/150, Strong 0.5/110), a 2-D target-size search over at most 6 passes, then a qpdf lossless pass. Forms, signatures or tags trigger a pre-flight warning and an offer of lossless-only. **Guard:** if output ≥ input, keep nothing and report "Already optimal". | `<base> Compressed.<ext>` (wav/aiff → `.flac`) | 2 |
| 2 | **Metadata** (view, edit, strip) | images, audio, mp4/mov/mkv, gif, pdf / same | **Read:** ExifTool JSON (`-j -G1 -a -s -n -struct`), plus ffprobe tags for media. **Write/strip:** ExifTool for images, GIF, PDF and MP4/MOV/M4A; ffmpeg `-c copy -map 0 -map_metadata -1 -map_chapters -1` (or `-metadata k=v`) for MP3, FLAC, OGG, Opus, WAV, AIFF, WMA and MKV. *[challenge: `-map 0` keeps `attached_pic` cover-art streams, and a cover JPEG can carry its own EXIF and GPS. "Remove all" must drop them (`-map 0 -map -0:disp:attached_pic`, using the `disp:` stream specifier documented in FFmpeg 9.0, or explicit index maps from ffprobe), or re-encode the cover through ImageIO with no properties, so `-fflags +bitexact` doesn't re-add a `Lavf` encoder tag. MKV attachments (fonts) are kept but their filename and mimetype tags are reviewed. M-META also covers this.]* For PDF, a qpdf full rewrite drops old incremental revisions. **Verify:** re-read the file; every planned change applied, nothing else changed, `ImageDataHash` unchanged; "Remove all" leaves no GPS, maker notes, XMP, IPTC, thumbnail or C2PA (unless C2PA is kept). | strip: `<base> No Metadata.<ext>`; edit: `<base> Edited Metadata.<ext>` | 2 |
| 3 | **Edit Photo** | jpg png webp heic tiff / — | Core Image chain in one P3 linear `CIContext`: exposure, colour controls, highlight/shadow, temperature/tint, vibrance, sharpen, noise reduction, vignette, grain. Dehaze, clarity and texture are our own Metal `CIKernel`s (ESTIMATE). RAW sources go through `CIRAWFilter`. | `<base> Edited.<ext>` | 3 |
| 4 | **Annotate Photo** | same / — | Our own CoreGraphics/CoreText layer model: arrow, freehand, text, rectangle, ellipse, highlighter, counter, magnifier, pasted image. Rendered at full resolution. | `<base> Annotated.png` | 3 |
| 5 | **Add BG** | same / — | CoreGraphics gradient and colour presets, padding, corner radius, shadow, canvas ratio. Optional Vision foreground mask for a subject shadow. | `<base> With Background.<ext>` | 3 |
| 6 | **Crop Image** | same / same ("Apply to all" proportional) | IIO decode → `CGImage.cropping(to:)` → same-format encode (WEBP for WebP). Lossless JPEG MCU-aligned crop is P4. | `<base> Cropped.<ext>` | 2 |
| 7 | **Normalize Volume** | mp3 m4a wav flac / same | FF EBU R128 two-pass `loudnorm` (measured values passed into pass 2, `linear=true`). Presets −16/−14/−23 LUFS, TP −1.5, LRA 11. | `<base> Normalized.<ext>` | 2 |
| 8 | **Remove Audio** (instant) | mp4 mov mkv / same | FF `-map 0 -map -0:a -c copy` (measured 37 ms) | `<base> Muted.<ext>` | 2 |
| 9 | **Trim Video** | mp4 mov mkv / — | FF **Fast** (keyframe, `-c copy -avoid_negative_ts make_zero`) or **Exact** (re-encode). Preview via AVPlayer, or an ffmpeg proxy for formats AVFoundation can't play. | `<base> Trimmed.<ext>` | 2 |
| 10 | **Split PDF** (instant) | pdf / same | PDFKit per page; qpdf `--split-pages` for very large files | folder `<base> Pages/Page 001.pdf` | 2 |
| 11 | **Organize PDF** | pdf / — | PDFKit reorder, rotate, delete; "same width" scaling; `PDFThumbnailView` grid | `<base> Organized.pdf` | 2 |
| 12 | **Extract Archive** (instant) | zip tar gz rar (+ 7z etc. later) / same | LA with `SECURE_NODOTDOT`, `SECURE_SYMLINKS` and `SECURE_NOABSOLUTEPATHS`, no owner and no setuid. Unpacked into hidden staging beside the archive, then renamed. The quarantine xattr is propagated. | folder `<base> Extracted` | 2 |
| 13 | **Create PDF** (instant, multi only) | — / images (+ svg) | QZ: one page per image, JPEG bytes embedded, page size from the image at 72/150/300 DPI or A4/Letter; SVG pages via S2P, then merged | `<first base> Combined.pdf` | 2 |
| 14 | **Merge PDFs** (multi only) | — / pdf | PDFKit insert, keeping the first document's outline. qpdf `--empty --pages` when a source has forms, encryption or signatures. | `<first base> Merged.pdf` | 2 |
| 15 | **Crop Video** | mp4 mov mkv / — | FF `crop=w:h:x:y` (even dimensions), re-encoded in the source container's default codec (VT), audio copied, portrait rotation honoured | `<base> Cropped.<ext>` | 2 |
| 16 | **Change Video Speed** | mp4 mov mkv / — | FF `setpts=PTS/s` + `atempo` (chained below 0.5), 0.25×–4×, pitch preserved | `<base> Speed 2x.<ext>` | 2 |
| 17 | **Join Videos** (multi only) | — / mp4 mov mkv | FF concat demuxer + `-c copy` when every input has the same codec parameters; otherwise the first clip sets the canvas (`scale…decrease, pad, setsar=1, fps`), `concat`, `anullsrc` fills missing audio, then VT H.264 + AAC | `<first base> Joined.mp4` | 2 |
| 18 | **Video Snapshots** | mp4 mov mkv / — | UI frame grab via `AVAssetImageGenerator` (or the proxy). Export via FF `-ss t -frames:v 1 -update 1` PNG, one job per timestamp. | `<base> Snapshot.png`; several → folder `<base> Snapshots/Frame 001 - 12.345s.png` | 2 |
| 19 | **Split Video** | mp4 mov mkv / — | FF: separate clips (N × fast or exact trim), or "One video" (concat of kept segments when keyframe-aligned, else `trim/atrim + concat` re-encode) | folder `<base> Clips/Clip 001.<ext>`; one-video mode → `<base> Edited.<ext>` | 2 |
| 20 | **Audio Visualizer** | mp3 m4a wav flac / — | FF `showwaves mode=cline:rate=30:scale=sqrt` in our brand colour, or a still image looped at 30 fps; 16:9, 9:16 or 1:1; VT H.264 + `aac_at` | `<base> Visualizer.mp4` | 3 |
| 21 | **Trim Audio** (+ auto-trim silence) | mp3 m4a wav flac / — | FF `-ss/-to`. Auto mode: `silencedetect=noise=<dB>dB:d=0.1` analysis (−80…−10 dB), then a copy trim. Waveform from `AVAudioFile`, or an ffmpeg `f32le` pipe at 2 kHz. | `<base> Trimmed.<ext>` | 2 |
| 22 | **Convert Audio Channels** | mp3 m4a wav flac / — | FF `-ac 1` or `pan=stereo\|c0=L*c0\|c1=R*c1`; swap and dual-mono options | `<base> Mono.<ext>` / `<base> Stereo.<ext>` | 2 |
| 23 | **Create Collage** (multi only) | — / images (+ svg) | CoreGraphics in P3: grid, horizontal, vertical or featured layout; spacing, padding, corners, fill or fit; at most 8192²; options remembered | `<first base> Collage.png` | 3 |
| 24 | **Read QR Codes** | images, pdf / same | Vision `DetectBarcodesRequest` (QR, micro-QR, Aztec, DataMatrix, PDF417, EAN/UPC, Code 39/93/128, ITF-14, GS1, Codabar); PDF pages at 200 DPI. The results window offers Copy and Copy All, plus Open for `http(s)` only, with the full URL shown and never auto-opened. | no file | 2 |
| 25 | **Redact Photo** | jpg png webp heic tiff / — | Vision faces (boxes +15 %), text and **PII auto-select** (`RecognizeDocumentsRequest.detectedData`: e-mail, phone, address, links, dates, money), plus our own IBAN, card (Luhn) and ID regexes. Burn-in with a solid fill (default), pixellate (≥ max(16 px, 4 % of the short edge)), or heavy blur (radius ≥ 30 px, with a warning). **Always strips metadata, including the EXIF thumbnail.** | `<base> Redacted.<ext>` | 3 |
| 26 | **Redact Video** | mp4 mov mkv / — | Vision detection on keyframes + `TrackObjectRequest` → per-frame boxes → FF `drawbox` (solid) or `split→crop→gblur→overlay` (blur) via a `-/filter_complex <file>` script, with `enable='between(t,a,b)'` time ranges. *[challenge: one `drawbox` per tracked box per time slice makes a filtergraph with thousands of nodes for a moving face, and every node evaluates `enable` on every frame. Use **one filter instance per track, driven by `sendcmd`** (`sendcmd=f=boxes.cmd,drawbox@t1=…`, with commands keyed by timestamp), or pipe a Swift-rendered **mask video** (`-f rawvideo -pix_fmt gray` on stdin) and composite with `maskedmerge` against a blurred copy. Pass bar in M-REDACT: a 10-min 1080p clip with 3 tracks runs ≥ 1× realtime.]* | `<base> Redacted.<ext>` | 3 |
| 27 | **Bleep Audio** | mp3 m4a wav flac / — | FF: the program is gated by `volume=enable='between(t,a,b)':volume=0`, mixed with a 1 kHz `sine` that is gated the other way, then `amix=normalize=0`. Video tracks are copied. | `<base> Bleeped.<ext>` | 3 |

> [challenge] **Output names: apply OWN-3.** OWN-3 (00-decisions) fixes these names, which differ from the table above:
> - Speed: "Speed 2.0x" / "Speed 0.5x" (one decimal place); here "Speed 2x".
> - Create PDF: "<first> Images.pdf"; here "Combined".
> - Image metadata: "Metadata Edited" / "Metadata Removed"; here "Edited Metadata" / "No Metadata". PDF and A/V removal stay "No Metadata".
>
> O-16 should list each difference explicitly, so every deviation is deliberate and not an accident. The OWN-3 name is the default.

**Beyond-parity tools** (catalogued but outside the 27):

| Tool | Engine | Phase |
|---|---|---|
| Remove Background | Vision `GenerateForegroundInstanceMaskRequest`; macOS 27 tap/brush refine | 4 |
| Make PDF Searchable (OCR) | Vision → invisible text layer, or `.saveTextFromOCROption` (spike I-PDF3) | 4 |
| PDF Protect, Unlock, Optimize, Fast Web View | qpdf | 4 |
| QR Generate | `CIQRCodeGenerator` | 4 |
| Batch Rename | own, with token preview and Undo | 4 |
| Transcribe → SRT/VTT | FFmpeg `whisper` filter (whisper.cpp, MIT) or the macOS Speech framework (on-device) | 5 |

---

## 6. Actions: all 6

Actions run **in the app** with no worker, accept folders and mixed selections, and use no conversion engine.

| # | Action | Implementation | Errors and edge cases | Phase |
|---|---|---|---|---|
| 1 | **AirDrop** | `NSSharingService(named: .sendViaAirDrop)`; `canPerform(withItems:)`, then `perform(withItems:)`; the delegate reports success or failure in the result card | Error card when `canPerform` refuses the selection. Non-local items are refused. | 1 |
| 2 | **Float** | Our own `FloatShelfPanel`: non-activating `NSPanel` at `.floating`, all Spaces and full-screen auxiliary. Several shelves can be open. Each docks to a screen edge as a tab or floats free, and switches between compact and expanded, icons and list. Thumbnails come from `QLThumbnailGenerator` and Quick Look from `QLPreviewPanel`. Drag-out is an `NSDraggingSource` with file URLs. Marquee selection, type-to-select, and a context menu (Open, Open With, Quick Look, Show in Finder, Copy, Share, Move to Trash, Remove). The setting `floatWheelBehavior` is new shelf or add to existing. Pointer tracking uses a global mouse monitor, so no permission is needed. Shelves are restored after relaunch. | Missing files show greyed out with "Locate…". The shelf references files and never copies them. | 2 |
| 3 | **Copy** | `NSPasteboard.general.clearContents()` then `writeObjects(urls as [NSURL])` | Error card when any item is not a local file URL. | 1 |
| 4 | **Move** | `NSOpenPanel` (directories only, prompt "Move Here", raised above the wheel) → per item, `FileManager.moveItem`. Collisions get the "name 2" rule. Across volumes: copy, verify size and count, then trash the source. A folder can't be moved into itself. Recorded in the **UndoLog** (the Undo button moves items back). | Error card when the chosen destination is not an existing local folder; success card with the moved count; per-item failures listed | 1 |
| 5 | **Copy Path** | Newline-joined POSIX paths as `.string`. ⌥ variant: shell-quoted, space-separated. | Error card when any item has no local POSIX path. | 1 |
| 6 | **Terminal** | Folder, or a file's parent → `NSWorkspace.shared.open([dir], withApplicationAt: termURL, configuration:)`. Settings lists the installed terminals: Terminal `com.apple.Terminal` (default), iTerm2 `com.googlecode.iterm2`, Ghostty `com.mitchellh.ghostty`, WezTerm `com.github.wez.wezterm`, Warp `dev.warp.Warp-Stable`. Each must be verified to open a directory URL (spike P-TERM). | Error card when the selected terminal is not installed, with a button that opens Settings to pick another. | 1 |

