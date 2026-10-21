# 01 — Zivlet Product Requirements Document

Date: 2026-10-20. Status: **draft for owner review**. Supersedes product spec Part B where they differ.

**Roadmap additions (approved 2026-10-21):** FR-90…FR-141, NFR-21…NFR-24, the scope edits to §3.2, §6.2–§6.9, §10
and FR-20/39/73/88, and new success metrics are in [01b-prd-additions.md](01b-prd-additions.md). Where they differ,
01b wins.

| Field | Value |
|---|---|
| Product | Zivlet: free, open-source macOS file converter driven by a drag + modifier-tap radial wheel |
| Licence | GPL-3.0-or-later (O-1), DCO contributions (O-2) |
| Platform | macOS 26.0+, Apple silicon (arm64-only, O-13), Swift 6.4 strict concurrency, Xcode 27 |
| Distribution | Direct download, Developer ID, notarized, **not sandboxed**, Sparkle 2 updates |
| Bundle id | `app.zivlet.Zivlet` (placeholder, O-10) |
| Inputs | [00-decisions](../design/00-decisions.md), [10-tech-strategy](../design/10-tech-strategy.md) (and its `[challenge]` notes), [14-app-platform](../design/14-app-platform.md), [15-strategy-challenge](../design/15-strategy-challenge.md); earlier product and competitive notes (not published) |

Conventions:
- "Reference app" = the commercial gesture-driven Mac file converter whose public behaviour inspired Zivlet (named once in the README). Its observable behaviour is a baseline only. Zivlet is a clean-room design: no code, assets, sounds, icons, screenshots or copy are reused; no Open-Tangerine code is reused.
- Evidence keys: `TS§n` = 10-tech-strategy section, `R-n` = 10-tech-strategy reconciliation row, `C-n` = 15-strategy-challenge finding, `G-0` and `P-x/M-x/D-x/I-x` = spike ids (TS§13). Rows without a public source state Zivlet's own spec.
- Phase ids: **P0** spikes/skeleton, **P1** private alpha 0.1, **P2** public beta 0.5, **P3** 1.0 parity, **P4** 1.x, **P5** 2.x. "1.0" is used only at full parity (O-18).
- MUST/SHOULD per RFC 2119. All numbers are Zivlet's own targets.

---

## 1. Problem

| # | Problem | Evidence |
|---|---|---|
| PR-1 | Converting a file on a Mac means opening an app or uploading to a website, picking a format, saving, finding the output. Most jobs are "5-second tasks". | Public user feedback |
| PR-2 | The existing gesture-driven converter (the reference app) is paid after a free quota, closed source, sandboxed (per-folder grant dialogs) and has shipped hidden routes (e.g. WebM). | Public listing and reviews |
| PR-3 | A polling drag trigger costs energy at idle and adds latency; without a permission-free cancel and a progress window that really stops work, users lose control. | 14 §1.3 |
| PR-4 | Free alternatives are unsigned, cross-platform toolkits without the native wheel, or partial clones. | Public survey of alternatives |
| PR-5 | No auditable, offline, automatable (Shortcuts, CLI) gesture converter exists for macOS. | Zivlet goal G7 |

## 2. Target users

| Persona | Typical jobs | Needs | Priority |
|---|---|---|---|
| U-1 Everyday Mac user | HEIC → JPG, MOV → MP4, PDF → JPG, ZIP extract | Zero setup, no prompts, result beside the file, Undo | Primary |
| U-2 Creator / marketer | Compress video for chat limits, GIF/WebP, trim, snapshot, collage, add background | Speed, presets, size targets, quality report | Primary |
| U-3 Developer / power user | WebM/Opus/AV1, metadata strip, Copy Path, Terminal, CLI, Shortcuts | Correct codecs, scripting, open source, keyboard path | Primary |
| U-4 Privacy-sensitive user | Redact photo/video, strip GPS, bleep audio | Fully offline, verifiable, fail-closed metadata | Secondary |
| U-5 Office/document user | DOCX ↔ PDF, Pages, spreadsheets, EPUB | Fidelity, no Office install required | Secondary |
| U-6 Accessibility user | Any of the above without a mouse drag | VoiceOver-operable wheel, Reduce Motion/Transparency | Secondary (P3 must) |

## 3. Goals and non-goals

### 3.1 Goals

| # | Goal | Measured by |
|---|---|---|
| G1 | Feature parity with the reference app's public feature set: 275 pairs, 27 tools, 6 actions | FR-47…FR-73, nightly pair matrix |
| G2 | Same or faster zero-click flow; never add a step to the default path | NFR-1, NFR-2 |
| G3 | Every advertised route works (no hidden/broken slices) | NFR-11 |
| G4 | Zero permission prompts beyond macOS folder (TCC) prompts in the default flow | NFR-3 |
| G5 | Offline, no telemetry, auditable | NFR-5, NFR-6 |
| G6 | Small install (≤ 70 MB) | NFR-7 |
| G7 | Automation surfaces: Services, App Intents, CLI, keyboard mode | FR-84…FR-89 |
| G8 | Accessible from 1.0 | NFR-14 |

### 3.2 Non-goals

| # | Non-goal | Reason |
|---|---|---|
| NG1 | Mac App Store build, sandboxing, StoreKit | 00-decisions |
| NG2 | Trial, paywall, accounts, analytics, ads | 00-decisions |
| NG3 | macOS < 26, Intel | 00-decisions, O-13 |
| NG4 | Cloud or server-side processing | Privacy promise |
| NG5 | Writing RAR, decrypting DRM, encrypted RAR | Licence/legal; TS§0 |
| NG6 | Bundling LibreOffice, Java, Pandoc | Size; TS R-1 |
| NG7 | Becoming a workspace (editor suite, library manager) | Positioning |
| NG8 | Usage-based slice reordering | Breaks muscle memory |
| NG9 | Binding bare Enter in Finder | Finder rename conflict |
| NG10 | Localisation beyond English at 1.0 (strings catalogued) | O-15 |

## 4. Product principles

1. Drag, tap, drop. No modal window in the convert path; tool windows only for tools that need input.
2. Never touch the original. Outputs are new files; sources are never overwritten, moved or deleted (except the Move action, which is undoable).
3. Show only what works. A slice exists only if its engine is present and passes the capability probe.
4. Explain every refusal. No silent no-ops.
5. Local and verifiable. No network in the processing path.
6. Immutable value types end to end (request → plan → result), pure core logic, AppKit at the edges.

---

## 5. Core interaction

### 5.1 Flow

| Step | User | Zivlet | Key requirement |
|---|---|---|---|
| 1 Drag | Starts dragging files (Finder, Desktop, Mail, Photos, browser, Electron app, shelf app) | Wakes on the first `leftMouseDragged`; checks drag pasteboard `changeCount` + file types; starts a display-synced sampler | FR-1, FR-2, FR-13 |
| 2 Tap | Taps ⇧, ⌘ or ⌃ (configurable) | Wheel appears centred on the cursor on the next frame | FR-3, FR-18, NFR-1 |
| 3 Aim | Moves over a slice; may tap another key to switch wheel, or re-tap to close | Highlight + haptic + tick; hub shows slice name | FR-21, FR-22, FR-6, FR-7 |
| 4 Drop | Releases on a slice | Drop accepted, wheel hides, job admitted, HUD shown | FR-29, FR-31 |
| 5 Result | — | Output staged then published beside the original; result card with Undo / Reveal / Open | FR-34…FR-40 |

### 5.2 Key bindings

| Gesture | Zivlet | Note |
|---|---|---|
| Tap ⇧ during file drag | Conversion wheel | Default (O-16) |
| Tap ⌘ | Tools wheel | Default |
| Tap ⌃ | Actions wheel | Default |
| ⌥ alone, unbound combos (⇧⌘…) | Ignored; current wheel unchanged | Exact-mask match |
| Tap a different bound mask while open | Switch in place, same anchor, highlight cleared, glass morph | D-10 |
| Re-tap the active mask | **Close wheel**; drag continues as a normal drag | D-4 |
| Release the key | Wheel stays open until drop or close | — |
| Mask held before the drag started | **Ignored until released and pressed again** | D-3: avoids Finder ⌘-move / ⌥-copy drags opening wheels |
| Esc while wheel visible | Closes wheel, drag continues (Carbon hotkey registered only while visible, if P-T3 passes; else opt-in Input Monitoring toggle) | D-11 |
| Remap | 3 masks from the 15 non-empty ⌃⌥⇧⌘ combos, pairwise distinct; any wheel may be Disabled | FR-11 |

### 5.3 Trigger state machine

```
idle   ─ leftMouseDown ─────────────────────────────▶ armed   (snapshot drag changeCount, held mask)
armed  ─ leftMouseDragged ∧ changeCount moved ∧ file types ─▶ live    (start vsync sampler, drop dragged-monitor)
armed  ─ leftMouseUp ───────────────────────────────▶ idle
live   ─ rising edge of bound mask (not held at start, > 40 ms after live) ─▶ wheel(mode)
wheel  ─ rising edge of another bound mask ─────────▶ wheel(other)   (in place)
wheel  ─ rising edge of same mask | Esc | Space change ─▶ live  (wheel hidden, drag continues)
wheel  ─ drop on slice ─────────────────────────────▶ dispatch → idle
wheel  ─ drop on hub / dead zone ───────────────────▶ refused (snap back) → idle
wheel  ─ pointer leaves panel ──────────────────────▶ wheel stays (anchored); hidden 150 ms after draggingExited if button up
any    ─ button up (sampler or 2 Hz watchdog) ──────▶ idle  (sampler stopped within 1 frame)
```

The machine is a pure `step(InputSample) -> [TriggerEffect]` in `ZivletTrigger` with no AppKit import (FR-10).

### 5.4 Thresholds and timings

| Parameter | Zivlet | Source |
|---|---|---|
| Idle detection | Global + local mouse monitors; **0 timer wakeups** | TS§2, 14 §1.3 |
| Sampling while live | Display link of the cursor's screen (120 Hz ProMotion / 60 Hz) | 14 §1.3 |
| Tap → first wheel frame | p95 ≤ 16 ms @120 Hz, ≤ 33 ms @60 Hz | NFR-1 |
| Tap edge | Rising edge (key down), exact mask | — |
| Drag-start debounce | 40 ms | 14 §1.3 |
| Drag liveness | `changeCount` moved since mouse-down + file/promise types | — |
| URL read for petals | Once per `(changeCount, mode)`, off main, ≤ 64 items, `contentType` only | C-20 |
| Panel fade-in | 70 ms ease-out fade; petals expand from r 50.4 over 200 ms, curve (0.18, 0.82, 0.24, 1) [critic3: aligned with 03a §2.7] | 03a §2.7 |
| Highlight change | ≤ 1 frame to tint; 120 ms snappy ease | 03a §2.7 |
| Mode morph | 280 ms spring, bounce 0.15 | 14 §2.3 |
| Hide after drop | 100 ms accepted pulse + fade; never delays the job | D-9 |
| Leave grace | `draggingExited`/`concludeDragOperation` + 150 ms | D-6 |
| Highlight hysteresis | 3° past a sector boundary | 03a §2.4 |
| Reduce Motion | Springs → 80 ms opacity fades | 14 §2.3 |
| Tick sound | Original 20–40 ms sample, system-sound API, at most one per 35 ms, requests older than 150 ms dropped, muted if system UI sounds off [critic3: 03a §2.7 value; was 30 ms] | 03a §2.7 |
| Haptics | Slot change `.alignment` (`.now`), mode switch `.levelChange`, drop `.generic` | 14 §2.4 |
| Watchdog | 2 Hz `pressedMouseButtons` in `pressed`/`passive` only; `live` and `wheel` read the button every display frame [critic3: 03a §1.5] | 14 §1.3 |

### 5.5 Wheel geometry and layout

Zivlet's standard disc is sized for a familiar target-acquisition feel; the hit model is Zivlet's own (§5.6). [critic3] Standard values are the 03a §2.2 spec; the earlier rounded values (42/48/120/126, panel 320, slack 148) disagreed with 03a, 05 P0-24 and M1 Task 7 and were replaced.

| Element | Standard | Large (accessibility, P3) |
|---|---|---|
| Hub radius (cancel zone) | 42.24 pt | 52 pt |
| Petal inner radius | 48.64 pt | 60 pt |
| Petal outer radius | 119.52 pt | 150 pt |
| Backdrop ring outer radius | 125.92 pt (Ø 251.84) | 158 pt |
| Gap between petals (constant width) | 4 pt (visual only) | 5 pt |
| Active outer slack | to r 150 pt (+30.48 beyond petal outer) | +32 pt |
| Panel | 372 pt square, transparent, no shadow (covers the r 150 hit area plus 1.05 highlight scale) | 400 pt |
| Label radius | 84.53 pt | 105 pt |
| Highlight scale | 1.05 (petal pops outward) | 1.05 |
| Max petals | 12 (size constant; no paging) | 12 |

| Layout rule | Value |
|---|---|
| Order | Catalog order (parity petal order). Slice 0 centred at 12 o'clock, clockwise. n = 3: first slice at 9 o'clock. n = 1: full ring. n = 2: top/bottom halves. |
| Conversion petals | Format label only (e.g. "WEBP", "GZIP" for gz) |
| Tool/action petals | SF Symbol + short label |
| Hub idle label | One file: size. Several: "N files · total size" |
| Hub hover label | Full slice name ("WebP", "Compress", "Copy Path") |
| Anchor | Hub centre = cursor at tap; never follows the pointer; stays put across displays |
| Edges | Hub stays under the cursor; petals rotate/compact so every label is on-screen (FR-24) |
| Theme | Liquid Glass petals in one `GlassEffectContainer`; highlight tinted with the Zivlet accent (own token, design doc). **Solid** theme for Reduce Transparency / Increase Contrast or by choice. |

### 5.6 Hit-testing

| Zone | Definition | Highlight | Drop result |
|---|---|---|---|
| Hub | r < 42.24 pt | none; hub shows "Cancel" | Refused, icon snaps back (explicit cancel) |
| Petal sector | 42.24 ≤ r ≤ 150 pt; sector boundaries at mid-gap, so gaps belong to the nearer slice | that slice (3° hysteresis) | Accepted |
| Disabled slice | sector of a slice marked unavailable for this selection | dimmed, reason in hub | Refused |
| Panel outside active ring | r > 148 pt inside panel | none | Refused (snap back) |
| Outside panel | — | none | Normal drop on whatever is underneath; Zivlet uninvolved |

Slot index: `a = (base − atan2(dy, dx)) mod 2π`, `base = π` if n = 3 else π/2, `slot = round(a / (2π/n)) mod n`, then hysteresis against the current slot.

### 5.7 Drop and dispatch

| Case | Behaviour |
|---|---|
| Operation negotiation | Return the first of `.copy, .generic, .link, .move` in the source mask; always copy semantics; never act on the negotiated operation destructively (C-8) |
| Drop acknowledged | `performDragOperation` returns in ≤ 1 ms; file reading/promise receipt happens after return |
| URL set changed since wheel built | Re-validate; if invalid, refuse with reason in HUD |
| Conversion | Job per input → HUD |
| Windowless tool (Remove Audio, Split PDF, Extract, Create PDF, Read QR) | Runs with defaults |
| Window tool, 1 file | Tool window opens at the wheel location, app activated |
| Single-file tool with several files | Not offered (filtered); if reached by a stale selection, explained, never a silent no-op |
| Action | Runs in the app immediately (or opens its picker) |
| Promise drag (Mail/Photos/browser) | Files received into staging, outputs go to the fallback folder, stated on the result card |

### 5.8 Result

| Surface | Spec |
|---|---|
| HUD | Non-activating panel near the drop point, cascades 24 pt per concurrent batch. Title "Converting to WEBP" or tool verb ("Trimming video"). Line 2: "name · i of n · pct%" (monotonic) → "n of m saved · k failed". Determinate when duration/pages known, else indeterminate + bytes written. **Cancel** button stops work (FR-41). Updates ≤ 10 Hz. |
| Result card | Replaces HUD on success: thumbnail, before → after size, **Undo**, Reveal, Open, Copy, drag-out of the output. Auto-dismiss 4 s unless hovered. Failures stay with per-file reason, Show details, Retry. |
| Finder reveal | One reveal per batch selecting outputs (setting "Reveal results in Finder", default on) |
| Naming | §5.9 |
| Location | Beside the original; fallback `~/Downloads` (configurable) for read-only volumes and promise drags; the card says where |
| Undo | Moves the batch's outputs to the Trash; Move action reverses moves. Recent results (last 20) in the menu. |

### 5.9 Output naming

| Kind | Rule | Example |
|---|---|---|
| Conversion | `<base>.<newext>`; compound `.tar.gz`/`.tgz` stripped as one; gz target writes `.tar.gz` | `IMG_1.heic` → `IMG_1.jpg` |
| Tool | `<base> <Suffix>.<ext>` | `clip Trimmed.mp4` |
| Multi-input tool | `<first base> <Suffix>.<ext>` in the first file's folder | `a Merged.pdf` |
| Folder output | `<base> Pages/Page 001.<ext>`, `Clips/Clip 001`, `Extracted`, `Sheets`, `Slides/Slide 001`, `Snapshots/Frame 001 - 12.345s.png` | — |
| Collision | Finder style `name 2.ext`, `name 3.ext`; names reserved across concurrent jobs; `renamex_np(RENAME_EXCL)` is ground truth (case-insensitive APFS safe) | `IMG_1 2.jpg` |
| Suffix names | Parity suffix names (03a §4.4) except deliberate differences D-21 | — |

### 5.10 Empty and refusal states (own copy)

[critic3] M1 implements the pill text in `EmptyReason.message` (06d 7c) without key glyphs, because bindings are configurable; the shell appends the current binding hint (for example "⌘ Tools · ⌃ Actions"). All copy is Zivlet's own; no strings are taken from the reference app.

| Condition | Wheel shows (status pill in place of petals) |
|---|---|
| No conversions for this format | "No conversions for this file type. ⌘ Tools · ⌃ Actions" |
| Mixed families | "These files can't share a format. Convert one kind at a time." |
| Plain folder on Convert/Tools | "Folders work with ⌃ Actions." |
| No tools | "No tools for this file type. ⇧ Convert · ⌃ Actions" |
| Engine missing (optional engine) | Slice shown dimmed with "Needs Office Engine" in hub; drop opens the engine card |
| Unreadable item | "Zivlet can't read one of these files." + name |
| Tapped wheel rejects items | That wheel's message (never keep the previous wheel silently) |

### 5.11 Deliberate design decisions

Each row is a behaviour Zivlet chooses on purpose. The Zivlet column is the spec; Why gives the reason.

| # | Area | Zivlet | Why |
|---|---|---|---|
| D-1 | Idle detection | Event-woken, 0 idle wakeups | Energy |
| D-2 | Sampling | vsync display link | Latency (NFR-1) |
| D-3 | Mask held before drag | Ignored until re-pressed | ⌘/⌥ drags in Finder mean move/copy |
| D-4 | Re-tap same key | Closes wheel | Permission-free cancel |
| D-5 | Tapped wheel can't take items | New wheel's empty state | Clear feedback |
| D-6 | Leaving the wheel | Drag-exit events + 150 ms | Responsiveness |
| D-7 | Anchoring at edges | Hub under cursor, adaptive layout | Orientation |
| D-8 | Hit model | Sectors, slack to r 150 pt, 3° hysteresis, hub = cancel [critic3] | Forgiving targeting |
| D-9 | Close | 100 ms pulse/fade, non-blocking | Feedback |
| D-10 | Mode switch | Glass morph | Orientation |
| D-11 | Esc | Carbon hotkey while visible, else opt-in | P-T3 |
| D-12 | Drop with modifier held | Negotiates copy/generic/link/move | C-8 |
| D-13 | Progress ✕ | Cancel stops work | User control |
| D-14 | Folder access | None (unsandboxed); TCC prompts primed in onboarding | Fewer prompts |
| D-15 | Video remux | Per-stream copy when the target allows and the result is AVFoundation-playable; `hvc1` tagging | R-14, C-9 (O-16) |
| D-16 | PDF → JPG/PNG | 300 DPI default (72/150/300/600), cap 16,384 px / 200 MP | R-8 (O-16) |
| D-17 | Ogg target | Vorbis forced | C-23 (O-16) |
| D-18 | WebM | VP9 + Opus; AV1 option | O-16 |
| D-19 | Compress result ≥ input | Discarded; "Already optimal. The original was kept." | O-16 |
| D-20 | Normalize | Two-pass EBU R128, presets −16/−14/−23 LUFS | Accuracy |
| D-21 | Names | **Deferred** [critic3]: 1.0 keeps the parity names (05 D-4, 03a §4.4, M1 Task 5) because O-16 does not list a naming change. The consistent set ("No Metadata" / "Edited Metadata", "Speed 2x") needs an O-16 addition **[OWNER]** | Consistency (C-19) |
| D-22 | Logging | Never logs keys | Privacy |
| D-23 | Onboarding seen flag | Set at the end; resumes | Resumable onboarding |

---

## 6. Functional scope by phase

### 6.1 Conversions (275 pairs + extras)

| Family | Inputs → outputs | Pairs | Engine | Phase |
|---|---|---|---|---|
| Raster images | jpg png webp heic tiff avif bmp → each other + pdf (7 each) | 49 | ImageIO/Core Image, libwebp, Quartz | P1 |
| Audio | mp3 m4a wav flac ogg opus aiff wma → each other (7 each) | 56 | ffmpeg | P1 |
| Video | mp4 mov mkv webm avi wmv → each other + gif + mp3 (7 each) | 42 | ffmpeg (VideoToolbox, libvpx, x264, SVT-AV1) | P1 |
| GIF | gif → mp4 mov mkv webm avi wmv | 6 | ffmpeg | P1 |
| SVG | svg → 7 rasters + pdf | 8 | resvg / krilla-svg | P2 |
| PDF | → jpg png txt md (P2); → docx pages pptx xlsx epub (P3) | 9 | Quartz raster, PDFKit text + Vision OCR fusion | P2 (4) / P3 (5) |
| Documents | docx pages md rtf rtfd textClipping txt epub → docx pages pdf txt md html epub png jpg | 65 | SDoc model + writers, WebKit print, docx-preview, mammoth, cupertino-files | P2 (19) / P3 (46) |
| Slides | pptx → pdf jpg png (P2); ppt → pdf jpg png (P3, needs LibreOffice or Keynote) | 6 | pptx-renderer + WebKit print; LO/Keynote | P2 (3) / P3 (3) |
| Spreadsheets | xlsx xls ods csv tsv → xlsx ods csv tsv pdf | 21 | SheetJS (+ LO for styled PDF) | P2 |
| Subtitles | srt ↔ vtt, → txt | 4 | own Swift module | P2 |
| Archives | zip tar gz rar → zip tar gz (rar input only) | 9 | libarchive | P2 |
| **Total** | | **275** | 272 out of the box; 3 (PPT) need an optional engine | P1 153 → P2 221 → P3 275 |

P2 documents (19): docx → pdf png jpg txt md html epub (7); md → txt html epub pdf png jpg (6); txt → md html epub pdf png jpg (6). P3 adds docx → pages, md/txt → docx/pages, pages 8, rtf 9, rtfd 9, textClipping 9, epub 6.

Extras beyond 275 (same catalog, never counted toward parity):

| Extra | Phase |
|---|---|
| video → m4a (copy when AAC), animated WebP output and input, WebM AV1 option | P2 |
| png/jpg/heic → docx (OCR); RAW/PSD/JXL/EXR/JP2 inputs; ICO/ICNS outputs; md ↔ html; odt/doc/odp inputs (with LO) | P3 |
| JPEG XL output; keynote/numbers inputs; 7z/xz/zst/iso/cab inputs; 7z, AES-ZIP, tar.xz/zst outputs; ASS/SSA/SBV input; subtitle shift/fps | P4 |

### 6.2 Tools (27)

| # | Tool | Single-file inputs | Multi-file | Window | Output | Phase |
|---|---|---|---|---|---|---|
| 1 | Compress | jpg png webp heic tiff, mp3 m4a wav flac, mp4 mov mkv, pdf | yes | yes | `<base> Compressed.<ext>` (wav/aiff → .flac) | P2 |
| 2 | Metadata (view/edit/strip) | images, audio, mp4 mov mkv, gif, pdf | yes (strip, no window) | yes | images: `Metadata Removed` / `Metadata Edited`; pdf, audio, video: `No Metadata` (parity, D-21) [critic3] | P2 |
| 3 | Edit Photo | jpg png webp heic tiff | no | yes | `Edited` | P3 |
| 4 | Annotate Photo | same | no | yes | `Annotated.png` | P3 |
| 5 | Add BG | same | no | yes | `With Background` | P3 |
| 6 | Crop Image | same | yes (apply to all) | yes | `Cropped` | P2 |
| 7 | Normalize Volume | mp3 m4a wav flac | yes | yes | `Normalized` | P2 |
| 8 | Remove Audio | mp4 mov mkv | yes | no | `Muted` | P2 |
| 9 | Trim Video | mp4 mov mkv | no | yes | `Trimmed` | P2 |
| 10 | Split PDF | pdf | yes | no | folder `<base> Pages` | P2 |
| 11 | Organize PDF | pdf | no | yes | `Organized.pdf` | P2 |
| 12 | Extract Archive | zip tar gz rar | yes | no | folder `<base> Extracted` | P2 |
| 13 | Create PDF | — | images (+svg), multi only | no | `<first> Images.pdf` | P2 |
| 14 | Merge PDFs | — | pdf, multi only | yes | `<first> Merged.pdf` | P2 |
| 15 | Crop Video | mp4 mov mkv | no | yes | `Cropped` | P2 |
| 16 | Change Video Speed | mp4 mov mkv | no | yes | `Speed 2.0x` (parity, D-21) [critic3] | P2 |
| 17 | Join Videos | — | mp4 mov mkv, multi only | yes | `<first> Joined.mp4` | P2 |
| 18 | Video Snapshots | mp4 mov mkv | no | yes | `Snapshot.png` / folder `Snapshots` | P2 |
| 19 | Split Video | mp4 mov mkv | no | yes | folder `<base> Clips` or `Edited` | P2 |
| 20 | Audio Visualizer | mp3 m4a wav flac | no | yes | `Visualizer.mp4` | P3 |
| 21 | Trim Audio (+ auto-silence) | mp3 m4a wav flac | no | yes | `Trimmed` | P2 |
| 22 | Convert Audio Channels | mp3 m4a wav flac | no | yes | `Mono` / `Stereo` | P2 |
| 23 | Create Collage | — | images (+svg), multi only | yes | `<first> Collage.png` | P3 |
| 24 | Read QR Codes | images (incl. svg avif bmp gif), pdf | yes | no (results window) | no file | P2 |
| 25 | Redact Photo | jpg png webp heic tiff | no | yes | `Redacted` | P3 |
| 26 | Redact Video | mp4 mov mkv | no | yes | `Redacted` | P3 |
| 27 | Bleep Audio | mp3 m4a wav flac | no | yes | `Bleeped` | P3 |

Per-format tool sets (wheel order) follow 03a §2.6: images 7 single / 5 multi; pdf adds Read QR; svg/avif/bmp/gif get Read QR (gif also Metadata); ogg opus aiff wma webm avi wmv get none at parity (gap filled in P4, §6.9). Recipes: TS§5.

### 6.3 Actions (6)

| # | Action | Behaviour | Phase |
|---|---|---|---|
| 1 | AirDrop | System AirDrop share for local items; pre-flight availability; result in card | P1 |
| 2 | Float | Opens/extends a floating shelf (§6.7) | P2 |
| 3 | Copy | File URLs to the general pasteboard | P1 |
| 4 | Move | Folder picker ("Move Here", above wheel); per item move; cross-volume copy-verify-trash; collisions "name 2"; Undo | P1 |
| 5 | Copy Path | Newline-joined POSIX paths; ⌥ held at drop: shell-quoted, space-separated | P1 |
| 6 | Terminal | Opens the folder (or file's parent) in the chosen terminal: Terminal (default), iTerm2, Ghostty, WezTerm, Warp (each verified, P-TERM) | P1 |

Actions accept files, folders and mixed selections; never use the worker; the Actions wheel is never empty for local items.

### 6.4 Settings

| Pane | Contents | Phase |
|---|---|---|
| General | Wheel keys recorder with live preview; theme Glass/Solid; sounds & haptics; launch at login; reveal results; output fallback folder; terminal app; Float behaviour (new shelf / add to existing); ignored source apps | P1 (keys, sounds, login, reveal, terminal); P2 (Float, ignore list) |
| Formats | Defaults keyed by output format: quality (Balanced default), keep metadata (on), max height, audio bitrate (128/192/256/320, default 256), bit depth (match source), GIF fps 10/15/24 (15) and width 480/960/1280 (960), PDF raster DPI (300), EPUB reflow/fixed, PDF→Office editable/preserve pages, Video "Maximum compatibility" | P1 media/image; P2–P3 others |
| Tools | Compress presets and target sizes; remembered tool options | P2 |
| Compatibility | Full pair matrix with availability and the reason for anything hidden | P1 |
| Engines | Document fidelity Automatic/Fast/Best (default Automatic, O-7); LibreOffice status and verified download; iWork bridge opt-in | P3 |
| Keyboard & Automation | Services shortcut help, global hotkey, "Use Finder selection" opt-in, Esc opt-in, CLI install | P2 (Services) / P3 |
| Updates | Automatic check, automatic download, beta channel | P1 (stable) / P2 (beta) |
| Advanced | Helper versions and licences, Copy diagnostics, lane width overrides, reset settings | P1 |

Storage: one versioned, validated settings value behind an `@Observable` store with migrations.

### 6.5 Onboarding (720×480, resumable)

| Step | Content | Phase |
|---|---|---|
| 1 | Welcome | P1 |
| 2 | Practice drag: sample file, tap ⇧, real wheel opens (self-test; on failure show diagnostics) | P1 |
| 3 | Tools (⌘) and Actions (⌃) practice | P1 |
| 4 | Keyboard path (Services shortcut, optional hotkey) | P2/P3 |
| 5 | Privacy: explains macOS folder prompts; optional "Grant now" per protected folder so prompts appear here, not mid-job | P1 |
| 6 | Launch at login + automatic updates (both default on) | P1 |
| 7 | Move to Applications if run from a DMG or translocated | P1 |

No folder-grant page, no paywall. Completion flag written only at the end.

### 6.6 Menu bar

| Item | Phase |
|---|---|
| State line "Ready" / "Working on N" | P1 |
| Key legend "⇧ Convert · ⌘ Tools · ⌃ Actions" (live from bindings) | P1 |
| Active tasks: one row each with progress and Cancel | P1 |
| Recent results (last 20): Reveal, Undo | P1 |
| Settings… ⌘, · Getting Started… · Check for Updates… · About · Quit ⌘Q | P1 |
| Reopening the app (double-click) opens Settings, so a hidden menu bar item never strands the user | P1 |

### 6.7 Float shelf (in scope, P2)

| Aspect | Spec |
|---|---|
| Window | Non-activating floating panel, all Spaces, full-screen auxiliary; several shelves allowed |
| Docking | Free or docked to a screen edge as a tab; attach hysteresis 28 pt in / 48 pt out; 8 pt move threshold |
| Views | Compact/expanded; icons/list; Quick Look thumbnails |
| Interaction | Drag-out of file URLs; marquee and type-to-select; context menu Open, Open With, Quick Look, Show in Finder, Copy, Share, Move to Trash, Remove; click-through outside the visible shape |
| Persistence | Shelves restored after relaunch; references files (never copies); missing files greyed with "Locate…" |
| Re-trigger | Drags out of a shelf can open the wheel (convert a shelved file) |

### 6.8 Automation and keyboard path

| Surface | Spec | Phase |
|---|---|---|
| Services | "Open in Zivlet" for Finder selections; user assigns a shortcut; zero permission | P2 |
| Keyboard-mode wheel | Panel becomes key without activating the app; arrows/Tab rotate, 1–9 pick, type-to-filter, ⌘/⌃ switch, Enter apply, Esc close; petals are AX buttons | P3 |
| Global hotkey | Optional (no default; suggestion ⌃⌥⌘S); Carbon hotkey, no permission | P3 |
| Finder selection | Opt-in Apple Events (O-17), asked only when toggled | P3 |
| App Intents | Convert Files, Compress (target size), Strip Metadata, Run Tool, Read QR, Extract Text, Images → PDF, Merge PDFs, Get Supported Formats; return files | P3 |
| CLI | `zivlet` (convert, tool, formats); exit codes 0/1/2/3/130; Homebrew cask | P3 |
| URL scheme | `zivlet://` opens UI with files preselected; never runs a job | P3 |

### 6.9 Beyond parity (backlog, not FR-bound)

Several rows below are now planned in Phase 2–4; see [01b-prd-additions.md](01b-prd-additions.md) §A.

| Item | Phase |
|---|---|
| Presets as pinned slices; fit-under-size targets (10 MB, 25 MB); customisable wheels; hover size estimates | P4 |
| Tools for ogg/opus/aiff/wma/webm/avi/wmv; batch trim/crop/speed | P4 |
| Remove Background, Make PDF Searchable, PDF Protect/Unlock/Optimize, QR generate, Batch Rename with Undo | P4 |
| Finder Sync menu, 10 languages, warm LibreOfficeKit helper, styled XLSX → PDF, "Copy command" | P4 |
| Transcribe → SRT/VTT, MuPDF true redaction (gate O-9), sandboxed worker, Foundation Models "describe what you want", Raycast/MCP | P5 |

---

## 7. Functional requirements

Format: ID · requirement · acceptance criteria (AC) · phase. Every AC is automated unless marked (M) = manual QA matrix.

### 7.1 Trigger

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-1 | Detect file drags system-wide without polling at idle | Wheel opens for drags from Finder windows, Desktop, VS Code, Dropover (M). Text/link/tab drags never open it (trace tests). 0 Zivlet timer wakeups over 5 min idle (powermetrics) | P1 |
| FR-2 | Treat file-promise drags (Mail, Photos, Safari, Chrome, Arc, Firefox) as file drags | Each P-T5 source either works end to end or is listed as unsupported in docs; outputs land in the fallback folder and the card says so | P2 |
| FR-3 | Open the bound wheel on the rising edge of an exact mask match | Trace tests: ⇧ → convert, ⌘ → tools, ⌃ → actions; ⇧⌘ (unbound), ⌥ → no change | P1 |
| FR-4 | Ignore masks held at drag start; debounce 40 ms after live | Trace: ⌘ held from mouse-down never opens Tools until released and re-pressed; an edge at +20 ms is held to the 40 ms mark and fires only if the mask still matches; +60 ms fires at once [critic3: M1 Task 6 semantics] | P1 |
| FR-5 | Keep the wheel open after key release | Trace: release does not emit `hide` | P1 |
| FR-6 | Switch wheel in place on another bound mask | Anchor unchanged (±0 pt), highlight cleared, morph completes ≤ 280 ms | P1 |
| FR-7 | Close on re-tap of the active mask; the drag continues | Trace emits `hide(.retap)`; subsequent drop on Finder folder behaves as a normal Finder drop (M) | P1 |
| FR-8 | Esc closes the visible wheel without swallowing Esc when hidden | If P-T3 passes: hotkey registered only while visible, wheel closes and Finder drag continues (M). Else: Settings toggle "Esc closes wheel (needs Input Monitoring)", off by default | P1 |
| FR-9 | Hide on Space change, button up, display sleep | Trace + notification tests; sampler stops within 1 frame of button up | P1 |
| FR-10 | Trigger logic is a pure, value-typed state machine | `ZivletTrigger` has no AppKit import; ≥ 40 recorded traces (incl. known drag edge cases); 100 % branch coverage | P1 |
| FR-11 | Remappable bindings, validated | Recorder rejects empty or duplicate masks; a wheel may be Disabled; menu legend and onboarding key caps update live | P1 |
| FR-12 | Per-app ignore list for drag sources | A listed source app never opens a wheel (trace with source bundle id) | P2 |
| FR-13 | Bounded wake-up cost | Dragged-event monitor removed after the first event of each drag; < 1 % CPU on M1 with a 1 kHz mouse doing non-file drags (P-T1) | P1 |

### 7.2 Wheel

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-14 | Pre-warmed non-activating panel above shelves and Dock, on all Spaces and over full-screen apps | Finder stays frontmost after show/hide; visible over a full-screen Space and above Dropover (M) | P1 |
| FR-15 | Geometry per §5.5 | Snapshot tests of petal paths for n = 1…12 against golden geometry (radii ±0.5 pt, gap 4 ± 0.25 pt) | P1 |
| FR-16 | Layout and ordering per §5.5 | Unit: slot centre angles for n = 1…12; order equals catalog order | P1 |
| FR-17 | Petal and hub content per §5.5 | Snapshot: conversion labels, tool/action symbol + label, hub idle/hover text | P1 |
| FR-18 | Correct slices on the first frame | Read drag-pasteboard file URLs at tap (≤ 64 items, `contentType`), fallback to type-provisional + refine on `draggingEntered`; replay suite: final slice set on frame 1 in ≥ 99 % of ≤ 64-file drags; no pasteboard-privacy alert on 26.x/27.x (G-0) | P1 |
| FR-19 | Probe once per `(changeCount, mode)` off the main thread | Instrumented test: one probe per drag per mode; main-thread work per sampler tick < 0.2 ms p99 | P1 |
| FR-20 | Slice computation | Single format: catalog targets ∩ capability probe. Same-family mix: ordered intersection (PDF counts as document, GIF as video). Different families: badged union ("k of n") if ≤ 12 slots, else empty state [critic3: 03a §2.6, 05 D-1, M1 Task 7; confirm at P-W1]. Tools: 03a §2.6 table + multi filter. Actions: fixed 6. Table-driven tests over all 45 inputs and 30 mixed sets | P1 |
| FR-21 | Hit-testing per §5.6 | Unit grid test over the disc: every point maps to the expected zone; hysteresis holds within 3°; hub drop refused | P1 |
| FR-22 | Highlight feedback | Tint/scale/label weight change on the frame after crossing (signpost); one haptic and ≤ 1 tick per change; both behind one setting (default on); tick muted when system UI sounds are off | P1 |
| FR-23 | Mode morph | Shared hub and stable slot ids morph; Reduce Motion → 80 ms crossfade | P1 |
| FR-24 | Edge-adaptive placement | P1: the disk (r 125.92 + 8 pt margin) stays inside `visibleFrame`, so the hub offset is ≤ 134 pt at a corner and 0 away from edges (03a §2.1) [critic3: "≤ 64 pt with all labels on-screen" is not reachable with the fixed P1 layout; labels sit up to ~126 pt from the hub]. P3 (after P-W3): hub offset ≤ 8 pt, all labels on-screen at the 8 edge/corner test points for n = 1…12 | P1/P3 |
| FR-25 | Empty and refusal states per §5.10 | Snapshot per condition; a tapped wheel that rejects the items shows its own message | P1 |
| FR-26 | Glass and Solid themes | Solid auto-selected under Reduce Transparency or Increase Contrast; label contrast ≥ 4.5:1 in both themes, light and dark | P1 |
| FR-27 | Maximum 12 petals at constant size | Catalog lint fails if any input's default target list exceeds 12 | P1 |

### 7.3 Drop, jobs, output

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-28 | Accept drops on a highlighted slice with any held modifier | P-T6: drop accepted with ⌃/⌘/⌥ still held from Finder, Mail, Safari, Chrome; source never moved or deleted | P1 |
| FR-29 | Refuse drops on hub, disabled slice or dead ring | Icon snaps back; no job created; refusal reason shown for disabled slices | P1 |
| FR-30 | Fast acknowledgement | `performDragOperation` ≤ 1 ms (signpost); HUD visible ≤ 50 ms after drop | P1 |
| FR-31 | Dispatch per §5.7 | Integration tests for each dispatch class; window tools open at the wheel location | P1 (P2 tools) |
| FR-32 | Job lifecycle Request → Probe → Plan → Admit → Execute → Verify → Publish → Report as immutable values with lanes (TS§8.1) | Plan goldens (argv, names) for every pair; lane widths honoured under load; memory warning halves widths | P1 |
| FR-33 | Output location | Beside original by default; read-only volume or promise drag → fallback folder (default `~/Downloads`), stated in card | P1 |
| FR-34 | Naming and collisions per §5.9 | Unit tests incl. `.tar.gz`, `a.png` + `a.PNG` on case-insensitive APFS, 50 concurrent jobs to one name produce `name … 51` with no loss | P1 |
| FR-35 | Atomic publication | Staged on the destination volume; single rename with `RENAME_EXCL`; source never overwritten; no partial file visible at any time (fs-event test); stale staging swept at launch | P1 |
| FR-36 | Propagate `com.apple.quarantine` from any input to every output | Pair-matrix assertion, incl. all 9 archive pairs and Extract | P1 |
| FR-37 | Progress HUD per §5.8 | Monotonic progress; ≤ 10 Hz updates; indeterminate + bytes when duration unknown | P1 |
| FR-38 | Result card per §5.8 | Card shows before → after size, Undo, Reveal, Open, Copy, drag-out; failures persist with Show details and Retry | P1 |
| FR-39 | Undo | Undo moves the batch's outputs to the Trash (or reverses Move); available from card and Recent results; survives relaunch for the last 20 operations | P1 |
| FR-40 | Reveal | One Finder reveal per batch selecting outputs; setting to disable | P1 |
| FR-41 | User cancel | Cancel in HUD or menu row: state `cancelled` ≤ 100 ms, staging deleted, nothing published, children torn down per NFR-9 | P1 |
| FR-42 | Error taxonomy and copy (TS§8.4) | Every error case maps to user copy + log context; no error is swallowed (lint: no empty `catch`); per-file reasons in batch | P1 |
| FR-43 | Batch isolation | One failing file never stops the batch; final line "n of m saved · k failed" | P1 |
| FR-44 | Worker crash isolation | In-process parsers run in `ZivletWorker.xpc`; on crash each in-flight job retried once, singly; second crash → "This file made the engine crash", batch continues | P2 |
| FR-45 | Orphan reaper | Child pid/pgid recorded; at launch, live orphans whose path matches our helper are killed and job dirs deleted (test with forced app kill) | P1 |
| FR-46 | Quit | Cancel all jobs, wait ≤ 2 s, then terminate; no orphans | P1 |

### 7.4 Conversions

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-47 | One declarative catalog of all 275 pairs drives wheel, Settings matrix, dispatch, docs and CI | `@Test(arguments: Catalog.allPairs)` count = 275; docs table generated from catalog | P0 |
| FR-48 | Capability probe gates slices | Probe at first launch, update and OS change (ImageIO UTIs, ffmpeg encoders/muxers, Vision, Perl, JS hashes, LO/iWork); unavailable routes hidden in wheel, reason shown in Compatibility | P1 |
| FR-49 | Raster images 49 pairs | Pair matrix property checks: dimensions, orientation applied, ICC kept, 16-bit not blown out, alpha kept where the target supports it, metadata per setting, animated sources keep animation where the target supports it | P1 |
| FR-50 | Audio 56 pairs | Duration ±1 frame; channels/sample rate preserved unless target forbids; tags and cover art copied when "keep metadata"; Ogg = Vorbis | P1 |
| FR-51 | Video 42 + GIF 6 pairs | Per-stream copy when allowed and AVFoundation-playable; WebM = VP9 + Opus and playable; every MP4/MOV output `isPlayable` on M1 and M3+; A/V drift ≤ 1 frame (M-COPY); GIF uses palette, loops, 15 fps / 960 px default | P1 |
| FR-52 | SVG 8 pairs | No external resource loading; raster at 2× intrinsic, ≤ 8192 px; vector PDF; ≥ 97 % equal to reference on I-S1 corpus | P2 |
| FR-53 | PDF 9 pairs | → jpg/png 300 DPI, multi-page → `<base> Pages/` folder; → txt/md with OCR for scanned pages; → docx/pages modes Editable / Preserve pages; → epub modes Reflow / Fixed; recall ≥ 98 % on D-PDF corpus | P2/P3 |
| FR-54 | Documents 65 pairs | D-DOCX: page delta ≤ 1, SSIM ≥ 0.85; EPUB 0 EPUBCheck errors; DOCX opens in Word/Pages/LO without repair; encoding detection order BOM → UTF-8 → UTF-16 heuristic → cp1252 → latin-1; long unbroken lines wrap | P2/P3 |
| FR-55 | Slides 6 pairs | PPTX median SSIM ≥ 0.80 vs PowerPoint, ≤ 2 s / 30 slides; multi-slide images → `<base> Slides/`; PPT dimmed with "Needs Office Engine or Keynote" until available | P2/P3 |
| FR-56 | Spreadsheets 21 pairs | 100 % cell values on D-SHEET corpus; multi-sheet CSV/TSV → `<base> Sheets/`, one file per visible sheet; 2 M cells < 15 s | P2 |
| FR-57 | Subtitles 4 pairs | Cue timing preserved to the ms; fuzzed parser never crashes | P2 |
| FR-58 | Archives 9 pairs | gz target writes `.tar.gz`; RAR read only; limits (§NFR-13) enforced; quarantine propagated | P2 |
| FR-59 | Per-output-format defaults (§6.4 Formats) | Changing a default changes the plan golden; "Restore defaults" per format | P1 |
| FR-60 | Pass the 19 known conversion pitfalls of existing clones | One regression fixture per pitfall in the pair matrix | P1–P3 |

### 7.5 Tools

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-61 | Declarative tool registry: per-format single/multi sets, `hasEditor`, `multiInput` | Table-driven test reproduces §6.2 sets for every input format and count | P2 |
| FR-62 | Each of the 27 tools implements its TS§5 recipe and §6.2 output name | Per-tool golden plans + property checks; tools 1–2, 6–19, 21–22, 24 at P2; 3–5, 20, 23, 25–27 at P3 | P2/P3 |
| FR-63 | Shared tool window chrome | Opens at wheel location; live preview; Apply/Cancel; options remembered per tool; fully keyboard operable; Apply admits a job like any drop | P2 |
| FR-64 | Compress guards and targets | Output ≥ input → nothing kept, "Already optimal"; target-size mode lands within −10 %/+0 % of target on corpus or reports why; PDF with forms/signatures warns and offers lossless only | P2 |
| FR-65 | Metadata fail-closed | Read → plan → write → verify; any unplanned change or `ImageDataHash` change → output discarded; "Remove all" leaves no GPS, maker notes, XMP, IPTC, thumbnail, cover-art EXIF (C-14) | P2 |
| FR-66 | Redaction burns in | Photo/video redaction irreversibly overwrites pixels; outputs always stripped of metadata incl. EXIF thumbnail; Redact Video ≥ 1× realtime on M-REDACT clip | P3 |
| FR-67 | Read QR safety | Results window: Copy, Copy All; Open only for http(s) with full URL shown; never auto-opens | P2 |
| FR-68 | Multi-file semantics | Combining tools (Create PDF, Merge, Join, Collage) produce one output in the first file's folder; single-file tools never silently no-op | P2 |

### 7.6 Actions

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-69 | AirDrop | Availability pre-flight; non-local items refused with copy; success/failure in card; user cancel is not an error | P1 |
| FR-70 | Copy and Copy Path | Copy writes file URLs; Copy Path writes newline-joined paths, ⌥ variant shell-quoted; non-local items refused with copy | P1 |
| FR-71 | Move | Picker above the wheel; collisions "name 2"; cross-volume copy → verify size and count → trash source; folder into itself refused; Undo restores; per-item failures listed (non-modal) | P1 |
| FR-72 | Terminal | Opens folder or file parent in the selected installed terminal; missing terminal → message pointing to Settings | P1 |
| FR-73 | Float shelf per §6.7 | Restored after relaunch; drag-out works into Finder/Mail; missing file shows Locate…; no permission prompts | P2 |

### 7.7 App shell

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-74 | Menu bar per §6.6 | Active task rows cancel jobs; Recent results reveal/undo | P1 |
| FR-75 | Reopen opens Settings | Double-click while running opens Settings | P1 |
| FR-76 | Settings per §6.4 | Each pane's options persist and migrate across versions (migration tests) | P1–P3 |
| FR-77 | Onboarding per §6.5 | Practice drag uses the real trigger; quitting midway resumes at the same step; completion flag only at the end | P1 |
| FR-78 | Launch at login via `SMAppService` | States on/off/requires approval shown truthfully; default on from onboarding | P1 |
| FR-79 | Updates via Sparkle 2 (EdDSA, signed feed) | N-1 → N update installs on a clean VM; beta channel opt-in at P2; Sparkle system profiling off | P1 |
| FR-80 | Move to Applications | Offered when running from `/Volumes/` or translocated | P1 |
| FR-81 | Local diagnostics | Copy diagnostics bundles helper versions/hashes, capability cache, last 200 log lines, last trigger trace, settings; nothing is sent | P1 |
| FR-82 | Licence and source | About lists every component and licence; links to corresponding source for the exact version | P1 |
| FR-83 | Optional engines | LibreOffice detected or downloaded on click (pinned SHA-256, Team ID check); iWork bridge opt-in, off by default | P3 |

### 7.8 Automation and keyboard path

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-84 | Services entry | Selecting files in Finder + Services shortcut opens the wheel in keyboard mode (P3) or a format menu (P2); no prompt (P-X1) | P2 |
| FR-85 | Keyboard-mode wheel per §6.8 | Every slice reachable by keys; VoiceOver announces "Convert to PNG"; Finder stays frontmost | P3 |
| FR-86 | Global hotkey and Finder-selection opt-in | Hotkey unset by default; Automation consent asked only when the toggle is flipped; denied → falls back to Services or "Choose files…" | P3 |
| FR-87 | App Intents per §6.8 | Each intent runs headless in Shortcuts, returns files, chains with another action | P3 |
| FR-88 | CLI | `zivlet convert in.heic --to jpg` writes beside input; exit codes 0/1/2/3/130; SIGINT cancels children; WebKit routes handed to the app (P-CLI) | P3 |
| FR-89 | URL scheme | `zivlet://` opens UI with files preselected; fuzzed URLs never start a job | P3 |

---

## 8. Non-functional requirements

| ID | Requirement | Target / acceptance | Verified by | Ph |
|---|---|---|---|---|
| NFR-1 | Tap → wheel latency | p95 ≤ 16 ms at 120 Hz, ≤ 33 ms at 60 Hz, modifier edge → first wheel frame committed; M1 Air (60 Hz) and a ProMotion Mac | `OSSignposter` nightly perf job (P-T4) | P1 |
| NFR-2 | Wheel smoothness | Highlight and morph with no hitch > 2 frames; GPU < 10 % on M1 | Instruments Hitches (P-W1/W2) | P1 |
| NFR-3 | Permission-free trigger | Default flow causes 0 prompts for Accessibility, Input Monitoring, Screen Recording, Automation. Only macOS folder prompts (Desktop, Documents, Downloads, iCloud Drive, removable, network) may appear, primed in onboarding | TCC db diff on clean VM after scripted flows (P-P1) | P1 |
| NFR-4 | Idle cost | 0 Zivlet wakeups with no drag; ~0 % CPU; idle RSS gate set from P-W1 data (provisional ≤ 60 MB); web views lazy, torn down after 60 s idle | powermetrics, footprint | P1 |
| NFR-5 | Privacy / offline | No telemetry, analytics, crash upload or account. Network only for Sparkle feed/update and a user-clicked LibreOffice download. Worker and helpers have no network code; ffmpeg built `--disable-network`; WebKit blocks http(s)/file/ftp | CI: pair matrix with outbound traffic blocked passes 100 % and logs 0 connection attempts; symbol scan of worker/helpers | P1 |
| NFR-6 | Log privacy | Paths `privacy: .private`; no key or modifier logging; diagnostics stay local | Log lint + review | P1 |
| NFR-7 | Size | ≤ 70 MB installed, ≤ 32 MB DMG target; CI hard fail > 85 / 40 MB, warn > 70 / 32 | Size gate on release | P1 |
| NFR-8 | Crash isolation | No input crashes the app process: hostile corpus (zip-slip, 42.zip, broken PDF xref, malformed media, fuzzed subtitles) nightly with 0 app crashes; worker/helper crashes become per-file errors | Hostile corpus + fuzzers | P1 (media) / P2 (worker) |
| NFR-9 | Cancel latency | Visible ≤ 100 ms; ffmpeg/perl/zivlet-js process group gone ≤ 1 s; LibreOffice ≤ 5 s; WebKit ≤ 200 ms; 0 partial outputs published | Cancel tests per engine | P1 |
| NFR-10 | Throughput and memory | HEIC 12 MP → JPEG ≤ 150 ms; 1 min 1080p MOV → MP4 (VideoToolbox) ≤ 10 s; VP9 shows ETA; 4 GB video with app RSS < 300 MB | Nightly benchmarks on Apple silicon | P1 |
| NFR-11 | Route correctness | 100 % of advertised pairs and tools pass the matrix nightly on a clean VM; any failure blocks release; no slice for an absent engine | Pair matrix (`@Test(arguments:)`) | P1→P3 |
| NFR-12 | Data safety | Originals never modified; atomic publish; disk-full and cancel leave no partial files; staging always cleaned | Fault-injection tests | P1 |
| NFR-13 | Security | Helper code-signature check on first use per launch; release never falls back to Homebrew binaries; child env pinned (`PATH=/usr/bin:/bin`, private TMPDIR); ffmpeg input confinement (demuxer whitelist, HLS/DASH disabled, HLS/ffconcat disguised fixtures refused); archives ≤ 100,000 entries, ≤ min(20 × archive + 1 GB, free − 2 GB), no `..`/symlink/absolute paths, no setuid; XML DTD/ENTITY rejected; 200 MP raster cap; quarantine propagated; hardened runtime, notarized, stapled | Hostile corpus, signature gate, M-HOSTILE | P1/P2 |
| NFR-14 | Accessibility | VoiceOver can reach every feature (keyboard-mode wheel, all windows, HUD, card); Reduce Motion, Reduce Transparency, Increase Contrast honoured; label contrast ≥ 4.5:1; Large wheel option; every control labelled | Accessibility Inspector audit 0 issues on shipped windows; VoiceOver script (M) | P3 (motion/transparency P1) |
| NFR-15 | Compatibility | macOS 26.0 → latest 27.x, arm64; multi-display, full screen, Stage Manager, notch | Clean Tart VMs 26.0/26.x/27.x (P-CI); real-drag QA matrix (M) | P1 |
| NFR-16 | Localisation-ready | All UI strings in String Catalogs, no concatenation, plural rules; pseudo-locale run with 0 truncations | Pseudo-locale UI test | P3 |
| NFR-17 | Code quality | Swift 6 strict concurrency, 0 warnings; ≥ 80 % coverage on Core, EngineKit, engines, Runtime, Trigger; files ≤ 400 lines typical (800 max); functions < 50 lines; immutable value types | PR CI | P0 |
| NFR-18 | Licence compliance | GPL-3.0-or-later; ffmpeg `-buildconf` has no `nonfree`; `cargo-deny`; npm allowlist; SPDX manifest complete; corresponding source per release | Licence gate (hard fail) | P1 |
| NFR-19 | Update integrity | EdDSA-signed feed; deltas; every Mach-O signed with runtime flag + timestamp; `spctl` passes on clean VM | Signature gate, P-C1 | P1 |
| NFR-20 | Energy during drag | Sampler ≤ 1 % CPU of one core at 120 Hz; stops within 1 frame of mouse-up | powermetrics during scripted drags | P1 |

---

## 9. Success metrics

Zivlet has no telemetry, so every metric comes from CI, benchmarks or public signals.

| Metric | Target | Source |
|---|---|---|
| Tap → wheel p95 | ≤ 16 ms @120 Hz on every nightly | Perf job |
| Advertised route pass rate | 100 % (P1 153, P2 221, P3 275 + 27 tools + 6 actions) | Pair matrix |
| "Hidden options" class regressions | 0 releases with a slice missing vs the catalog | Catalog diff test |
| Permission prompts in default flow | 0 non-folder prompts | TCC diff on clean VM |
| Hostile-corpus app crashes | 0 | Nightly |
| Installed size at 1.0 | ≤ 70 MB | Size gate |
| Onboarding practice drag success | Wheel appears on first try in ≥ 95 % of moderated sessions (n ≥ 10) | Moderated usability test (M) |
| Time to first conversion for a new user | ≤ 60 s from first launch | Moderated test (M) |
| Bug reports about wrong/unplayable output | < 5 % of issues after P2 | GitHub issue labels |
| Adoption | GitHub Releases downloads and stars tracked per release (no in-app counting) | GitHub API |
| Security response | Bundled-library CVE fix shipped ≤ 7 days after upstream release | Release log |

---

## 10. Release phases mapped to requirements

| Phase | Label | Scope | FR ids | NFR ids | Exit criteria |
|---|---|---|---|---|---|
| P0 | Skeleton (internal) | Gate-A spikes (G-0, P-T1–T4, P-T6, P-W1–W2, P-P1, M-1, M-2, M-4, P-C1, P-CI); XcodeGen project + ZivletKit package; catalog as data; vendored FFmpeg; signed "hello" DMG with Sparkle | FR-47 | NFR-17 | Permission-free trigger works from Finder on 26.x; notarized DMG with ffmpeg passes `spctl`; Sparkle N-1 → N installs |
| P1 | Private alpha 0.1 | Trigger, wheel (Glass + Solid), 153 pairs (raster, audio, video, GIF), 5 actions, runtime (lanes, staging, naming, HUD, card, Undo, reaper, probe, diagnostics), shell basics, onboarding, Sparkle stable | FR-1, FR-3–FR-11, FR-13–FR-43, FR-45–FR-51, FR-59, FR-60 (image/media), FR-69–FR-72, FR-74–FR-82 | NFR-1–NFR-13, NFR-15, NFR-17–NFR-20 | 153 pairs green incl. playable WebM; tap → wheel p95 ≤ 16 ms @120 Hz; 0 non-folder prompts; 0 app crashes on hostile media corpus |
| P2 | Public beta 0.5 | +68 pairs → 221 (SVG 8, PDF 4, sheets 21, PPTX 3, subtitles 4, archives 9, documents 19); 19 tools; Float; worker XPC; promise drags; ignore list; Services; beta channel; extras (video → m4a, animated WebP, AV1) | FR-2, FR-12, FR-44, FR-52, FR-53 (4), FR-54 (19), FR-55 (PPTX), FR-56–FR-58, FR-61–FR-65, FR-67, FR-68, FR-73, FR-84 | + NFR-8 (worker) | Every P2 route passes matrix and fidelity bars (D-SHEET, D-RENDER, I-S1, I-A1, I-M1, I-M2, EPUBCheck 0 errors); worker isolates hostile PDF/ZIP crashes |
| P3 | **1.0 parity** | +54 pairs → 275 (remaining documents, PDF → office/epub, PPT via optional engine); tools 27/27; keyboard-mode wheel; hotkey; App Intents; CLI + cask; URL scheme; engines pane; Large wheel; full accessibility; edge-adaptive wheel | FR-24 (P3 bar), FR-53 (5), FR-54 (46), FR-55 (PPT), FR-62 (remaining 8), FR-66, FR-83, FR-85–FR-89 | NFR-14, NFR-16 | All 275 pairs, 27 tools, 6 actions pass nightly on clean 26.x VM (PPT with LO installed); real-drag QA matrix passes; size gate passes |
| P4 | 1.x | §6.9 P4 backlog | new FR set per release | — | Per-feature PRD addendum |
| P5 | 2.x | §6.9 P5 backlog | new FR set | — | Gate decisions (O-9, P-8) |

Schedule note (TS§12 challenge, O-18): one engineer ≈ 12–18 months to P3. Labels are fixed to scope, not dates.

---

## 11. Improvement targets

| # | Improvement | Problem it prevents | Zivlet requirement |
|---|---|---|---|
| B-1 | WebM output works (VP9 + Opus, AV1 option) | WebM targets hidden when the encoder build lacks VP9/Opus | FR-51, D-18 |
| B-2 | Zero idle wakeups | Timer polling that costs energy while idle | FR-1, NFR-4 |
| B-3 | Faster, frame-synced trigger | Fixed-rate polling that quantises taps and lags on slower Macs | NFR-1, D-2 |
| B-4 | Permission-free cancel | Esc handling that silently needs Input Monitoring | FR-7, FR-8 |
| B-5 | Explains refusals | Silent no-ops when a wheel or tool can't take the items | FR-25, FR-68 |
| B-6 | Hub stays under the cursor | Wheel drifting away from the cursor near screen edges | FR-24, D-7 |
| B-7 | Forgiving hit-testing | Dead gaps and rims; flicker at sector boundaries | FR-21, D-8 |
| B-8 | Drop works with a modifier still held | A held ⌃/⌘ narrowing the drag operation mask (C-8) | FR-28 |
| B-9 | Real cancellation | Progress UI that closes while work and child processes keep running | FR-41, NFR-9 |
| B-10 | Bounded parallelism | Strictly sequential items, or unbounded parallel drops | FR-32 |
| B-11 | Crash isolation | Third-party parsers crashing the app process | FR-44, NFR-8 |
| B-12 | No folder-grant dialogs | Sandbox per-folder grant panels and late write failures | D-14, NFR-3 |
| B-13 | Free, no limits | Paywalls after a free quota | NG2 |
| B-14 | Small install (≤ 70 MB) | Bundled runtimes inflating the download | NFR-7 |
| B-15 | Safe archives | Extraction without size, count or path checks | FR-58, NFR-13 |
| B-16 | Atomic naming | Check-then-move races; stale staging left behind | FR-34, FR-35 |
| B-17 | Probes off the main thread | Per-frame file stats on the main thread during drags | FR-19 |
| B-18 | Lossless remux where possible | Always re-encoding video | FR-51, D-15 |
| B-19 | Two-pass loudness normalisation | Single-pass normalisation without measured values | FR-62, D-20 |
| B-20 | Larger PDF raster cap | Low pixel caps on PDF → image | FR-53, D-16 |
| B-21 | "Already optimal" guard | Compress keeping outputs that are not smaller (O-16 rationale) | FR-64 |
| B-22 | Fail-closed, complete metadata removal | Unverified stripping; metadata helper with no timeout | FR-65, D-21 |
| B-23 | Undo and result card | Progress UI that ends with no done state and no Undo | FR-38, FR-39 |
| B-24 | Automation | No App Intents, URL scheme or Services | FR-84–FR-89 |
| B-25 | Accessibility | No keyboard-operable wheel; accessibility undeclared | FR-85, NFR-14 |
| B-26 | Privacy you can audit | Closed source, so logging and network use can't be checked | NFR-5, NFR-6, D-22 |
| B-27 | Onboarding that resumes | Onboarding marked complete before it finishes | FR-77, D-23 |
| B-28 | Float shelves persist | Shelves lost on relaunch | FR-73 |
| B-29 | Non-blocking action feedback | Modal alerts for file-action failures | FR-69–FR-72 |
| B-30 | Capability matrix regression-tested | Routes silently disappearing between releases ("hidden options" class) | FR-47, NFR-11 |

---

## 12. Dependencies, risks and open items

| Item | Affects | Resolution path |
|---|---|---|
| P-T2 `flagsChanged` without permission | NFR-1 (event path vs vsync) | If yes, event path default; else vsync sampler (meets ≤ 2 frames) |
| P-T3 Carbon Esc hotkey during Finder drag | FR-8 | Fallback: opt-in Input Monitoring toggle |
| G-0 drag-pasteboard URL read at tap on 26.x/27.x | FR-18 | Fallback: type-provisional petals + `draggingEntered` refine |
| P-W3 edge layout feel | FR-24 P3 bar | Fallback: P1 bar (≤ 64 pt offset) ships at 1.0 |
| P-P1 TCC prompt locations (app and spawned ffmpeg) | NFR-3, onboarding step 5 | Documented table + onboarding copy |
| P-W1 idle RSS | NFR-4 | Gate set from measurement |
| D-PAGES (cupertino-files) | Pages pairs (P3) | Fail → Pages output via iWork only, Pages input preview fallback |
| C-12 styled XLSX → PDF | FR-56 | D-XLSX-STYLE; LO when present |
| Trademark check "Zivlet" (O-12) | Any public artifact | Before P2 public beta |
| Developer ID account (O-11) | P0 exit, NFR-19 | Owner action; ad-hoc builds until then |
| Accent colour, icon, sounds | FR-22, FR-26 | Original assets in design doc; none derived from the reference app |

## 13. Glossary

| Term | Meaning |
|---|---|
| Wheel / petal / slice | Radial overlay; one target per petal |
| Hub | Centre disc; label area and cancel zone |
| Mask | Exact set of held modifiers (⌃⌥⇧⌘) bound to a wheel |
| Pair | One input format → one output format conversion |
| Lane | Bounded concurrency queue per engine class |
| Staging | Hidden same-volume location where outputs are written before the atomic rename |
| Promise drag | Drag carrying file promises instead of file URLs (Mail, Photos, browsers) |
| Optional engine | LibreOffice or iWork apps, never bundled |
