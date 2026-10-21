# 10b — Zivlet Technical Strategy: roadmap, spikes and risks (§12–§14)

Part of [10-tech-strategy](10-tech-strategy.md), split out to keep each file under 800 lines. Section numbers are unchanged, so a reference such as "10 §12" points to the matching section below. Bare section references to sections not in this file point to the parent document, whose header defines the evidence tags, `[challenge]` notes and **[OWNER]** markers used here.

---

## 12. Phased roadmap

Effort figures assume one full-time engineer and are **ESTIMATES**.

> [challenge] **The schedule adds up to about 27–33 weeks for one engineer, and that is not credible for this scope.** Phase 3 alone holds: an SDoc model with five writers (DOCX that opens in Word without repair, EPUB passing EPUBCheck, MD, HTML, RTF), the Pages bridge, PDF → DOCX/Pages/PPTX/XLSX/EPUB fusion, 8 editor-heavy tools (Edit, Annotate, Add BG, Collage, Redact Photo and Video, Bleep, Visualizer), App Intents, the CLI and accessibility. Comparable single-developer Mac utilities (Dropover, Yoink, PDF Squeezer-class apps) took a year or more to reach a smaller surface. Plan **12–18 months to 1.0** for one engineer. Or keep the dates and cut 1.0 to Phases 1–2 (221 pairs, 19 tools), with the Phase 3 items as 1.x. That is the honest parity claim. **[OWNER]** (O-18).

### Phase 0: Spikes and skeleton (about 3 weeks)

- Run gate-A spikes (§13): G-0 (macOS 26 re-probe), P-T1–T4, P-W1, P-W2, P-P1, M-1, M-2, M-4, P-C1.
- Skeleton:
  - Xcode project and ZivletKit modules;
  - Catalog with all 275 pairs as data;
  - `vendor.yml` producing the FFmpeg artifact;
  - unsigned CI green;
  - signed + notarized "hello" DMG with helpers, and a Sparkle N-1 → N update on a clean VM.
- **Exit:** trigger works permission-free from Finder on 26.x; the notarized DMG with ffmpeg passes `spctl`; a Sparkle update installs.

### Phase 1: MVP slice, private alpha 0.1 (about 6–8 weeks)

| Area | Scope |
|---|---|
| Trigger + wheel | Hybrid trigger, glass wheel and Solid theme, mode switching, re-tap and hub cancel, haptics and sound, onboarding practice drag, TCC pre-prompts |
| Conversions (**153 pairs**) | raster images 49 (IIO, WEBP, QZ), audio 56, video 42, GIF 6 (FF) |
| Actions (5) | AirDrop, Copy, Move, Copy Path, Terminal |
| Runtime | Scheduler + lanes, staging + `RENAME_EXCL`, naming, HUD + result card with Undo, orphan reaper, capability probe, diagnostics |
| Release | Sparkle stable channel, GPL source bundle, licence and signature gates, size gate |

**Exit:**
- 153 pairs green on the matrix (including WebM playable);
- tap → wheel p95 ≤ 16 ms at 120 Hz;
- zero permission prompts other than the TCC folder prompts;
- crash-free on the hostile media corpus (ffmpeg runs out of process).

### Phase 2: Breadth, public beta 0.5 (about 8–10 weeks)

| Area | Scope |
|---|---|
| Conversions (+68 → **221**) | SVG 8 (Rust lib), PDF → jpg/png/txt/md 4, spreadsheets 21 (SJS + zivlet-js), PPTX 3 (PPTR + RenderHost), subtitles 4, archives 9 (LA) = 49. Documents 19, using the SDoc core with only the txt/md/html/epub writers plus WKP: docx → pdf/png/jpg (DXP) and txt/md/html/epub (MAM) = 7; md → txt/html/epub/pdf/png/jpg = 6; txt → md/html/epub/pdf/png/jpg = 6. |
| Tools (**19 of 27**) | Compress (all kinds), Metadata (ExifTool + Perl + ffmpeg + qpdf), Crop Image, Normalize, Remove Audio, Trim Video, Split PDF, Organize, Extract, Create PDF, Merge, Crop Video, Speed, Join, Snapshots, Split Video, Trim Audio (+ silence), Channels, Read QR |
| Actions | Float shelf (6 of 6) |
| Platform | `ZivletWorker.xpc` with crash-retry; Services menu entry; beta channel |
| Extras | video → m4a, animated WebP, AV1 option |

Pair accounting: 153 (Phase 1) + 49 + 19 = **221**. Phase 3 then adds the remaining **54**:
- docx → pages 1;
- md → docx/pages 2;
- txt → docx/pages 2;
- pages 8;
- rtf 9;
- rtfd 9;
- textClipping 9;
- epub 6;
- pdf → docx/pages/pptx/xlsx/epub 5;
- ppt 3.

That makes 221 + 54 = 275. Exit is measured per pair, not by the headline number.

**Exit:** every Phase 2 route passes its matrix and fidelity bars (D-SHEET, D-RENDER for PPTX, I-S1, I-A1, I-M1, I-M2, plus EPUBCheck with 0 errors for EPUB output); the worker isolates a crash on a hostile PDF or ZIP.

### Phase 3: 1.0 parity (about 10–12 weeks)

| Area | Scope |
|---|---|
| Conversions (→ **275**) | Remaining documents (pages, md, rtf, rtfd, textClipping, txt, epub → all; docx → pages), PDF → docx/pages/pptx/xlsx/epub (FUS), PPT 3 via LO or Keynote (Tier 2 runner, download card, engines manifest), iWork bridge (opt-in) |
| Tools (**27 of 27**) | Edit Photo, Annotate, Add BG, Collage, Redact Photo, Redact Video, Bleep, Visualizer |
| Platform | App Intents (Convert, Compress, Strip Metadata, Run Tool, Read QR, Extract Text, Images → PDF, Merge PDFs), `zivlet` CLI + Homebrew cask, Settings complete (per-format defaults, document fidelity, engines, advanced), accessibility (VoiceOver keyboard-mode wheel, Reduce Motion and Transparency), keyboard path (Services + optional hotkey) |
| Language | English at 1.0 **[OWNER]**; strings catalogued for localisation |

**Exit:** all 275 pairs, 27 tools and 6 actions pass nightly on a clean macOS 26.x VM (PPT with LibreOffice installed); the release checklist and real-drag QA matrix pass; the size gate passes.

### Phase 4: Beyond parity, 1.x

- **Fidelity:** warm LibreOfficeKit helper (D-LO); styled XLSX → PDF via umya-spreadsheet; HDR gain-map round trip.
- **Speed:** argv "Copy command" debug item; VMAF-calibrated VT presets (M-3).
- **Tools:** Remove Background; Make PDF Searchable; PDF Protect, Unlock, Optimize and Fast Web View; QR generate; Batch Rename; JPEG XL output; jpegli; subtitle time shift and fps conversion; ASS/SSA input; 7z/xz/zst/iso inputs; 7z and AES-ZIP creation.
- **UX:** pinned presets and fit-under-size targets (Discord 10 MB, Gmail 25 MB); hover-to-preview size estimates; customisable wheels; Finder Sync menu; opt-in Finder-selection hotkey; 10 languages.

### Phase 5: 2.x

- MuPDF true redaction (gate) **[OWNER]**.
- Sandboxed worker with file-descriptor passing (P-8).
- Transcribe → SRT/VTT.
- Foundation Models "describe what you want".
- Raycast extension and MCP server over the CLI.
- gifski or our own high-quality GIF palette.
- Pandoc pack, if corpus scores lag.

---

## 13. Consolidated spike plan (renamed by prefix, R-13)

| Gate | ID (was) | Question | Pass bar |
|---|---|---|---|
| **A: before Phase 1** | G-0 (13 S-0, 11 S-7, 12 note) | Re-run every PROBED/MEASURED table on macOS 26.0 and 26.x: ImageIO UTIs (AVIF write), Vision requests, the ffmpeg encoder list, the WKWebView print path | Same results, or a documented fallback is switched on |
| | P-T1 (14 S-T1) | Mouse monitors fire during Finder, Mail, Safari and Chrome drags, with no prompt | events seen, no TCC entry |
| | P-T2 (S-T2) | `flagsChanged` delivered without permission | edges < 2 ms |
| | P-T3 (S-T3) | Esc Carbon hotkey while Finder owns the drag | wheel closes, drag continues |
| | P-T4 (S-T4) | End-to-end latency | p95 ≤ 16 ms (120 Hz) |
| | P-W1, P-W2 | Glass highlight and morph in a transparent panel | no > 2-frame hitches; GPU < 10 % on M1 |
| | P-P1 (S-P1) | Which locations prompt when writing a sibling, from the app **and** from a spawned ffmpeg | documented table + onboarding copy |
| | M-1 (11 S-1) | Real stripped size of the FFmpeg build | ≤ 30 MB |
| | M-2 (S-2) | Does Xcode Code-Sign-On-Copy set runtime + timestamp on helpers and dylibs? | decide script vs phase |
| | M-4 (S-4) | swift-subprocess 1.0.2 teardown, process group and QoS under Swift 6 | works, or fall back to `Foundation.Process` |
| | P-C1 (S-C1) | Full CI dry run: sign, notarize, staple, DMG, delta update | Gatekeeper passes on a clean VM |
| **B: before Phase 2** | I-M1, I-M2 | Trimmed Perl module set, size, notarization of XS bundles; ExifTool throughput | < 6 MB; ≥ 20 files/s; no leaks over 1,000 jobs |
| | I-A1 | libarchive hostile corpus | all refused or contained |
| | I-S1 | resvg vs WKWebView on 500 SVGs | ≥ 97 % equal |
| | I-PDF1, I-PDF2, I-PDF3 | PDFKit render robustness; what Quartz-filter rewriting drops; OCR text-layer save | < 1 % failures; documented drop list; extractable text |
| | D-SHEET | SheetJS scale and correctness | 100 % values; 2 M cells < 15 s |
| | D-RENDER | pptx-renderer vs PowerPoint (+ @silurus legacy PPT) | median SSIM ≥ 0.80; ≤ 2 s per 30 slides |
| | D-JS (new) | `zivlet-js` JSContext with polyfills: SheetJS, mammoth and cupertino-files run; speed with and without `allow-jit` | all pass; warm call < 50 ms overhead |
| | M-3, M-5, M-6 | VT preset calibration; SVT-AV1 still AVIF; AIFF/WMA cover art | defaults chosen; fallbacks verified |
| | M-COPY (new) | Per-stream copy + re-encode A/V sync across the video pairs | drift ≤ 1 frame |
| | M-META (new) | `-map_metadata -1` vs ExifTool on QuickTime Keys/GPS | no GPS left |
| | P-T5 | Promise drags (Mail, Photos, Safari, Chrome, Arc, Firefox) | works or listed as unsupported |
| | P-X1 | Services entry + shortcut opens keyboard mode | no prompt |
| | I-V1 | Vision cold start on 26 + warm-up | first OCR < 3 s after warm-up |
| | P-TERM (new) | Each listed terminal opens a directory URL | supported list finalised |
| **C: before Phase 3** | D-DOCX | docx-preview + print vs Word on 40 files | page delta ≤ 1; SSIM ≥ 0.85; recall ≥ 99 % |
| | D-PAGES | cupertino-files round trip on 20 docs | opens in Pages without repair |
| | D-PDF | Vision + PDFKit fusion on 40 PDFs | recall ≥ 98 %; table F1 ≥ 0.8 |
| | D-WRITERS | DOCX/EPUB/MD/HTML writers vs Pandoc oracle | 0 EPUBCheck errors; 0 repair prompts |
| | D-LO | LO download, verify, install, batch convert | install < 3 min; batch works |
| | P-CLI (new) | CLI hands WebKit routes to the app | works headless-ish (app hidden) |
| | P-X2, P-W3, P-W4 | Shortcuts folder triggers; edge-of-screen layout; UI-sound setting key | works or claim removed |
| **Post-1.0** | P-8 (11 S-8) | Sandboxed worker with FD passing | prototype |
| | M-9, I-HDR, I-C1 | AVPlayer VP9 via supplemental decoder; HDR gain maps; jpegli/libavif A/B | adoption decisions |

> [challenge] **Spikes added or changed by 15-strategy-challenge:**
>
> | Gate | ID | Question | Pass bar |
> |---|---|---|---|
> | A | G-0 (extended) | Also run with `defaults write -g EnablePasteboardPrivacyDeveloperPreview -bool yes` on 26.x and 27.x: does reading **file URLs from `NSPasteboard(name: .drag)` at tap time** prompt? | no alert. If it does, use provisional petals plus a refine in `draggingEntered` (14 R2) |
> | A | P-T1 (extended) | Wake-up cost of a global `leftMouseDragged` monitor with a 1 kHz gaming mouse during ordinary (non-file) drags | monitor removed after the first event of each drag; < 1 % CPU on M1 |
> | A | P-T6 (new) | Drop accepted while ⌃ / ⌘ / ⌥ is still held at release (operation-mask negotiation, §2.1 note) | drop accepted in Finder, Mail, Safari and Chrome; source never moved or deleted |
> | A | P-CI (new) | Self-hosted Tart host with 26.0 / 26.x / 27.x clean images (§8.10 note) | `spctl` + Sparkle + probe jobs green |
> | B | D-PAGES (moved from C) | cupertino-files round trip on 20 docs | as before; failing moves Pages output to iW-only and Pages input to the preview fallback |
> | B | D-PRINT2 (new) | Two concurrent `printOperation` runs on the main thread | 200 × 2 runs correct and distinct; else render width stays 1 |
> | B | D-XLSX-STYLE (new) | umya-spreadsheet styles → HTML print vs Excel PDF on 30 styled workbooks | fills, fonts and borders present; SSIM ≥ 0.85 |
> | B | M-COPY (extended) | Every copied stream into MP4/MOV opens in AVFoundation on M1 (no AV1 HW) and M3+ | `isPlayable` true on both |
> | B | M-HOSTILE (new) | HLS/ffconcat disguised inputs, plus the `-format_whitelist` policy | refused, no file read outside the input |
> | C | M-REDACT (new) | sendcmd/mask-pipe redaction throughput | 10 min 1080p, 3 tracks ≥ 1× realtime |

---

## 14. Consolidated risk register

| # | Risk | L / I | Mitigation | Owner doc |
|---|---|---|---|---|
| X1 | Probes ran on macOS 27, and 26.x behaves differently (AVIF write, Vision APIs, print path) | Med / High | G-0 first; every capability is probed at runtime; documented fallbacks (SVT-AV1 AVIF, `RecognizeTextRequest`) | all |
| X2 | Apple puts mouse monitors or the drag pasteboard behind TCC | Low / High | Trigger isolated behind `InputSampler`; fall back to polling, then an opt-in Input Monitoring tap; re-run on every beta | 14 |
| X3 | Notarization fails on nested code (dylibs, Perl XS bundles, helpers) | Med / Med | Explicit inside-out signing script and signature gate; `notarytool log` on failure; M-2, I-M1 | 11, 13, 14 |
| X4 | Build upkeep across about 20 native upstreams and FFmpeg major bumps | Med / Med | One `versions.lock`, cached vendor artifacts, automated bump PRs, FFmpeg 8.1.x fallback branch, reproducibility diff | 11, 13 |
| X5 | Young single-maintainer JS libraries (pptx-renderer, cupertino-files) break or stall. *[challenge: raised to **High / High** for cupertino-files. On GitHub (2026-10-20) it is **4 stars, created 2026-07-30, about 2.5 months old**, and the commit log is mostly AI-agent-authored (155 of about 243 commits). Yet it carries **16 pairs**: pages → 8 and * → pages 8. pptx-renderer: 131 stars, created 2026-02, one maintainer. Mitigations: D-PAGES moves to gate B; Pages input falls back to the package's `preview.jpg` / `QuickLook/Preview.pdf` with a notice; Pages output is offered through iW (Pages app, often preinstalled) when the D-PAGES bar fails; @silurus/ooxml (849 stars, very active, MIT) is evaluated as a second PPTX renderer in D-RENDER.]* | Med / High → **High / High** | Pinned vendored builds with hashes, corpus + SSIM gates, LO/Keynote fallbacks, budget to fork (Apache/MIT) | 12 |
| X6 | DOCX pagination without break hints is approximate | High / Med | Print-driven pagination, "Layout approximated" label, Automatic mode prefers LO when present | 12 |
| X7 | Bundle size over target | Med / Low | Size gate; shared engines framework; font trim (R-9); optional packs as a last resort | 9 |
| X8 | Unsandboxed app parses hostile files with user privileges | Low / High | Worker isolation, helpers out of process, limits, fuzzing, fast security updates; sandboxed worker post-1.0 | 11, 13, 14 |
| X9 | TCC folder prompts in the middle of a conversion confuse users | High / Med | Onboarding explains and pre-triggers them; card copy; P-P1 | 14 |
| X10 | Quartz-filter PDF compression drops forms, signatures or tags | Med / Med | Pre-flight detection, lossless-only qpdf mode, v2 qpdf recompressor | 13 |
| X11 | ImageIO metadata writes silently do nothing (HEIC, PSD) | High / High (privacy) | ExifTool only, verify every write, fail closed | 13 |
| X12 | Vision first-run model preparation (about 58 s) | High / Med | Background warm-up, "Preparing text recognition…" state | 13 |
| X13 | VP9 software encoding is slow | High / Low | `-cpu-used 5`, ETA, AV1 option, swVideo width 1 | 11 |
| X14 | Sparkle key loss or leak | Low / Critical | Offline backup, protected environment, signed feed | 14 |
| X15 | PPT parity depends on an 805 MB optional engine | High / Low | Clear slice state + one-click install; Keynote alternative; @silurus experiment | 12 |
| X16 | GPL source obligation missed on a release | Low / High | `source-bundle.sh` is a release-blocking step; appcast links the source | 10 |
| X17 | `/usr/bin/perl` removed, or bundled Perl CVEs | Low / Med | Bundled Perl primary, tracked releases, system Perl as fallback | 13 |
| X18 | Glass performance in a transparent panel on 8 GB Macs | Med / Med | One container, ≤ 12 petals, pre-warm, Solid theme as automatic fallback | 14 |
| X19 | Orphaned children after an app crash | Med / Low | Process groups + PID files reaped at launch | 11, 14 |
| X20 | x264 patent exposure | Low / Med | VT default; one-flag removal | 11 |

