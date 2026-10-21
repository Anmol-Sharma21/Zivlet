# Zivlet roadmap: image cluster

> Imported into the repository on 2026-10-21 from the roadmap drafts; approved by the owner the same day
> (see [00-decisions.md](00-decisions.md), 2026-10-21 section). The product name is Zivlet.
> Prototype folders named `<name>.XXXX/` are local prototypes and are not published.
> The "17-* files" below are now [17-feature-roadmap.md](17-feature-roadmap.md), [17-roadmap-challenge.md](17-roadmap-challenge.md),
> [01b-prd-additions.md](../plan/01b-prd-additions.md) and [05-task-list.md §9](../plan/05-task-list.md).

> [challenge] Adversarial review 2026-10-21 ([17-roadmap-challenge.md](17-roadmap-challenge.md)). The 17-* files are authoritative wherever they differ from this report. Corrections that apply here:
> - Spike **I-C1 is renamed I-C2** (10 §13's I-C1 is jpegli/libavif). I-V2 is folded into the existing I-V1/S-V1 (P2-06).
> - The Hindi evidence is from macOS 27 only, while the minimum OS is 26.0. The fallback is OWN-OCR-1.
> - Match Hindi support by `languageCode == "hi"`: the Swift API lists `hi-Deva-IN`, VN lists `hi-IN`.
> - P3 subject picker: `instanceAtPoint` exists only on the Swift observation. On the VN fallback, read `instanceMask`.
> - Remove-background **refine** (macOS 27, `GenerateIterativeSegmentationRequest`) is a `DownloadableAssetsRequest`,
>   so Apple downloads its assets over the network. It must be user-initiated.
> - Batch Rename is resized M → L.

Date: 2026-10-21. Scope: the owner's image picks (00-decisions, 2026-10-21): copy text from image (OCR, Hindi), batch rename, batch resize, JPEG XL output, smaller PNG, remove background.
Inputs read: `docs/design/00-decisions.md`, `10-tech-strategy.md` (§4.2, §5, §9, §10, §12), `13-image-pdf-engine.md`, `14-app-platform.md`, `docs/plan/01-prd.md`, `02-architecture.md`, `03a/03b`, `05-task-list.md`.
Out of scope here: PDF OCR / searchable PDF (PDF cluster), Instagram and fit-to-size presets (their own clusters; resize shares code with them), transcription.

Evidence labels: **MEASURED** = run on this Mac for this report; **DOC** = vendor docs or existing design docs; **EST** = estimate.
Probe machine: Apple M2 Pro, 10 cores, 16 GB, **macOS 27.0 (26A428)**, Swift 6.4, Xcode at `/Applications/Xcode.app`. Our minimum is macOS 26, so every result below must be re-checked on a 26.x VM (spike G-0).
**Timing caveat:** other agents were running whisper, ffmpeg and Python spikes at the same time (load average 30–77 on 10 cores). All times below are inflated, often 3–8×. Treat them as upper bounds. Sizes and quality scores are not affected.

Prototype folders (all scripts and outputs; local prototypes, not published):
- `ocr.nzlJ/`: `render.swift`, `render2.swift` (test-image generators), `ocr.swift` (7 Vision configs, CER scoring), `langs.swift`
- `bg.NBNI/`: `bg.swift` (Swift Vision API, fails), `bgswift-min.swift` (isolates the failure), `bgvn2.swift` (VN API, works), `out/` (cut-outs and previews on magenta)
- `batch.NKCh/`: `fixtures.swift`, `resize.swift`, `rq.swift` (resize quality), `rename.swift` (rename with preview, journal and undo)
- `jxl.pxR3/`: `iio.swift` (ImageIO capability probe), `enc.swift` (ImageIO encoder), `jxl-results*.txt`
- `png.3iUy/`: `pngtool/` (Rust: oxipng 10.2.1 + imagequant 4.4.1), `png-results.txt`
- `photos.qvoc/`: four **CC0** Wikimedia Commons photos: "A photo of a cat sitting down", "Cute gray cat sitting in bed", "Coffee cup and coffee bean", "Purple ribbon tied to a potted plant 3"

---

## 0. Summary

| Feature | Engine | Licence | Bundle cost | Effort | Phase |
|---|---|---|---|---|---|
| Copy text from image (OCR, Hindi + English) | Vision `RecognizeDocumentsRequest` / `RecognizeTextRequest`, languages **`[hi-IN, en-US]` in that order** | system | 0 MB | M | **Phase 2, first tool** (stretch: late Phase 1) |
| Batch resize | ImageIO thumbnail decode (≥ 2× target) + Core Image Lanczos to the exact size; ImageIO/libwebp encode | system (+ libwebp BSD-3, already planned) | 0 MB | M | **Phase 2** |
| Batch rename (tokens, preview, undo) | own Swift; ImageIO EXIF date; UndoLog journal | own (GPL-3.0+) | 0 MB | M | **Phase 2** |
| Smaller PNG | oxipng 10.2.1 (MIT) + imagequant 4.4.1 (GPL-3.0+) in `ZivletRS` | MIT / GPL-3.0+ | **≈ 0.75 MB MEASURED** (already inside the planned Rust lib) | S (on top of P2-10) | **Phase 2** |
| Remove background | Vision **`VNGenerateForegroundInstanceMaskRequest`** (the Swift-native request failed here, §6.3) | system | 0 MB | S (one tap) / M (subject picker) | **Phase 2** (one tap), refine later |
| JPEG XL output | libjxl 0.12 (BSD-3 + patent grant), static | BSD-3 | **+2.5–3.3 MB** (3.28 MB MEASURED Homebrew dylib set) | M | **Phase 3**, gated on the size budget |

Headline findings from the prototypes:
1. **Hindi OCR works offline, but only when Hindi comes first in the language list.** With `[hi-IN, en-US]`, all 12 test images (pure Devanagari, code-mixed Hinglish, Roman Hinglish, English, dark mode, degraded photo-like, Devanagari digits) came out at **0–0.8 % CER**. With `[en-US, hi-IN]` or the default, Devanagari is silently dropped (CER 100 % on pure Hindi). Automatic language detection fails when a single Hindi word sits in an English sentence ("आधार" came back as "HER").
2. **The first OCR run on a fresh OS needs minutes of one-time model compilation.** That was 7.3 min + 9.4 min for the first two configurations here (ANE compiler), and 5 min more the first time auto-detect ran on a large image. The compiled model is cached across processes (a fresh process then took 3.0 s for its first call, about 0.3 s per image after that). Background warm-up is mandatory.
3. **The Swift-native `GenerateForegroundInstanceMaskRequest` returned `requestCancelled` in every call style, inside an app bundle too.** The older `VNGenerateForegroundInstanceMaskRequest` works (0.4–1.4 s per photo under load). Design 13 §8.2 must change to the VN API until the Swift one is re-tested on 26.x.
4. **The ImageIO thumbnail resize planned in 03b §6.1 is noticeably soft.** It scored SSIMULACRA2 66.8 and 83.7 against a linear-light Lanczos reference, versus 94.4 and 92.9 for Core Image Lanczos. Use a hybrid: thumbnail decode to ≥ 2× the target, then Lanczos.
5. **Lossless oxipng cuts Retina screenshots by 45 %** (6.1 → 3.3 MB). Lossy imagequant should never be applied to photos: it scored SSIMULACRA2 73.8 on the test photo, a visible loss.
6. **ImageIO can read JPEG XL but cannot write it** (`CGImageDestinationCreateWithData(…"public.jpeg-xl"…)` returns nil). libjxl's lossless JPEG transcode is **bit-exact and 15–19 % smaller**. Lossy d1.0 is 20–24 % smaller than JPEG of equal quality.

---

## 1. Copy text from image (OCR, incl. Hindi + English) — VERY IMPORTANT

### 1.1 User-facing behaviour
- **Wheel slice "Copy Text"** (tool group Images; also offered for PDFs by the PDF cluster). Drop one or more images (PNG, JPEG, HEIC, WebP, TIFF, screenshots, plus scanned single-page PDFs via the PDF cluster's renderer). No window opens.
- **Default output: clipboard.** The HUD result card shows the first lines, the character count, the detected scripts ("Hindi + English") and buttons: **Copy again**, **Save as .txt**, **Show all** (a scrollable, selectable text view).
- **Modifier (⌥, per the modifier scheme in 03a):** also write `<base> Text.txt` beside the original (UTF-8, no BOM, LF line endings). For multiple images the clipboard gets one combined text with `— <file name> —` separators, and ⌥ writes one `.txt` per image.
- **Languages (Settings → Text recognition):** an ordered list. The default comes from the system's preferred languages; if Hindi or Marathi is present (or the Hindi keyboard is enabled) the default is **Hindi, English** in that order. A one-click preset "Hindi + English (Hinglish)" sets it. "Automatic" is offered but is **not** the default (§1.4).
- Output keeps the script as written: Devanagari stays Devanagari, Roman Hinglish stays Latin. No transliteration (the transcription cluster owns Roman/Devanagari conversion).
- Reading order: paragraphs from `RecognizeDocumentsRequest`, so multi-line paragraphs join into one line in the `.txt` and blocks are separated by blank lines. Tables come out tab-separated (a free bonus from the documents request).
- Empty result: "No text found" card. That is not an error, and nothing is written.
- First use before the warm-up has finished: the card says "Preparing text recognition (one-time, a few minutes)…" with a spinner, and the job continues in the background. Other jobs are not blocked (separate scheduler lane).

### 1.2 Engine choice
- **Vision, system framework, 0 MB, on-device.** Both `RecognizeTextRequest` (macOS 15) and `RecognizeDocumentsRequest` (macOS 26) list `hi-Deva-IN` and `mr-Deva-IN` on macOS 27 (MEASURED, §1.3). There is no Tesseract fallback: Tesseract `hin` data plus the engine is about 20 MB or more (EST), and in these tests Vision was already perfect.
- Use **`RecognizeDocumentsRequest`** with `textRecognitionOptions.recognitionLanguages = [hi, en]`, `useLanguageCorrection = true` and `automaticallyDetectLanguage = false`. It was equal in accuracy, the same speed or faster, and gives paragraphs, lists and tables. It is also the request the PDF searchable-OCR and Redact features use (design 13 §8.3/§8.5), so build one shared `TextRecognizer` service (in `EngineImage`, or a small `EngineVision` module) that all three call.
- Run it in the engine worker (untrusted image decode, ADR isolation rule), and return text over the existing job IPC.

### 1.3 Evidence (MEASURED)
Commands (in `ocr.nzlJ/`):
```
swiftc -O langs.swift -o langs && ./langs          # supported languages
swiftc -O render.swift -o render && ./render img    # 7 test images + ground truth
swiftc -O render2.swift -o render2 && ./render2 img2 # 5 edge-case images
swiftc -O ocr.swift -o ocr && VERBOSE=1 ./ocr img; VERBOSE=1 ./ocr img2
```
Supported (accurate level, macOS 27): `… "hi-IN", "mr-IN"` (33 languages). The `.fast` level supports only 6 Latin languages, so Hindi requires `.accurate`.

Test images were rendered with CoreText (Kohinoor Devanagari, Devanagari Sangam MN, Helvetica Neue). "Degraded" = rotated 3°, blur σ 0.9, noise, then JPEG q0.35 at 22 px. Character error rate (CER) = Levenshtein distance over Unicode scalars, NFC, whitespace collapsed.

| Image (content) | default (en) | `[en,hi]` | **`[hi,en]`** | auto-detect | docs `[hi,en]` | docs auto |
|---|---|---|---|---|---|---|
| english_print | 0 % | 0 % | **0 %** | 0 % | 0 % | 0 % |
| roman_hinglish ("Kal meeting 10 baje hai…") | 0 % | 0 % | **0 %** | 0 % | 0 % | 0 % |
| hindi_print (Kohinoor) | 100 % (empty) | 100 % | **0 %** | 0 % | 0 % | 0 % |
| hindi_sangam (Sangam MN) | 100 % | 100 % | **0 %** | 0 % | 0 % | 0 % |
| mixed_print ("Meeting कल सुबह 10 बजे है…") | 38.3 % | 38.3 % | **0.8 %** ("WiFi"→"Wifi") | 0.8 % | 0.8 % | 0.8 % |
| mixed_dark_small (17 px, white on dark) | 46.6 % | 46.6 % | **0 %** | 0 % | 0 % | 0 % |
| mixed_degraded (photo-like) | 37.6 % | 37.6 % | **0 %** | 0 % | 0 % | 0 % |
| short_mixed ("कल 10 बजे meeting") | 29.4 % | 29.4 % | **0 %** | 0 % | 0 % | 0 % |
| one_hindi_word ("Please bring your आधार card") | 10.8 % ("HER") | 10.8 % | **0 %** | **10.8 % ("HER")** | 0 % | **10.8 % ("HUR")** |
| mostly_english (one Hindi line) | 31.7 % (line dropped) | 31.7 % | **0 %** | 0 % | 0 % | 0 % |
| hindi_numbers ("कुल राशि: ₹1,250.00") | 59.6 % | 59.6 % | **0 %** | 0 % | 0 % | 0 % |
| devanagari_digits ("₹१२५०", "२१ अक्टूबर") | 100 % | 100 % | **0 %** | 0 % | 0 % | 0 % |
| **Images ≤ 1 % CER** | 2/12 | 2/12 | **12/12** | 11/12 | **12/12** | 11/12 |

Language correction on or off made no difference (`[hi,en] nocorr` also 12/12).

Timing:
| Situation | Time |
|---|---|
| Very first call on this OS install (default config) | **437 s** (ANE compiler busy; process stack in `E5RT … MILCompilerForANE`, `ANECompilerService` used 4.5 CPU-min) |
| First call with `[hi,en]` after that | **564 s** |
| First auto-detect call on a large (3600×2338) image | **302 s** |
| Warm, new process, first call | 3.0 s; then 0.15–0.7 s per small image |
| Warm, 3600×2338 Retina screenshot | 0.66–2.0 s per config |

So compiled models are cached system-wide and survive process restarts, but each new configuration (and apparently some input-size buckets) can trigger its own compile.

### 1.4 Risks
- **Language order is a silent failure mode.** With English first, Vision drops Devanagari without any error. Mitigation: Hindi-first default when Hindi is in the user's languages; a test fixture that fails CI if any Devanagari golden image returns no Devanagari.
- **Auto-detect misses isolated Hindi words** (11/12). Do not make it the default for Hindi users.
- **Cold compile measured in minutes** (much worse than the 58 s noted in design 13 §8.1, although that number was taken on an idle machine). Mitigation: after onboarding, warm up the exact production configuration at `.utility` QoS on a 64 px **and** a ~3000 px blank-with-text image; persist a "warmed for OS build X" flag; re-warm after OS updates; show a determinate "one-time preparation" state; never time out the job.
- **macOS 26.0 language list not verified.** Hindi might be new in 27. If it is missing on 26.x, the Hindi option is hidden there via the capability probe. That would be a real product gap for this owner, so spike **I-V2** (below) must run early.
- Handwriting, stylised fonts and low-light phone photos were not tested. Add real phone photos of Hindi signage and receipts to the fixture corpus (owner can supply them; there are no licence issues for private CI fixtures).
- Privacy: text goes to the clipboard. Don't put it in History previews by default (History shows "Text copied, 342 characters" without the content).

### 1.5 Effort, dependencies, phase
- **Effort M:** request wrapper S, warm-up + capability probe S, settings language list S, result card "text" variant + `.txt` writer + multi-image combine S, fixtures (12 rendered + real photos) S.
- **Dependencies:** engine worker job type returning text (no output file); HUD result card (P1-41) gains a text variant; capability probe (Vision languages per OS); Settings store; shared with PDF searchable OCR (PDF cluster) and Redact Photo (Phase 3).
- **Phase:** Phase 2 as the **first tool shipped** (the owner rated it very important). It needs no vendored library, so it could also land at the end of Phase 1 once the HUD card and worker exist.
- **New spike I-V2:** on macOS 26.0 and 26.x, (a) are `hi-IN`/`mr-IN` listed, (b) do the 12 fixtures still pass with `[hi,en]`, (c) cold-compile time, and whether warm-up removes it.

---

## 2. Batch resize — IMPORTANT

### 2.1 User-facing behaviour
- **Wheel slice "Resize"** (single or multiple images). A small options popover opens (same pattern as Compress options) and remembers the last choice:
  - **Long edge** (presets 3840 / 2560 / 1920 / 1280 / 1080 / 800 px, or custom),
  - **Width** (px; height follows),
  - **Percent** (e.g. 50 %),
  - **Fit in box** W×H (scale to fit inside, no crop, no padding. Crop/fill to exact ratios belongs to the Instagram presets cluster and reuses this pipeline).
- Aspect ratio is always kept. **Never upscale** by default ("already smaller, skipped" in the card); an "Allow enlarging" checkbox is available.
- **Same format out** by default, with per-format quality from 03b §6.2 (Compact/Balanced/High → JPEG/HEIC/AVIF 0.65/0.85/0.96, WebP via libwebp, PNG lossless + oxipng pass). An optional "Convert to" picker reuses the conversion targets.
- Metadata kept (EXIF date, camera, GPS), with orientation baked in and reset to 1, and pixel-dimension tags updated. A "Remove location" checkbox is offered. ICC profile kept (Display P3 stays P3); a "Web (sRGB)" option converts.
- Output: `<base> Resized.<ext>` beside the original (consistent with `<base> <Suffix>` naming in 10 §8.5, collision rule `… 2`), or "Replace originals (move originals to Trash)" as an opt-in with Undo.
- The card shows "12 resized · 3 skipped (already smaller) · 41.2 MB → 6.8 MB".

### 2.2 Engine choice
- **Decode:** `CGImageSourceCreateThumbnailAtIndex` with `ThumbnailMaxPixelSize = min(source long edge, 2 × target)`, `CreateThumbnailWithTransform`, `FromImageAlways`, `ShouldCacheImmediately`. This is fast and memory-bounded (JPEG/HEIC DCT-domain scaling) and applies EXIF orientation once.
- **Final scale:** `CILanczosScaleTransform` in the job's `CIContext` (or vImage `vImageScale_ARGB8888` with `kvImageHighQualityResampling`) to the exact target. Do not use the thumbnail output directly as the final image (see §2.3).
- **Encode:** existing EngineImage encode path (ImageIO; libwebp for WebP); 16-bit kept where the target allows.
- 0 MB added; all system frameworks.

### 2.3 Evidence (MEASURED, `batch.NKCh/`)
Fixtures were made with ImageIO from the CC0 cat photo (`fixtures.swift`): EXIF `DateTimeOriginal` + `OffsetTimeOriginal`, orientation 6, Display P3 HEIC, a PNG with no EXIF, and a Devanagari filename.
```
./resize long 1280 r1 fixtures/*
./resize width 800 r2 fixtures/IMG_0001.jpg fixtures/IMG_0002.heic
./resize percent 50 r3 fixtures/IMG_0003.JPG
./resize fit 1080x1080 r4 fixtures/IMG_0001.jpg "fixtures/scan 4.png"
./resize long 4000 r4 fixtures/IMG_0003.JPG
```
| Input | Mode | Output (verified by re-reading) |
|---|---|---|
| IMG_0001.jpg 1440×1920 (stored 1920×1440, orientation 6) | long 1280 | 960×1280, orientation 1, sRGB, date kept |
| IMG_0002.heic 1920×1440 P3 | long 1280 | 1280×960, **Display P3 kept**, date kept |
| कुत्ता फोटो.jpg | long 1280 | 1280×960, date kept |
| scan 4.png (no EXIF) | fit 1080×1080 | 1080×810 |
| IMG_0001.jpg | width 800 | 800×1067 |
| IMG_0003.JPG | percent 50 | 960×720 |
| IMG_0003.JPG 1920 px | long 4000 | **skipped (no upscale)** |

The 6-file batch at long 1280 took 1.74 s under load.

Quality (`rq.swift`, reference = ImageMagick Lanczos in linear light, `-colorspace RGB -filter Lanczos -resize`; frame alignment confirmed with RMSE offset search = (0, 0)):
| Photo → 1280 px | ImageIO thumbnail | Core Image Lanczos |
|---|---|---|
| cat (fur, high detail) | SSIMULACRA2 **66.8**, 125 ms | **94.4**, 150 ms |
| plant | 83.7, 121 ms | **92.9**, 320 ms |

The thumbnail output is visibly softer (its PNG is 2.13 MiB vs 2.49 MiB for the Lanczos output at the same size: less detail). **03b §6.1 ("resize via CreateThumbnailAtIndex") should be amended** to the hybrid in §2.2. Compress's "max pixel −15 %" steps (13 §2.6) should use the same hybrid.

### 2.4 Risks
- Very large inputs (≥ 100 MP panoramas, 16-bit TIFF): the hybrid path keeps memory bounded because the thumbnail decode caps at 2× target. The 200 MP decode cap (03b §6.1) still applies.
- Animated GIF/WebP/HEICS: resize every frame (ImageIO frames + delays; libwebp `WebPAnimEncoder`). Otherwise the card warns "first frame only". Not prototyped.
- RAW inputs: decode through `CIRAWFilter` at the target scale (`scaleFactor`), not the embedded JPEG preview. Not prototyped.
- HDR gain maps: when resizing HEIC/JPEG with a gain map, the gain map must be resized too, or it is dropped (I-HDR spike).
- Multi-page TIFF → resize all pages or warn.

### 2.5 Effort, dependencies, phase
- **Effort M:** pipeline S (it is mostly the existing encode path), options popover S, metadata rewrite + verification S, animated/multi-page handling S–M, tests.
- **Dependencies:** EngineImage decode/encode (P1-2x), encode settings (03b §6.2), libwebp (Phase 1/2), tool-options popover infrastructure (Phase 2 tools), Undo log for "replace originals". **Shares its pipeline with** the Instagram/Reels presets and fit-to-size presets (other clusters): build `ResizeSpec` (immutable value: mode, value, allowUpscale, colour, metadata policy) once, and have presets produce `ResizeSpec`s.
- **Phase 2** (alongside Compress images P2-31 and Crop Image).

---

## 3. Batch rename — IMPORTANT

### 3.1 User-facing behaviour
- **Wheel slice "Rename…"** (any files; best with images). A sheet opens over the wheel position:
  - **Pattern field with token chips:** `{name}` (original base name), `{counter}` with digits and start (`{counter:3}` → 001, `{counter:3@10}` → 010), `{date}` with an optional format (`{date:yyyy-MM-dd HH.mm.ss}`), `{ext}` / `{EXT}`, plus free text. Presets: "Date taken + counter" (`{date} {counter:3}.{ext}`), "Name + counter", "Trip name + counter" (text prompt).
  - **Sort order** for the counter: as dropped / name (Finder order, `localizedStandardCompare`) / **date taken** / date modified.
  - **Live preview table:** old name → new name, the date source per row ("EXIF", "EXIF + time zone", "file date" in grey when no EXIF), and a status. Conflicts are shown in red and block **Rename**: duplicate inside the batch, an existing file outside the batch, invalid name (empty, leading dot, > 255 bytes). Unchanged rows are greyed out.
  - **Rename** applies; the HUD card offers **Undo**. History lists the batch.
- **No find-and-replace** in names for now (the owner said "Replace: not needed"). It can be added later as a token-free mode if the owner meant this.
- `{date}` = capture date: EXIF `DateTimeOriginal` (+ `OffsetTimeOriginal` / `SubSecTimeOriginal`) for images, ImageIO for HEIC/RAW, `AVAsset` `creationDate` for videos (extra), else the file creation date (labelled). Dates render in the **capture's own time zone** when the offset is known, so photos taken in Delhi read 09:26 even when renamed in London. (The prototype renders in the Mac's zone; the product must not.)

### 3.2 Engine choice
- Own Swift code in a small `ZivletRename` module (pure planner, no I/O in the planner) + the app process for execution (renaming is not an engine job; nothing is decoded except metadata).
- Name comparison uses **case-folded + NFC keys**, because default APFS is case-insensitive and normalisation-insensitive.
- Execution is **journal first, then two-phase rename** (every file → hidden temp name `.zivlet-rename-<id>-<old>`, then temp → final). This handles swaps (a↔b), cycles and case-only renames. Undo reverses via the journal and refuses files whose inode changed.
- Journal stored as a new `UndoEntry` kind (`rename`) in the existing UndoLog (P1-15; 03a §4.7: 20 batches, 24 h).

### 3.3 Evidence (MEASURED, `batch.NKCh/rename.swift`)
```
./brename preview "{date:yyyy-MM-dd HH.mm.ss}.{ext}" date rn/…
./brename apply "Trip {date} {counter:3}.{ext}" date j1.json rn/…  ; ./brename undo j1.json
./brename apply "{name}.{EXT}" name j2.json rn/IMG_0001.jpg rn/IMG_0003.JPG ; ./brename undo j2.json
```
| Scenario | Result |
|---|---|
| Date pattern; two shots in the same second | Row 3 flagged "DUPLICATE of row 2"; apply refused |
| Target equals an existing file outside the batch ("Trip 2026-03-14 001.jpg") | "EXISTS (not in batch)"; apply refused |
| PNG without EXIF | date via file creation date, labelled |
| Devanagari filename (कुत्ता फोटो.jpg) | renamed and restored correctly |
| Apply 6 files, then Undo | `ls` before and after Undo **identical** (`diff` clean) |
| Case-only rename `IMG_0001.jpg` → `IMG_0001.JPG` on APFS | works (two-phase); Undo restores |
| File renamed, then replaced by a copy before Undo | Undo **skips** it ("changed since rename"), restores the rest |

### 3.4 Risks
- **Crash between phases** leaves `.zivlet-rename-*` hidden files. Mitigation: the journal is written before any move, and recovery runs on next launch (finish or roll back from the journal).
- **iCloud Drive / SMB / FAT:** renames may be slow or case-insensitive differently; FAT forbids more characters (`? * " < > |`). Sanitise per volume (`URLResourceValues.volumeSupportsCaseSensitiveNames`, filesystem type).
- **Sidecar files** (`IMG_0001.AAE`, RAW+JPEG pairs, `.xmp`): rename them together, as an option that defaults to on for same-base sidecars. Not prototyped.
- **Live Photos** (HEIC + MOV pair): renaming breaks Photos' pairing only inside the Photos library, not for Finder files. Rename both together.
- Time-zone correctness (see §3.1).

### 3.5 Effort, dependencies, phase
- **Effort M:** planner + tokens + conflict rules S (prototype exists), execution + journal + recovery S, preview sheet UI M, tests S.
- **Dependencies:** UndoLog (P1-15) new entry kind; History cluster (same journal feeds History); a sheet/window host for tools (Phase 2 tool infrastructure); ImageIO/AVFoundation metadata reading.
- **Phase 2.** (Design 10 had it in Phase 4; the owner's priority moves it up.)

---

## 4. Smaller PNG (lossless optimise + optional colour reduction)

### 4.1 User-facing behaviour
- **"Smaller PNG"** appears as (a) the PNG branch of **Compress** (already planned, P2-31) and (b) a quality option for every **→ PNG** conversion: "Optimise PNG" is on by default (lossless), because ImageIO's PNG encoder is not size-optimised.
- Two levels in the Compress options:
  - **Lossless** (default): oxipng; pixel-identical. Card: "6.1 MB → 3.3 MB (−45 %), no quality change".
  - **Smallest (fewer colours)**: imagequant palette quantisation + oxipng. Card warns "Reduces colours. Best for screenshots, icons and graphics." It is **automatically refused for photos** (imagequant cannot reach quality ≥ 90 with 256 colours) with "This looks like a photo. JPEG/HEIC/JPEG XL will be much smaller", plus a one-click convert.
- Global "never bigger than input" guard (13 §2.6): if the output is not smaller, keep nothing and report "Already optimal".
- Alpha is preserved (premultiplied edges kept by imagequant's alpha-aware palette).

### 4.2 Engine choice
- **oxipng 10.2.1** (MIT; deps `libdeflater` 1.26.1 Apache-2.0 → libdeflate MIT, `zopfli` 0.8.4 Apache-2.0, `rayon`) and **imagequant 4.4.1** (**GPL-3.0-or-later**, compatible with Zivlet's GPL-3.0-or-later; the standalone libimagequant is dual GPL/commercial). Both are in the planned `ZivletRS` static library (P2-10) behind `sat_png_optimize` / `sat_png_quantize` (design 13 §3.2).
- Default oxipng preset **2** (preset 5 gave 5 % more for 2× time); zopfli only for an explicit "Maximum" option.

### 4.3 Evidence (MEASURED, `png.3iUy/`)
Build (scratch `CARGO_HOME`, no global install):
```
cargo build --release   # oxipng 10.2.1 + imagequant 4.4.1 + png 0.18.1; opt-level "s", lto, panic=abort, strip
→ target/release/pngtool  768,448 bytes   (2 min 15 s build)
./pngtool lossless in.png out.png 2      ./pngtool quant in.png out.png 80 98
```
So oxipng + imagequant + PNG codec + zopfli cost **≈ 0.75 MB** of code, well inside the 4–6 MB EST for the whole `ZivletRS` lib.

Baseline = the PNG ImageIO writes (what Zivlet produces today). Quality = SSIMULACRA2 vs the baseline (90+ ≈ visually lossless, 70 ≈ high quality).
| Image | ImageIO | oxipng p2 | oxipng p5 | quant 60–85 + oxipng | quant 80–98 + oxipng |
|---|---|---|---|---|---|
| Retina screenshot 3600×2338 (terminal + dock) | 6,093 KB | **3,323 (−45 %)** | 3,072 (−50 %) | 805 (−87 %), s2 57.1 | 1,687 (−72 %), s2 74.7 |
| Photo 1920×1440 | 4,516 | 3,956 (−12 %) | 3,875 (−14 %) | 1,862 (−59 %), s2 **73.8** | same (max reachable q 87) |
| Alpha cut-out (from §6) | 1,042 | 945 (−9 %) | 945 | 348 (−67 %), s2 85.8 | 349 (−67 %), s2 85.7 |
| Text render (OCR image) | 40 | **15 (−62 %)** | 15 | 9 (−78 %), s2 92.3 | 11 (−72 %), s2 93.9 |
| Flat chart 1600×1000 | 42 | **7 (−83 %)** | 6 (−86 %) | 5 (−88 %), s2 89.3 | 5 (−88 %), s2 90.9 |

Times under heavy load: oxipng p2 on the 8.4 MP screenshot took 30.9 s (p5: 60.3 s). Expect a few seconds on an idle M2 Pro (EST; re-measure in spike I-C1). Small images take well under 1 s.
Also: macOS's own screenshot PNG (6,045 KB) is slightly smaller than ImageIO's re-encode (6,093 KB), so every Zivlet → PNG conversion should get the oxipng pass.

Decision rule from the data: offer lossy only when imagequant reports quantisation quality ≥ 90 at min-quality 80 (graphics, text, charts, most screenshots); refuse and suggest a photo format otherwise.

### 4.4 Risks
- oxipng time on huge PNGs: cap at preset 2 for > 20 MP, run in the CPU lane, cancellable (oxipng supports a timeout/deadline option; wire it to job cancellation).
- imagequant is GPL-3.0+: fine for this project, but it rules out any future non-GPL relicensing of the Rust lib (note in `Acknowledgements` / `cargo-deny` allow-list).
- APNG input: oxipng keeps APNG frames; imagequant must not run on animated PNGs (skip lossy).
- Colour profiles: oxipng keeps `iCCP` by default (strip only with "Remove metadata").

### 4.5 Effort, dependencies, phase
- **Effort S** on top of P2-10 (ZivletRS) and P2-31 (Compress images): photo/graphics gate, options UI, card copy, guard.
- **Phase 2** (as already planned). Expose "Optimise PNG" on → PNG conversions in the same release.

---

## 5. JPEG XL output

### 5.1 User-facing behaviour
- **"JPEG XL" target** in the image conversion wheel (all raster inputs).
  - From **JPEG**: default **lossless transcode**: bit-exact reversible, about 15–19 % smaller, no quality loss. Card: "Lossless: can be turned back into the identical JPEG". Plus a **JXL → JPG (original)** route that reconstructs the original JPEG bytes.
  - From **other formats**: lossy distance 1.0 ("visually lossless") under Balanced, 2.0 under Compact, lossless under High or for PNG graphics.
- Metadata (EXIF/XMP) and ICC carried in JXL boxes.
- A compatibility note on the first use: "JPEG XL opens on macOS 14+/iOS 17+ and Safari; some Windows and web apps cannot open it yet." (Third-party support status is DOC/UNVERIFIED and should be re-checked at ship time.)

### 5.2 Engine choice
- **libjxl 0.12.0** (BSD-3-Clause + PATENTS grant; DOC from 13 §2.4; Homebrew formula reports 0.12.0, BSD-3-Clause). Static build per 13 §2.4 (`JPEGXL_ENABLE_TOOLS=OFF`, `SKCMS=ON` to avoid lcms2, `BUILD_SHARED_LIBS=OFF`), wrapped in a small C-API Swift module `ZivletJXL`: `JxlEncoderAddJPEGFrame` (lossless transcode), `JxlEncoderAddImageFrame` + `JxlEncoderSetFrameDistance` (lossy), `JxlEncoderSetICCProfile`, `JxlEncoderAddBox("Exif"/"xml ")`. Decoding for previews stays in ImageIO; the libjxl decoder is only used for "JXL → original JPEG" (`JxlDecoderSetJPEGBuffer`).
- jpegli (same repo) can come along later for better JPEG output (S-C1, P2 in 13).

### 5.3 Evidence (MEASURED, `jxl.pxR3/`)
ImageIO capability probe (`iio.swift`):
```
public.jpeg-xl        read: true  write: false
org.webmproject.webp  read: true  write: false
public.avif           read: true  write: true
CGImageDestinationCreateWithData(jxl) = nil (cannot write)
UTType(filenameExtension: "jxl") = public.jpeg-xl
```
Every `.jxl` produced below decoded through ImageIO (33–104 ms), so Zivlet can preview and re-convert its own output.

Size of the libjxl stack (Homebrew arm64 dylibs, 0.11.2 installed): libjxl 1.91 MB + libjxl_cms 0.11 + libjxl_threads 0.06 + highway 0.10 + brotli enc/dec/common 0.91 + lcms2 0.36 = **3.28 MB**. A static encoder-focused build with skcms (no lcms2) and dead-stripping should be about 2.5–3 MB (EST).

Compression with `cjxl`/`djxl` 0.11.2 (the reference front-end of the same library) on the four CC0 photos. Quality = SSIMULACRA2 against the decoded source pixels. ImageIO encodes via `enc.swift`:
| Photo | Source JPEG | JXL lossless-JPEG transcode | JXL d1.0 e7 | ImageIO JPEG q0.65 | ImageIO JPEG q0.85 | ImageIO AVIF q0.85 | ImageIO HEIC q0.85 | libwebp q85 |
|---|---|---|---|---|---|---|---|---|
| cat 1920×1440 | 897 KB | **759 (−15 %), bit-exact** | **730**, s2 88.2 | 917, 87.7 | 1,307, 89.4 | 848, 86.3 | 818, 83.2 | 767, 83.0 |
| coffee 1547×1024 | 199 | **162 (−19 %), bit-exact** | **200**, 87.6 | 263, 87.9 | 369, 88.8 | 206, 83.4 | 207, 83.5 | 177, 79.4 |
| plant 1920×2560 | 952 | **796 (−16 %), bit-exact** | **786**, 86.8 | 982, 88.1 | 1,433, 89.1 | 840, 84.3 | 831, 83.8 | 645, 77.3 |
| gray cat 1920×1440 | 621 | **524 (−16 %), bit-exact** | **497**, 87.3 | 630, 88.3 | 917, 89.7 | 556, 85.8 | 544, 84.0 | 476, 79.4 |

"bit-exact" = `djxl out.jxl recon.jpg && cmp src.jpg recon.jpg` identical. At roughly equal quality (s2 ≈ 87–88), JXL d1.0 is **20–24 % smaller than ImageIO JPEG** and beats AVIF/HEIC q0.85 on quality at similar or smaller size. Caveat: the sources were already JPEGs.
JXL lossless on graphics: chart 42 → 4 KB (oxipng 7 KB), text 40 → 12 KB (oxipng 15 KB), alpha cut-out 1,042 → 480 KB (oxipng 945 KB), but the Retina screenshot came out at 4,567 KB vs oxipng 3,323 KB. Lossless JXL is not always better than an optimised PNG.
Times (heavy load): transcode 0.1–1.1 s; d1.0 e7 1.4–6.4 s per 1.6–4.9 MP photo. Use effort 5–6 for batches (EST: much faster at about 1 % size cost; measure in I-C1).

### 5.4 Risks
- **Bundle size:** expected total 68.8 MB vs the 70 MB target (10 §9). +2.5–3.3 MB pushes it to about 71–72 MB. Options: ship JXL only after the Phase 0 hello-DMG measures real headroom; or accept 72 MB (still under the CI gate of 85); or make JXL a signed, notarised optional component (adds complexity). **[OWNER] decision.**
- **Ecosystem compatibility:** a JXL file the recipient cannot open is a support problem. Default stays "keep original", plus the first-use note.
- Hostile-input surface only if the decoder is used (JPEG reconstruction): run it in the worker and add libjxl to the fuzz corpus.
- libjxl API churn between 0.11 and 0.12 (pin the version, CI build from source).

### 5.5 Effort, dependencies, phase
- **Effort M:** vendor build + XCFramework (vendor.yml, P0-37 pattern) S–M, Swift wrapper + metadata boxes S, reconstruction route S, capability probe + catalog pairs S, tests (bit-exact round-trip fixture) S.
- **Dependencies:** vendor pipeline, size gate, catalog/route table (10 §4.14 lists "JPEG XL output | libjxl 0.12 | Phase 4"), engine worker.
- **Phase 3**, gated on the size measurement (moved up from Phase 4 because the owner picked it; it is the lowest of the six image picks in value per MB).

---

## 6. Remove background

### 6.1 User-facing behaviour
- **Wheel slice "Remove Background"** (single or multiple images; zero-click).
  - Output: **`<base> No Background.png`** (alpha). If the source is HEIC or WebP, keep that format with alpha (HEIC/WebP alpha are supported via ImageIO/libwebp); JPEG sources → PNG.
  - All detected subjects are kept by default. Option: "Crop to subject" (tight crop + small margin).
  - Card shows a before/after thumbnail on a checkerboard. "No subject found" is a clear non-error result.
- **Refine (tool window, later):** click a subject to toggle it (`instanceAtPoint`); on macOS 27, tap/box/brush refinement via `GenerateIterativeSegmentationRequest` (design 13 §8.2) behind `#available`.
- **Follow-ups that reuse the mask:** "Add background colour" (feeds the Phase 3 Add BG tool) and "Smaller PNG" on the cut-out (−67 % measured with imagequant at s2 85.8, §4.3).

### 6.2 Engine choice
- **Vision `VNGenerateForegroundInstanceMaskRequest`** (macOS 14+) + `VNInstanceMaskObservation.generateScaledMaskForImage(forInstances:from:)` → soft mask at full resolution → `CIBlendWithMask` over clear → RGBA8 sRGB/P3 PNG. Or `generateMaskedImage(ofInstances:from:croppedToInstancesExtent:)` for the cropped variant.
- 0 MB, on-device. No bundled segmentation model (a good open model such as BiRefNet/RMBG-class would be 40–200 MB and often has non-commercial licence terms; that would break the size principle).

### 6.3 Evidence (MEASURED, `bg.NBNI/`)
**The Swift-native API failed here:**
```
./bgswift-min coffee.jpg
A request.perform(on: cg)       error: requestCancelled("GenerateForegroundInstanceMaskRequest was cancelled.")
B handler.perform(request)      error: requestCancelled(…)
C Task.detached                 error: requestCancelled(…)
D ImageRequestHandler(URL)      error: requestCancelled(…)
(same four failures from inside a signed .app bundle: BgTest.app)
./bgvn coffee.jpg   →  ok 1 instance  2.31 s (first call)
```
VN API results (`bgvn2.swift`, 4 CC0 photos):
| Photo | Request | Full-res mask | Total incl. PNG write | Mask: fully in / out / soft edge | Cut-out PNG |
|---|---|---|---|---|---|
| cat 1920×1440 | 1,406 ms | 385 ms | 2.36 s | 14.2 % / 84.0 % / 1.85 % | 1,042 KB |
| coffee 1547×1024 (white cup on white) | 412 ms | 25 ms | 0.73 s | 52.4 / 46.3 / 1.34 % | 685 KB |
| plant 1920×2560 (ribbon, leaf, tag) | 1,330 ms | 389 ms | 3.77 s | 22.7 / 74.5 / 2.76 % | 2,233 KB |
| gray cat on gray bedding | 1,198 ms | 241 ms | 2.63 s | 17.5 / 81.4 / 1.04 % | 925 KB |

The mask is soft (1–3 % of pixels are partial alpha), not binary. That is good for fur.
Visual inspection (on magenta, `out/*-prev.png`, `out/cat-zoom.png`):
- **Cat:** clean silhouette, ears and tail crisp, fur edge natural; **whiskers outside the silhouette are lost**.
- **Coffee (white on white):** cup and saucer correct, handle hole correctly cut out; a 1–2 px light rim in places.
- **Gray cat on similar-coloured bedding:** a light **halo/fringe** on one side, where background colour bleeds into the soft edge.
- **Plant:** the weakest. Part of the leaf/stake is cut off, a small hole appears inside the stem, and the thin ribbon tail is partly lost. Thin structures and "what counts as the subject" are the main failure mode.

### 6.4 Risks
- **Swift Vision API failure** (above). Use the VN API behind a `ForegroundMasker` protocol; re-test the Swift request on 26.x and later 27.x betas (spike I-V3). `bgvn2.swift` compiles against the macOS 27 SDK with zero warnings (re-checked without filtering), so the VN classes are not marked deprecated there.
- Edge quality: halos on similar backgrounds and lost thin details. Mitigations: optional colour decontamination (pull edge colours from the inner 2–3 px, P2), a 1 px mask erode for hard-edged products (design 13 §8.2), and the macOS 27 refine tool. Be honest in the card ("Check edges").
- Subject choice: Vision decides what the foreground is. Multi-subject photos keep all instances; the picker comes with the refine window.
- First-call latency: 2.3 s cold here (model already prepared). Include it in the Vision warm-up.
- Output size: alpha PNGs are big (0.7–2.2 MB for 2–5 MP); offer "Smaller PNG" in the card.

### 6.5 Effort, dependencies, phase
- **Effort S** for one-tap (request + mask + encode + card + tests); **M** for the refine/picker window.
- **Dependencies:** EngineImage encode with alpha (PNG/HEIC; WebP via libwebp), Vision warm-up shared with OCR, tool window infrastructure for refine, Add BG tool (Phase 3) reuses the mask.
- **Phase 2** for one-tap (moved up from Phase 4; it is cheap and needs 0 MB). **Phase 3/4** for refine (macOS 27 interactive segmentation).

---

## 7. Cross-cutting

### 7.1 Size budget impact (vs 10 §9, expected 68.8 MB)
| Feature | Added to bundle |
|---|---|
| OCR, resize, rename, background removal | 0 MB (system frameworks) |
| Smaller PNG | 0 MB extra: already inside `ZivletRS` (oxipng + imagequant ≈ 0.75 MB MEASURED of the 4–6 MB EST row) |
| JPEG XL | **+2.5–3.3 MB** (the only real cost; owner decision §5.4) |

### 7.2 Shared building blocks (build once)
- `TextRecognizer` (Vision documents request, language order, warm-up) → Copy Text, PDF searchable OCR, Redact Photo.
- `VisionWarmup` (OCR exact config at 64 px + ~3000 px, foreground mask, barcode) at `.utility` QoS after onboarding; flag per OS build.
- `ResizeSpec` + hybrid resampler → Resize, Compress size steps, Instagram presets, fit-to-size presets.
- `UndoEntry.rename` journal → Batch Rename, History, "replace originals" in Resize.
- `ZivletRS` (`sat_png_optimize`, `sat_png_quantize`) → Smaller PNG, every → PNG output, cut-outs.

### 7.3 Changes to existing design docs (proposals, not applied)
1. 13 §8.2 / 10 §5 extras: background removal uses **`VNGenerateForegroundInstanceMaskRequest`** until the Swift request passes I-V3.
2. 13 §8.5 and 14 (App Intent "Extract Text"): language order **`[hi-IN, en-US]`** when Hindi is enabled; no auto-detect default; cold compile can take minutes (update §8.1's 58 s figure).
3. 03b §6.1 decode row: thumbnail to ≥ 2× target, then Lanczos (not thumbnail-only).
4. 10 §12 / 05 backlog: move B4-05 (Remove Background) and B4-09 (Batch Rename) to Phase 2; B4-10 (JPEG XL) to Phase 3 behind the size gate; add Copy Text and Batch Resize as Phase 2 tools.

### 7.4 New spikes
| ID | Question | Pass criterion |
|---|---|---|
| I-V2 | Hindi/Marathi OCR on macOS 26.0/26.x: languages listed, 12 fixtures with `[hi,en]`, cold compile time, warm-up effect | `hi-IN` listed; 12/12 ≤ 1 % CER; first user OCR after warm-up < 3 s |
| I-V3 | Swift `GenerateForegroundInstanceMaskRequest` on 26.x and the next 27.x | Works → switch back; else keep VN |
| I-R1 | Hybrid resize quality/speed on 12–48 MP iPhone HEIC and RAW | SSIMULACRA2 ≥ 90 vs linear Lanczos; ≤ 0.3 s per 12 MP on an idle M1 |
| I-C1 (extend) | Idle-machine timings for oxipng p2 and cjxl e5/e6/e7 | Pick defaults; document |

### 7.5 Recommended phase plan for this cluster
- **Phase 2 (public beta):** Copy Text (first tool), Batch Resize, Batch Rename, Smaller PNG (inside Compress and → PNG), Remove Background (one tap).
- **Phase 3 (1.0):** JPEG XL output + "JXL → original JPEG" (if the size gate allows); background-removal picker.
- **Phase 4 (1.x):** macOS 27 interactive background refine; sidecar-aware rename extras; jpegli.
