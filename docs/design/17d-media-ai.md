# Zivlet roadmap: Media / AI cluster

> Imported into the repository on 2026-10-21 from the roadmap drafts; approved by the owner the same day
> (see [00-decisions.md](00-decisions.md), 2026-10-21 section). The product name is Zivlet.
> Prototype folders named `<name>.XXXX/` are local prototypes and are not published.
> The "17-* files" below are now [17-feature-roadmap.md](17-feature-roadmap.md), [17-roadmap-challenge.md](17-roadmap-challenge.md),
> [01b-prd-additions.md](../plan/01b-prd-additions.md) and [05-task-list.md §9](../plan/05-task-list.md).

> [challenge] Adversarial review 2026-10-21 ([17-roadmap-challenge.md](17-roadmap-challenge.md)). The 17-* files are authoritative wherever they differ from this report. Corrections that apply here:
> - **Diarisation:** only sherpa-onnx was measured, and it ships code (onnxruntime, about 60 MB), which can't be a
>   data-only pack. The CoreML route is unmeasured. sherpa-onnx is a test baseline, not a shipped fallback.
> - **Translate:** use the transcript's **Devanagari** form as the source. Roman Hinglish with source = hi rests on one
>   sentence and is a fallback only.
> - `SystemLanguageModel.tokenCount(for:)` is macOS 26.4+. Add a character-count fallback for 26.0–26.3.
> - The dwell-ring spike **P-W4 is renamed P-W5** (10 §13's P-W4 is the UI-sound key).
> - Size estimates before the drop use only metadata: no content reads, no ffprobe, no dataless download.

Date: 2026-10-21. Status: research and prototypes for the owner's 2026-10-21 feature picks (recorded in [00-decisions.md](00-decisions.md)).
Scope: remove silences, fit-to-size presets, Instagram presets, size preview while hovering, meeting summary with speaker labels, translate transcript, "ask in plain words".
Out of scope: transcription itself. It is being designed separately (docs/design/16, not yet written; spikes are local prototypes, not published). This document only reserves its place (§9) and states what the features here need from it.

Inputs read: `docs/design/00-decisions.md`, `10-tech-strategy.md` (§9 size, §10 licensing, §12 roadmap), `11-media-engine.md` (§8.2 probe, §9 target size, §11 tool mapping), `12/13` (engines), `14-app-platform.md` (§2.3 rendering, §4.4 CLI, §4.7 Apple Intelligence), `docs/plan/01-prd.md`, `02-architecture.md`, `03a`/`03b`, `05-task-list.md` (P2-32, P2-33, P2-49, B4-15, B4-16, B5-03, B5-04).

Principles applied: local and offline, no telemetry, bundle ≤ 70 MB with large models as optional downloads, clean-room (nothing from the reference app or Open-Tangerine is used).

### Evidence labels and test machine
- **MEASURED**: run on this Mac (Apple M2 Pro, macOS 27.0 build 26A428, Xcode SDK `MacOSX27.0.sdk`, Swift 6.4, Homebrew ffmpeg 8.1.2). Swift probes were compiled with `-target arm64-apple-macos26.0` (the product's minimum) unless noted.
- **VERIFIED-SDK**: read from the SDK's `.swiftinterface` files.
- **VERIFIED-WEB**: web sources, dated, listed in Sources.
- **INFERRED**: engineering judgement, not measured.
- **Timing caveat:** another agent's transcription spike was running whisper and Python jobs at the same time. Load average ranged from **26 to 296** during these runs. Treat every wall-clock figure as an **upper bound**. Sizes, accuracy and sync numbers are not affected by load.
- All prototypes are in `<feature>.XXXX/` folders (local prototype, not published). Each section names its folder.

---

## 0. Summary

| # | Feature | Engine (licence, bundle cost) | Effort | Recommended phase | Main risk |
|---|---|---|---|---|---|
| 1 | Remove silences (audio + video) | ffmpeg `silencedetect` → own cut list → `trim/concat` or frame-snapped `select` (GPL ffmpeg, already bundled; +0 MB) | **M** | **Phase 2** with P2-49 | Threshold choice on noisy recordings; A/V sync on many cuts (solved, see §1) |
| 2 | Fit-to-size presets | Existing target-size machinery (11 §11, P2-32/33) plus a data-driven preset table; ImageIO quality search for images (+0 MB) | **S** (table) + **M** (image/PDF search) | **Phase 2** | Platform limits change (Discord changed in Aug 2026) |
| 3 | Instagram presets | ffmpeg scale/crop/pad/blur-fill; Vision objectness saliency for smart crop (system, +0 MB) | **S** (crop/pad/blur), **M** (smart crop) | Phase 2 (basic), Phase 4 (smart crop) | Reels length rules unclear and changing |
| 4 | Size preview while hovering | Tiered estimator: exact maths → image tile sampling → background video sample encode (+0 MB) | **M** | Tier 0 in Phase 2; tiers 1–2 in Phase 4 (B4-15) | Video constant-quality presets can't be estimated within the hover budget |
| 5 | Meeting summary with speaker labels | Diarisation: CoreML pack (FluidAudio-style, Apache-2.0 code) or sherpa-onnx (Apache-2.0) as an **optional download**; summary: Apple **Foundation Models** (system, +0 MB) | **L** | **Phase 4** (after transcription ships) | 4096-token context; Hindi not officially supported by the model; model-pack signing |
| 6 | Translate transcript (→ English) | Apple **Translation** framework, offline packs (system, +0 MB); Whisper `task=translate` as a fallback inside the transcription pipeline | **S** | Same phase as transcription | Romanised Hinglish can't be auto-detected; turbo models can't translate |
| 7 | Ask in plain words | Foundation Models guided generation into a registry-constrained plan, plus deterministic validation and a confirm card (+0 MB) | **M** | **Phase 4** (pull B5-04 forward) | Model hallucinates destinations and steps; needs Apple Intelligence enabled |
| 8 | Transcription (reserved) | Separate design | — | Separate | — |

**Bundle impact:** about +1 MB in total (Swift code and preset JSON). Diarisation models are an optional verified download of **about 15–20 MB** (CoreML route) or **about 60 MB** (sherpa-onnx route, §5.3). Foundation Models, Translation and Vision are part of macOS. Translation language packs are downloaded and managed by macOS, not by Zivlet.

**Corrections to the owner's numbers (VERIFIED-WEB, §2.1):** Discord's free limit is now **20 MB** (raised from 10 MB on 2026-08-13). WhatsApp's **100 MB** document limit applies to the WhatsApp **Business API**; the consumer app allows documents up to 2 GB. Gmail's 25 MB covers the whole encoded message, so the safe attachment budget is about **18 MB**.

---

## 1. Remove silences (audio and video)

### User-facing behaviour
- Slice "Remove Silences" appears on the wheel for audio and for video with an audio track. Probe gating (11 §8.2) hides it for video with no audio.
- One drop, no dialog. Defaults to **Natural**: removes pauses ≥ 0.5 s and keeps 0.15 s of padding at each edge.
  - ⇧ variant **Tight**: ≥ 0.3 s, 0.08 s padding.
  - Settings exposes the threshold (Auto, or −60…−25 dB), the minimum pause and the padding.
- Output: `<name> (No Silences).<ext>` beside the original, same container. Video is re-encoded with VideoToolbox in the source codec family (cuts are frame-accurate). Audio is re-encoded in the same codec; WAV/AIFF/FLAC stay lossless.
- Result card: "Removed 4 min 12 s (18%)". If nothing qualifies: "No long pauses found". This is a neutral result, not an error, and writes no file.
- Tool window (with P2-49's waveform): shows shaded removal regions and lets the user un-shade a region before rendering.

### Engine
- Analysis: `ffmpeg -i in -af silencedetect=noise=<T>dB:d=<min> -f null -`, then parse `silence_start`/`silence_end` from stderr into a keep list (a pure Swift function, unit-testable; prototype `cutlist.awk`).
- **Adaptive threshold (Auto):** measure 100 ms RMS windows (`astats=metadata=1:reset=1` at 16 kHz). Then T = p10 + 6 dB, clamped to −60…−25 dB. A fixed −40 dB found **zero** pauses in the TTS file whose pauses sit near −37 dB (MEASURED below).
- Render, two proven variants:
  - **≤ 40 segments:** `trim/atrim + setpts/asetpts + concat` in a `-/filter_complex <file>` script. Exact.
  - **> 40 segments:** single-pass `select`/`aselect` with **frame-snapped** bounds. Video uses half-frame offsets `(k±0.5)/fps`; audio uses frame times `k/fps`. 4.6× faster at 100 segments.
  - Never use plain `between(t,a,b)`: it is inclusive at both ends, which adds one frame per segment. More than about 150 product terms overflow the expression parser.
- Audio-only shortcut `silenceremove` was tested and rejected as the main path. Its `stop_silence` semantics gave 7.66 s where the cut-list path gives 6.1 s, and it can't be previewed in the tool window.
- Licence and size: ffmpeg (GPL-3.0-or-later build, already in the bundle). **+0 MB.**

### Evidence (MEASURED; `silence.p7I3/` (local prototype, not published))
1. **Synthetic A/V sync fixture**, 12 s. Tone in [0.5,2.5], [5,6], [8.5,11] s; pink noise floor at −60 dB. A white video flash coincides with each tone onset.
   ```
   ffmpeg -f lavfi -i "color=black:s=640x360:r=30:d=12" -f lavfi -i "aevalsrc='0.25*sin(2*PI*440*t)*(between(t,0.5,2.5)+…)':s=48000:d=12" \
     -f lavfi -i "anoisesrc=c=pink:a=0.001:r=48000:d=12" -filter_complex "[0:v]drawbox=…:enable='…'[v];[1:a][2:a]amix=inputs=2:normalize=0[a]" … src.mp4
   ffmpeg -i src.mp4 -af silencedetect=noise=-40dB:d=0.5 -f null -     # → 0–0.500021, 2.5–5.000021, 6–8.500021, 11–12.01
   ```
   Detection was accurate to 0.02 ms. Keep list with 0.1 s padding: `0.4–2.6, 4.9–6.1, 8.4–11.1`.
   `trim/concat` render: **12.0 s → 6.100 s** (video 6.100000, audio 6.100000). Audio onsets in the output: **0.100, 2.300, 3.500 s**. Video flashes (`blackdetect`): **0.1, 2.3, 3.5 s**. A/V offset < 1 ms. Render wall time 6.1 s (loaded machine).
2. **Scale test**, 5 min 720p, a gap every 3 s → **100 segments**, expected output 219.9 s.

   | Render method | Wall (loaded) | Max RSS | Video / audio duration | End drift |
   |---|---|---|---|---|
   | `trim/concat` | 92.5 s | 96 MB | 219.900 / 219.900 | 0 |
   | `select` with plain `between()` | 19.9 s | 117 MB | **222.967** / 219.925 | **+3.04 s** (one frame per segment) |
   | `select`, `gte*lt` (200 terms) | — | — | parser "Cannot allocate memory" | — |
   | `select`, `between(t,a,b−0.0005)` | 19.2 s | — | 219.633 / 219.925 | −0.29 s (float boundaries) |
   | **`select` frame-snapped (video ±½ frame, audio frame times)** | ≈ 20 s | — | **219.900 / 219.925** | **≤ 25 ms (< 1 frame)** |

   On the 12 s fixture, the frame-snapped `select` gives video flashes at 0.1/2.3/3.5 s and audio onsets at 0.095/2.291/3.487 s (≤ 13 ms).
3. **Real speech:** three CC-BY-4.0 HumynLabs Hinglish clips joined with inserted 2 s and 3 s noise gaps (38.6 s total). Thresholds −45, −40 and −35 dB all found both gaps (2.07–2.62 s and 3.25–3.26 s) plus one natural 0.9 s pause. Kept 33.3 / 33.2 / 32.7 s. The result is stable across a 10 dB range.
4. **Noise floor** (`astats` 100 ms windows): the TTS `en10.aiff` file has p10 −37.2 dB. The real clips have p10 −38.5 and −46.0 dB. Analysis of 10 min of PCM took **0.12 s** (about 6600× realtime).

### Risks
- **Music beds and constant background noise:** the adaptive threshold may find nothing. That is the correct outcome, and the result card says so.
- **Cuts mid-breath can click.** Add a 5–10 ms `afade` at each join (INFERRED, not tested).
- **Transcript and subtitle sidecars:** if a transcript exists, its timestamps must be remapped through the keep list. The keep list is a pure function, so this is cheap.
- **VFR sources:** `trim` is timestamp-based and works. The `select` variant assumes the probe's nominal fps, so use `trim/concat` when the probe reports VFR (INFERRED).

**Effort:** M (analysis parser, adaptive threshold, two render paths, sync tests in CI using the lavfi fixture above).
**Dependencies:** P1-07 progress parser, P2-30 media engine base, P2-49 waveform and trim tool window.
**Phase:** **Phase 2**, delivered together with P2-49 (same analysis code; P2-49 only trims the ends).

---

## 2. Fit-to-size presets

### 2.1 Current limits (VERIFIED-WEB, 2026-10-21; sources at the end)

| Preset | Limit | Status of the evidence | Zivlet target (bytes, decimal) |
|---|---|---|---|
| **WhatsApp** (photos/videos/voice, sent as media) | 16 MB | Consistent across all sources; WhatsApp still re-encodes media | **15.5 MB** |
| WhatsApp document (consumer app) | 2 GB (rolled out from 2022) | Most sources; some 2025–26 articles still say 100 MB | not a preset (no need) |
| WhatsApp **Business API** document | 100 MB | Business API docs | optional "WhatsApp Business doc 97 MB" |
| **Gmail** (personal) | 25 MB per message, **including** encoding; receive 50 MB | Consistent; 2026 Enterprise accounts may get 50 MB | **18 MB** (25 MB ÷ 1.351 base64 overhead, MEASURED, minus headers) |
| **Discord** (free) | **20 MB since 2026-08-13** (was 10 MB) | Discord's own announcement, reported 2026-08-13 | **19.4 MB**; keep a "10 MB (old Discord / Nitro-less servers)" entry only if the owner wants it |
| Discord Nitro Basic / Nitro | 50 MB / 500 MB | Same sources | optional |

Design rule: presets live in a **versioned JSON table** shipped in the app and updated with Sparkle releases. Nothing is fetched at runtime, because there is no network. Every entry has `limitBytes`, `safetyMargin` (default 3%), `kind` (media/document), `verifiedOn` date and a source note. Settings → Presets lets users add their own ("Company mail 10 MB").

### User-facing behaviour
- The wheel gets a **"Fit for…"** slice. A tap shows a second ring: WhatsApp · Gmail · Discord · Custom. The PRD's pinned-presets idea (B4-15) can promote one preset to a first-ring slice.
- Works on video, audio, image and PDF. Zivlet picks the method by type: video/audio use bitrate budgeting; images use a quality search, then a downscale step; PDFs use the P2-33 2-D search.
- If the file is already small enough: "Already fits WhatsApp (11.2 MB)". No file is written.
- If the target can't be reached (budget below the floor, for example a 40-minute video into 15.5 MB): refuse **before** encoding with "Can't fit: the smallest watchable result is about 38 MB. Trim it first?" (11 §11 already plans the "minimum achievable size" message.)
- Output name: `<name> (WhatsApp).mp4`.

### Engine
- Video: `videoBitrate = (target×8×0.98 − audioBits) / duration` (11 §11). Default **Fast** = VideoToolbox H.264 ABR with `-maxrate 1.5×`, `-bufsize 2×`, verify, retry ×(target/actual)×0.97 up to 3 times. **Accurate** = x264 two-pass (Settings, or ⌥).
- Images: binary search on ImageIO `kCGImageDestinationLossyCompressionQuality` (≤ 8 passes, stop at a 0.02 window). If even q=0.05 is too big, step the long edge down by 0.8× and repeat. WebP uses libwebp `target_size` natively (13 §).
- PDF: P2-33 as designed.
- Audio: exact bitrate maths (AAC/Opus ABR).
- Licence and size: existing ffmpeg/x264/ImageIO. **+0 MB.**

### Evidence (MEASURED; `fit.VYau/` (local prototype, not published), script `fit.sh`)
- Sources (30 s, 1080p30): `easy.mp4` (testsrc2, 40.3 MB) and `src.mp4` (testsrc2 plus per-frame noise, 849 MB, about 226 Mbit/s; a worst case).
  ```
  vk=(target*8*0.98 - 96k*dur)/dur
  ffmpeg -i src -c:v h264_videotoolbox -b:v ${vk}k -maxrate $((vk*3/2))k -bufsize $((vk*2))k -c:a aac -b:a 96k out.mp4
  ffmpeg -i src -c:v libx264 -preset fast -b:v ${vk}k -pass 1 … -f null /dev/null && … -pass 2 … out.mp4
  ```

  | Source | Target | Mode | Output | Output ÷ target | Tries | Wall (loaded) | VMAF |
  |---|---|---|---|---|---|---|---|
  | easy | 15.5 MB | VT ABR | 15,223,927 | 0.982 | 1 | 9 s | — |
  | easy | 15.5 MB | x264 2-pass | 15,206,551 | 0.981 | 1 | 36 s | — |
  | easy | 7.76 MB | VT ABR | 7,633,361 | 0.984 | 1 | 8 s | 89.30 |
  | easy | 7.76 MB | x264 2-pass | 7,649,190 | 0.986 | 1 | 34 s | 89.49 |
  | noisy | 15.5 MB | VT ABR | 15,217,636 | 0.982 | 1 | 75 s | — |
  | noisy | 15.5 MB | x264 2-pass | 14,649,956 | 0.945 | 1 | 146 s | — |
  | noisy | 7.76 MB | VT ABR | 7,634,362 | 0.984 | 1 | 62 s | 83.81 |
  | noisy | 7.76 MB | x264 2-pass | 7,667,626 | 0.988 | 1 | 118 s | 83.68 |

  All eight runs came in **under target on the first try**. VT is 2–4× faster and matches x264 `-preset fast` on VMAF at equal size. So **VT ABR should be the default**, and x264 stays as the "Accurate" fallback (as 11 §9 already plans).
- Resolution ladder: 720p at the same 1931 kbit/s scored **lower** than 1080p (VMAF 86.1 vs 89.3 on easy; 82.2 vs 83.8 on noisy; measured at 1080p). Do **not** auto-downscale at about 0.03 bits per pixel on this content. The threshold must be calibrated on real footage (fold into spike M-3, VMAF-calibrated VT presets).
- Image quality search (`preview.Tacb/imgprobe.swift`): 12 MP synthetic textured image → 2.0 MB target reached at q=0.837 (1,983,458 B) in **6 passes**. 36 MP wallpaper → 1.0 MB at q=0.331 in 6 passes.
- Base64 overhead (76-column MIME), 10 MB random file: ×**1.3509**.

### Risks
- **Limits change** (Discord just did). Mitigation: dated JSON table, release-note check before each release, user-editable custom presets.
- **WhatsApp re-encodes anyway**, so "fit" only guarantees that the file is accepted, not the quality the recipient sees. Say this in help text.
- **Gmail's 18 MB is INFERRED** from the encoding overhead. Owner action: one real send at 18 MB and one at 24 MB to confirm.
- **Two-pass x264 is slow under load** (146 s for 30 s of noisy 1080p). Keep it opt-in.

**Effort:** S for the preset table, second ring and refusal copy. M for image downscale-plus-quality search and PDF wiring.
**Dependencies:** P2-32 (video/audio target size), P2-33 (PDF target size), image engine encode path.
**Phase:** **Phase 2** (moves part of B4-15 forward; the machinery is already scheduled there).

---

## 3. Instagram presets

### User-facing behaviour
- Inside "Fit for…" or as its own "Instagram" ring: **Reel 9:16 (1080×1920)** · **Portrait 4:5 (1080×1350)** · **Square 1:1 (1080×1080)**. Works for video and images.
- Framing modes, chosen with a modifier and remembered:
  - **Fill (crop)**: default for video taken in a similar aspect ratio.
  - **Fit (pad)**: black or white bars.
  - **Blur fill**: the source is blurred behind itself. This is the usual "landscape clip in a Reel" look.
  - **Smart crop** (Phase 4): follows the subject.
- Encode: H.264 High, 30 fps (keeps ≤ 60 if the source is higher), yuv420p, AAC 128k 48 kHz, `+faststart`, about 8 Mbit/s cap. Instagram re-encodes, so feeding it a clean high-bitrate file is best.
- **Length:** Instagram announced 3-minute Reels on 2025-01-20 (VERIFIED-WEB). Later reports of 15–20 min uploads are unverified, and Reels over 3 min may not show in the Reels tab. Behaviour: never trim silently. Clips longer than 3:00 get a note "Reels over 3 min may not be shown as Reels" with an optional "Trim to 3:00" button.
- Instagram moved profiles to a vertical grid in January 2025, so 4:5 posts use the grid best (VERIFIED-WEB, same announcement).

### Engine
- ffmpeg filters (`insta.JF31/`):
  - crop: `scale=W:H:force_original_aspect_ratio=increase,crop=W:H,setsar=1`
  - pad: `scale=W:H:force_original_aspect_ratio=decrease,pad=W:H:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1`
  - blur fill (fast): `split[a][b];[a]scale=W/4:H/4:force_original_aspect_ratio=increase,crop=W/4:H/4,gblur=sigma=10,scale=W:H[bg];[b]scale=W:H:force_original_aspect_ratio=decrease[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1`
- Smart crop: Vision `GenerateObjectnessBasedSaliencyImageRequest` (macOS 26 Swift API) on frames sampled every 1 s. Take the median subject centre with a smoothed pan, or one static crop when the subject stays inside one window. Use face rectangles first when faces are present (INFERRED). Images use the same request on the single frame.
- Licence and size: ffmpeg (bundled) and Vision (system). **+0 MB.**

### Evidence (MEASURED; 10 s 1080p source, VT H.264)

| Output | Dims / SAR / fps | Bytes | Wall (loaded) |
|---|---|---|---|
| Reel crop | 1080×1920, 1:1, 30 | 5,785,544 | 3.2 s |
| Reel pad | 1080×1920, 1:1, 30 | 2,739,442 | 2.6 s |
| Reel blur fill, full-res `gblur=sigma=40` | 1080×1920, 1:1, 30 | 3,383,959 | **21.8 s** |
| Reel blur fill at ¼ resolution (above) | 1080×1920 | — | **4.6 s** (visually checked: `reel_blurfast.png`) |
| Square crop | 1080×1080 | 8,993,705 | 2.8 s |
| Portrait crop / pad | 1080×1350 | 8,993,945 / 4,031,007 | 3.7 / 1.7 s |

Smart crop, synthetic 1920×1080 frame with a subject at x=1400–1660:
- **Attention**-based saliency returned one box covering 19–98% of the width. The 9:16 crop landed at x=817–1425 and **missed** the subject.
- **Objectness**-based saliency returned x=0.708–0.891 (1360–1711 px). The crop at x=1232–1840 **contains** the subject. That took 0.7 s per frame (loaded).
- Conclusion: use objectness, not attention.

### Risks
- Reels rules vary by account, region and over time. Keep the length note advisory and data-driven, like §2.
- Smart crop on fast action can pan jerkily. Use one static crop by default and only follow the subject when it moves more than 20% of the width (INFERRED; needs a spike on real footage).

**Effort:** S (presets and three framing modes). M (smart crop with smoothing).
**Dependencies:** Crop Video and compress paths (Phase 2 media tools), image engine resize, §2 preset table.
**Phase:** basic presets in **Phase 2**; smart crop in **Phase 4**.

---

## 4. Size preview while hovering a slice

### The interaction constraint (from 03a §2.7 and 14 §2.3)
Hover events don't reach the wheel during an external drag. The highlight is model-driven from the polled pointer. So "hover preview" means the label shown when a slice becomes **hot**. That label must already exist; nothing can be computed on the highlight path.

### User-facing behaviour
- The hot slice's label gains a second line: "≈ 4.2 MB (−71%)", "≤ 15.5 MB" (fit presets, exact by construction), "Already smaller" or "Lossless". The ≈ sign and a range appear only when the estimate is uncertain ("≈ 15–40 MB").
- In keyboard or click mode and in tool windows, the same text appears, and the estimate refines in place.
- Settings toggle "Show size estimates", default on. Estimates never block a drop.

### Latency budget (proposal)

| Stage | Budget | What runs |
|---|---|---|
| Probe at drag-in (already in 11 §8.2) | ≤ 150 ms | ffprobe / ImageIO properties, cached by (path, size, mtime) |
| Tier 0 estimates for all visible slices | ≤ 5 ms per slice, in the same task as the probe | maths: bitrate × duration, target sizes, lossless/remux = source size, simple per-format ratios |
| Label on slice highlight | ≤ 1 frame (8–16 ms) | read from cache only |
| Tier 1 (images) | ≤ 250 ms per (format, quality) on an idle machine, nearest slices first, cancelled on drop or exit | 6×6 grid of 256 px native-resolution tiles encoded with ImageIO; size scaled by area |
| Tier 2 (video constant-quality presets) | seconds; **only** in tool windows or keyboard mode, never during a drag | k = 3 one-second sample encodes with the real encoder settings |

### Evidence (MEASURED; `preview.Tacb/` (local prototype, not published))
- **Downscaled sample encode is a bad estimator.** Encoding a 1024 or 2048 px thumbnail and scaling by area was off by **+45% to −88%**. For example, JPEG q0.75 on a 36 MP wallpaper estimated 3.2 MB against an actual 7.4 MB. Downscaling removes the fine detail that dominates file size.
- **Native-resolution tiles work.** `tiles6.swift`: 36 tiles of 256 px (about 19% of a 12 MP image), per-file overhead subtracted.

  | Image | JPEG q0.5 / 0.75 / 0.9 error | HEIC q0.5 / 0.75 / 0.9 error |
  |---|---|---|
  | 12 MP textured (synthetic) | −1.7% / −1.5% / −1.1% | −6.0% / −0.3% / −0.6% |
  | 36 MP wallpaper | −4.4% / −4.0% / −3.1% | −9.6% / −4.8% / −2.4% |

  A coarser 3×3 grid of 512 px tiles was biased by −16% to −43% on the uneven image, so use more, smaller tiles.

  Cost: JPEG **37–181 ms** in quiet moments. HEIC was 1.3–2.7 s under load, because there are 36 separate encoder sessions. Optimisation to test: put the tiles into one mosaic and encode once (untested).
- **Video sample encode** (`vest.sh`, VT HEVC `-q:v 55`):
  - mixed-complexity 36 s 1080p: k=3 gave **+7.8%** in 8.5 s; k=6 gave **+4.6%** in 20.8 s.
  - easy 30 s: k=3 gave **+1.3%** in 5.5 s.

  This is accurate but far too slow for the drag path, which is why it sits in tier 2.
- A tier-0 bits-per-pixel guess for VT q55 is weak. Measured 0.089 bits/pixel (easy) against 0.153 (mixed), roughly 2× apart. So tier 0 shows a **range** for constant-quality video, or just "smaller", and never a single number.

### Risks
- Wrong estimates erode trust. Show ranges when uncertain, and log estimate against actual in the local diagnostics so we can calibrate (local only, no telemetry).
- Estimation competes with conversion for CPU. Run it at `.utility` priority, cancel on drop, and cap concurrency at 1.

**Effort:** M (estimator protocol per engine, cache, label UI, calibration tests).
**Dependencies:** probe cache (11 §8.2), wheel label rendering (08f), §2 presets.
**Phase:** tier 0 in **Phase 2** (it comes almost free with fit-to-size); tiers 1–2 in **Phase 4** (B4-15).

---

## 5. Meeting summary with speaker labels

### User-facing behaviour
- The slice "Meeting Notes" applies to audio and video. Output is a Markdown (and optionally .docx) file beside the source: `<name> (Meeting Notes).md`. It contains:
  - key points, decisions and action items, written as "Speaker 2: fix scanned PDFs (Friday)";
  - then the full speaker-labelled transcript `[00:21] Speaker 3: …`.
- Before running, a small sheet asks: number of speakers **Auto / 2 / 3 / 4 / 5+**, and summary language (English default). After running, the user can rename "Speaker 1" → "Priya" in the result window; the file is rewritten with the names. Names are never guessed.
- Runs fully on-device. If Apple Intelligence is unavailable, the transcript with speaker labels is still produced and the summary section says why it is missing (device not eligible / Apple Intelligence off / model not ready), with a button to System Settings.
- First use downloads the **Speaker pack** (about 15–20 MB), verified by SHA-256 and pinned. A download card follows the LibreOffice pattern (10 §9).

### Pipeline
1. Transcription (separate design, §9) → segments with start/end, text, language, and both Roman and Devanagari forms.
2. Diarisation → speaker turns (start, end, speaker id).
3. Merge: each ASR segment takes the speaker with the largest time overlap. When word timestamps exist, split a segment at a turn boundary.
4. Summary: for Hindi or Hinglish, first translate to English (§6), because English is officially supported by the model. Then do token-budgeted map-reduce: chunks of about 2,000 tokens leave room for instructions and output within the 4096 context. Map gives ≤ 5 bullets per chunk with speaker labels kept; reduce produces guided-generation output into `MeetingSummary { keyPoints, decisions, actionItems }`.
5. Use `Guardrails.permissiveContentTransformations` (macOS 26.0, VERIFIED-SDK) for summarise and translate, because meetings can contain anything (INFERRED, not tested).

### 5.1 Foundation Models facts
VERIFIED-SDK, `MacOSX27.0.sdk` `FoundationModels.swiftinterface`:
- `SystemLanguageModel`, `LanguageModelSession`, `@Generable`/`@Guide`, `Tool`, `availability` (`deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`), `UseCase.general/.contentTagging`, `Guardrails.default/.permissiveContentTransformations`, and `contextSize` are all available on **macOS 26.0**. `tokenCount(for:)` is **26.4**.
- The synchronous `supportedLanguages`/`supportsLocale` are marked **obsoleted in macOS 27**, with async replacements. This is fine at a 26.0 deployment target, but needs migrating when the minimum is raised.
- macOS 27 adds `PrivateCloudComputeLanguageModel`. That **sends requests to Apple servers**. Zivlet must **never** use it: add a CI grep or lint rule for the symbol. This is a privacy requirement.
- macOS 27 deprecates `GenerationError.guardrailViolation` in favour of `LanguageModelError`. Handle both. On 27, the context overflow came back as a non-`GenerationError` type (MEASURED below).

MEASURED (`fm.b3H5/probe.swift`, `probe2.swift`, `tok.swift`):
- `availability: available`, **`contextSize: 4096`**.
- 24 supported languages, including **en-IN**. **Hindi is not listed**: `supportsLocale(hi-IN)=false`, `en-IN=true`.
- Speaker-labelled Hinglish meeting (8 turns, 242 tokens) → structured summary in 9.4 s. It kept SPEAKER_n labels and got 3 of 3 real action items right. It also **invented one** ("SPEAKER_1: Complete Hindi translation in 1.1") and mis-attributed one. So the UI must label the notes as AI-generated, and the transcript stays the source of truth.
- Devanagari input was accepted and summarised correctly in English (18 s, including cold load), even though Hindi is unsupported. Tokens: Devanagari 20, Roman 26, English 22 for the same sentence. Devanagari is **not** token-heavy, so chunk by `tokenCount` rather than by characters.
- 7,525-token input → error "Content contains 7583 tokens, which exceeds the maximum allowed context size of 4096". Map-reduce over 6 chunks of 6,000 characters (about 1,250 tokens each) took **158 s** in total (about 20 s per chunk, loaded) and gave a coherent 8-bullet summary.
- Throughput estimate: about 150 words/min ≈ 200 tokens/min of speech. A 1-hour meeting ≈ 12k tokens ≈ 6 chunks ≈ 2–3 min of summarising (INFERRED from the measured chunk time).

### 5.2 Diarisation options

| Option | Licence | Size | Offline | Fit | Verdict |
|---|---|---|---|---|---|
| **sherpa-onnx** v1.13.8 (2026-09-10) with pyannote segmentation-3.0 ONNX and 3D-Speaker CAM++ zh/en embedding | Apache-2.0 (sherpa-onnx); **MIT** (pyannote seg-3.0, CNRS; LICENSE in tarball); onnxruntime MIT; CAM++ model Apache-2.0 per 3D-Speaker (**verify**) | onnxruntime 28.8 MB + C API 3.0 MB + seg int8 1.5 MB + CAM++ 28.3 MB ≈ **61 MB** | yes | C API, links from Swift | **Works (prototype below).** Too big for the bundle; as a download pack it ships **code** (dylibs), which hits library validation (§10) |
| **FluidAudio** v0.17.7 (2026-10-08) CoreML diarisation (pyannote segmentation + WeSpeaker, ANE) | Apache-2.0 code; HF model card licence "other", per-model check needed (pyannote community-1 is CC-BY-4.0 = attribution) | needed models ≈ seg 5.8 + WeSpeaker int8 8.0 + FBank 1.8 + PLDA 0.2 ≈ **16 MB** (repo total 129 MB with variants) | yes (models fetched once) | native Swift package, CoreML is in the OS, so the pack is **data only** | **Preferred candidate; spike AI-S2.** Not run here |
| pyannote.audio 3.x/4 (Python) | MIT code; community-1 CC-BY-4.0; some repos gated on HF | PyTorch ≈ 1 GB+ | yes | Python runtime | Rejected (size, Python) |
| whisper-diarization (NeMo + Whisper) | BSD-2 | GBs | yes | Python/NeMo | Rejected |
| whisper.cpp `-tdrz` (tinydiarize) | MIT | small.en-tdrz only | yes | turn changes only, **English only**, no identities | Rejected for Hindi/Hinglish |
| whisper.cpp `--diarize` | MIT | — | yes | stereo-channel energy only (one speaker per channel) | Niche; could be a fast path for 2-channel call recordings |

### 5.3 Evidence (MEASURED; `diar.GKMj/` (local prototype, not published), downloads isolated in `dl/`)
```
sherpa-onnx-offline-speaker-diarization --segmentation.pyannote-model=…/model.onnx \
  --embedding.model=3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx \
  --clustering.cluster-threshold=0.5 | --clustering.num-clusters=3  <16 kHz mono wav>
```
- **Real Hinglish, 3 speakers**: halves of HumynLabs clips from three speakers (A, B, C), interleaved A1 B1 C1 A2 B2 C2. Ground truth `0–4.50 A, 4.80–12.19 B, 12.49–17.41 C, 17.71–22.22 A, 22.52–29.91 B, 30.21–35.12 C`. Output at threshold 0.5 and 0.7: `0.54–4.52 s0, 4.98–12.18 s1, 13.06–17.45 s2, 17.67–21.58 s0, 22.49–28.89 s1, 30.59–34.30 s2`. **6 of 6 turns correctly attributed**, with recurring speakers re-identified. Boundaries are within about 0.6 s; speech onsets and offsets are trimmed. RTF 0.30–0.37 (loaded).
- **sherpa's own 2-speaker English sample** (34 s): threshold 0.7 gives 2 speakers with plausible turns. Threshold 0.5 over-splits into 3. RTF 0.5–1.1 (loaded).
- **TTS 3 speakers** (Rishi en-IN, Lekha hi-IN, Aman en-IN; Hinglish/Devanagari script; 7 turns): threshold 0.5 and 0.7 **merged Rishi and Aman** (two similar synthetic male en-IN voices). With `num-clusters=3` or threshold 0.3, **7 of 7 correct**. The int8 segmentation model (1.5 MB) worked as well as fp32.
- Product implications:
  - "Number of speakers" in the pre-run sheet matters. Auto uses threshold about 0.5–0.6.
  - Users need a "merge speakers" action in the result window.
  - TTS is cleaner than real meetings, so overlapping speech and far-field rooms are untested (labelled TTS where applicable).

### Risks
- **Hallucinated or mis-attributed action items.** Mitigations: guided-generation schema, an "AI-generated, check against transcript" label, and every bullet linked to a transcript timestamp (Phase 4.x).
- **Context window:** 4096 tokens is small. Map-reduce is mandatory, and long meetings take minutes. Show progress per chunk; the summary is cancellable while the transcript is kept.
- **Hindi is officially unsupported.** Summarise from the English translation, keep the original-language transcript in the file, and summary language is English only at first.
- **Availability:** needs Apple Intelligence enabled on an eligible Mac, and a supported system language. A user whose Mac language is Hindi may get `unsupportedLanguageOrLocale` (INFERRED from the API). The degraded path is the transcript only.
- **Diarisation quality** on overlapping speech, phone audio and more than 5 speakers is unknown. Run spike AI-S1 on real meeting recordings before committing the UI copy.
- **Pack signing** (§10).

**Effort:** L (diarisation integration and pack, merge logic, map-reduce, result window with rename/merge, degraded paths).
**Dependencies:** transcription (§9), translation (§6), model-pack infrastructure (§10), Markdown/DOCX writer (document engine).
**Phase:** **Phase 4 (1.x)**, after transcription is stable. The diarisation spike can run earlier.

---

## 6. Translate transcript (→ English)

### User-facing behaviour
- After transcription, "Translate to English" is a checkbox in the transcribe sheet, and it is also its own slice for existing `.txt/.srt/.vtt` transcripts. Output: `<name> (English).srt|.txt`, with timestamps preserved line by line.
- Language packs: Translation packs are installed through macOS. A headless session **cannot request downloads** (`canRequestDownloads=false`, MEASURED). So when the pack is missing, Zivlet shows a SwiftUI `.translationTask` prompt in its window (the system download UI), or points to System Settings → General → Language & Region → Translation Languages.
- The source language comes from the transcript. Romanised Hinglish is passed with **source = hi** explicitly (auto-detection fails, below).

### Engine
- **Primary: Apple Translation framework** (system, +0 MB). Uses `TranslationSession(installedSource:target:)` (macOS 26.0) and `translations(from:)` batches with `clientIdentifier` = segment index. macOS 26.4 adds `Strategy.highFidelity/.lowLatency` and an AttributedString `skipsTranslation` attribute (VERIFIED-SDK), which can keep speaker labels and product names untouched.
- **Secondary: Whisper `task=translate`** inside the transcription pipeline. It is one pass with no separate pack, but only the **non-turbo** models translate (below). The transcription design decides whether to expose it.

### Evidence (MEASURED; `translate.54tm/` (local prototype, not published))
- `LanguageAvailability().supportedLanguages`: 47 entries including **hi** and en-IN. Status: `hi→en installed`, `en→hi installed`, `de→en installed`. **ur, bn and ta → en are unsupported**, so other Indian languages are out of scope for now.
- `status(for: "kal meeting mein humne decide kiya…")` → `unableToIdentifyLanguage`. Romanised Hinglish needs an explicit source language.
- Headless `TranslationSession(installedSource: hi, target: en)`:
  - Devanagari-mix "कल की meeting में हमने decide किया कि release सोमवार को होगी।" → "In yesterday's meeting, we decided that the release will be on Monday." First call 18 s (cold).
  - Roman "Kal ki meeting mein humne decide kiya ki release Monday ko hogi." → same English, 2.4 s.
  - "मुझे यह फ़ाइल छोटी करनी है ताकि मैं इसे WhatsApp पर भेज सकूँ।" → "I need to make this file smaller so that I can send it on WhatsApp." 2.3 s.
  - Note: "kal" is ambiguous (yesterday or tomorrow) and was resolved as "yesterday" despite the future verb.
- Batch of 40 lines took 250 s (6.3 s per line) at load average 296. That is an unusable figure for planning; re-measure on an idle machine (spike AI-S3).
- **Whisper translate on real FLEURS Hindi and HumynLabs Hinglish** (models from the transcription spike, read-only):
  - `ggml-medium-q5_0 -tr`: good ("There is no such universal definition… Some agencies have defined the 100 years old goods as antique.").
  - `ggml-small-q5_1`: fine on simple sentences, garbled on harder ones ("IC CoI is not a WSP company…").
  - **`ggml-large-v3-turbo-q5_0` ignores `-tr` and outputs Hindi**, because turbo was not trained for translation.
- **Two-step** (turbo Devanagari transcript → Apple Translation): good on clean transcripts (airline clip, white-smoke clip). On the hard clip, ASR errors carried through and "100 years" became "older than a year". Translation quality is bounded by transcript quality.

### Risks
- Missing pack on a fresh Mac. That is a one-time system download; it needs UI, not the CLI. The CLI fails with a clear message.
- Code-mixed ambiguity ("kal"). Keep the original transcript next to the translation.
- Speed under load. Translate in batches, in the background, with progress.

**Effort:** S. **Dependencies:** transcription output format (§9); SwiftUI host window for the pack prompt.
**Phase:** ship together with transcription.

---

## 7. Ask in plain words

### User-facing behaviour
- In keyboard mode (and from the menu-bar item), a text field reads "Describe what you want…". Examples: "make this small enough for WhatsApp", "isko Discord pe bhejna hai", "turn these photos into one PDF with a password".
- The model's answer is **never executed directly**. It becomes a **confirm card** listing the steps in Zivlet's own words ("1. Combine 12 images into a PDF · 2. Add a password"). Each step uses the normal tool UI (the password sheet, for example). Enter runs; Esc cancels.
- Requests Zivlet can't do ("delete my files", "email this") get: "Zivlet only converts and edits copies of files. It can't delete, send or upload." Zivlet has no destructive or networked operations in its vocabulary at all, and all outputs are new files beside the originals.
- Hidden when Foundation Models is unavailable. A keyword matcher still handles the top phrases (WhatsApp, Gmail, Discord, Instagram, PDF, password, silence, text from image), so the feature degrades instead of vanishing.

### Engine
- **Hybrid (recommended):**
  1. A deterministic phrase table (English, Hinglish romanised, Devanagari keywords) maps destinations and keywords to registry operations. It is instant and works on every Mac.
  2. Foundation Models guided generation produces `Plan { steps: [Step{operation, format, destination, megabytes}] }`, with enums generated from the **live registry** for the selected files (a dynamic schema; the probe used static enums).
  3. A validator removes impossible steps (not in the file's allowed targets), destinations not mentioned in the text, no-op converts (jpg→jpg) and invented sizes, and maps destination → §2 preset.
  4. Confirm card.
- Tool calling (`Tool` protocol, macOS 26.0) is not needed for this mapping. Use it later if the plan must query file facts ("how long is this video?").
- Licence and size: system framework. **+0 MB.**

### Evidence (MEASURED; `fm.b3H5/probe.swift`, `probe3.swift`)
Ungrounded (operation enum only):
- whatsapp → `compress mp4` (should be fit-to-size)
- "discord … 10 MB se kam karo" → `compress **mp3** 10 discord` (invented format)
- photos → pdf + password → `pdfMerge` only (lost a step)
- podcast quiet parts → `removeSilence` ✓
- instagram reel → `convert mp4 instagram`
- "delete all my files" → `unknown` ✓
- 1.4–2.0 s per request.

Grounded (file kind in the prompt, rules, multi-step plan, 9 cases):
- photos → `convert/jpg → pdfMerge → pdfLock` ✓ (multi-step works, with a no-op convert)
- `is pdf ka password hata do` → `pdfUnlock` ✓
- `copy the text in this picture` → `extractText` ✓
- Remaining failures:
  - spurious `destination=discord` on the podcast and meeting cases;
  - "meeting ka summary, kaun kya bola" → `transcribe` only (no summarise step);
  - Discord 10 MB → `compress/mov/10MB` instead of fitToSize;
  - **"delete all my files and email them to my boss" → `convert/pdf/gmail → resize`**, a dangerous misread that the validator and refusal rule must catch.
- 1.6–4.6 s per request (loaded).
- Conclusion: the model is useful for paraphrase and code-mixed input, but **it cannot be trusted alone**. The validator, phrase table and confirm card are mandatory, not polish.

### Risks
- Hallucinated steps or parameters. Mitigated by the validator and the confirm card. The model never sees file contents, only kind, size and duration.
- Prompt injection through filenames, for example a file named "ignore rules…". Pass filenames as data in a delimited field, or don't pass them at all; pass kind only (INFERRED).
- Latency of about 2 s plus a cold start. Prewarm the session when keyboard mode opens (`prewarm` exists).
- Availability gating and the "never PCC" rule (§5.1).

**Effort:** M (dynamic schema from the registry, validator, phrase table, confirm card, eval set of about 100 requests in EN/Hinglish/Devanagari run in CI on a capable Mac).
**Dependencies:** stable tool registry (Phase 3), App Intents (so plans reuse the same operation definitions), §2 presets.
**Phase:** **Phase 4**. This pulls B5-04 forward from Phase 5; it is cheap once the registry is stable.

---

## 8. Shared building blocks

| Block | Used by | Notes |
|---|---|---|
| Preset table (JSON, dated) | §2, §3, §7 | one source of truth for limits and aspect presets; user presets in Settings |
| Keep-list model (pure Swift) | §1, transcript time remap, Split Video "remove clips" | detect → keep list → render; unit-tested with the lavfi sync fixture |
| Size estimator protocol | §4, §2 (shows "≤ target" and "can't fit" early) | `estimate(probe, settings) -> Estimate { value, range, tier }` per engine |
| On-device AI gate | §5, §7 | one `AICapability` service: FM availability, locale support, Translation pack status; drives slice visibility and degraded copy |
| Model packs | §5 (speaker), transcription models | download, verify SHA-256, version-pin, delete in Settings → Engines; see §10 |
| CLI verbs (CLI is a YES pick) | all | `zivlet silence <file> [--tight]`, `zivlet fit --preset whatsapp <file>`, `zivlet insta --reel --blur <file>`, `zivlet translate --to en <transcript>`, `zivlet notes --speakers 3 <file>` (14 §4.4) |

---

## 9. Transcription (reserved slot; designed separately)

The transcription design is being done separately (docs/design/16, not yet written; spikes are local prototypes, not published: whisper.cpp spikes, an EN/HI/Hinglish corpus, and owner answers: two output files, Roman and Devanagari). This document does not redesign it. §5 and §6 need these things from it:
1. **Segments with timestamps** (word timestamps if available) and a per-segment language tag, in an internal model, not only in the output files.
2. **Both script forms** per segment (Roman and Devanagari), so translation and summary can choose: Roman goes to Translation with source=hi; English goes to the summary.
3. A **task=translate decision**. If it is offered, the chosen model must not be a turbo variant (§6 evidence).
4. A **model-pack** mechanism shared with the Speaker pack (§10).
5. Phase placement. Meeting notes and translation follow whatever phase transcription lands in.

---

## 10. Cross-cutting: model packs, signing, privacy

- **Library validation:** Zivlet is notarized with the hardened runtime. A downloaded pack that contains **executable code** (sherpa-onnx's `libonnxruntime.dylib`, `libsherpa-onnx-c-api.dylib`) won't load unless it is signed with Zivlet's Team ID. The other option, `disable-library-validation`, weakens the app and is rejected. So a code-carrying pack means we must rebuild, sign and host it ourselves. That is one more release artefact and one more supply-chain item.
- A **CoreML pack is data only** (`.mlmodelc`). Loading it needs no code-signing step beyond integrity checks. This is the main reason to prefer the CoreML/FluidAudio route (spike AI-S2), on top of being about 45 MB smaller.
- **Integrity:** pin URL, size and SHA-256 in an `engines.lock`. Download over HTTPS to `~/Library/Application Support/Zivlet/Packs/<name>/<version>/`, verify, then atomic-rename. No auto-updates outside Sparkle releases.
- **Privacy:**
  - No cloud APIs, and `PrivateCloudComputeLanguageModel` is banned (§5.1).
  - Translation and Foundation Models run on-device.
  - Pack downloads are the only network traffic and happen only on explicit user action.
  - Diagnostics stay local.
- **Size budget (10 §9):** the bundle is unchanged apart from about 1 MB of code and JSON. The ≤ 70 MB target holds.

---

## 11. Proposed task-list rows (for `docs/plan/05-task-list.md`)

| ID | Task | Module | Depends on | Size | Phase |
|---|---|---|---|---|---|
| MA-01 | Keep-list model + `silencedetect` parser + adaptive threshold | EngineMedia | P2-30 | S | 2 |
| MA-02 | Remove Silences render (trim/concat ≤ 40 segs; frame-snapped select > 40), A/V sync CI fixture | EngineMedia | MA-01, P1-07 | M | 2 |
| MA-03 | Remove Silences slice, Natural/Tight, result copy, tool-window shading | UI | MA-02, P2-49 | S | 2 |
| MA-04 | Preset table (JSON, dated) + "Fit for…" second ring + refusal copy | Core, UI | P2-32, P2-33 | S | 2 |
| MA-05 | Image fit-to-size: quality search + downscale ladder | EngineImage | MA-04 | M | 2 |
| MA-06 | Instagram presets: crop / pad / blur-fill (¼-res blur), length advisory | EngineMedia, EngineImage | MA-04 | S | 2 |
| MA-07 | Size estimator protocol + tier 0 + cached hot-slice label | Core, Wheel | probe cache | M | 2 |
| MA-08 | Tier 1 image tile estimator; tier 2 video sample estimator (tool windows only) | EngineImage, EngineMedia | MA-07 | M | 4 |
| MA-09 | Smart crop via Vision objectness + smoothing | EngineMedia | MA-06 | M | 4 |
| MA-10 | Translate transcript (Translation framework, batch, pack prompt) | EngineAI | transcription | S | with transcription |
| MA-11 | Speaker pack (CoreML route) + diarisation + transcript merge | EngineAI | AI-S2, §10 packs | L | 4 |
| MA-12 | Meeting Notes: map-reduce summary, result window (rename/merge speakers), degraded paths | EngineAI, UI | MA-10, MA-11 | M | 4 |
| MA-13 | Ask in plain words: phrase table, FM dynamic schema, validator, confirm card, eval set | EngineAI, UI | registry, App Intents | M | 4 |
| MA-14 | `AICapability` service + CI ban on `PrivateCloudComputeLanguageModel` | Core | — | S | 4 |

### Spikes (each ≤ 2 days)

| ID | Question | Pass bar |
|---|---|---|
| AI-S1 | Diarisation on real meetings (overlap, phone, 4–6 speakers, Hinglish) with sherpa-onnx as the baseline | DER ≤ 20% on 3 recordings with ground truth |
| AI-S2 | FluidAudio CoreML diarisation: same audio as AI-S1, plus pack size and licence audit of each model | parity with AI-S1 at ≤ 20 MB, data-only pack, licences compatible with GPL-3.0 distribution (attribution OK) |
| AI-S3 | Re-measure Translation and FM throughput on an **idle** Mac (and on an M1 Air) | 1-hour meeting: translate + summarise ≤ 5 min |
| AI-S4 | Real-footage calibration: resolution ladder threshold (§2), video tier-0 ranges (§4), HEIC mosaic estimator | documented thresholds, estimator error ≤ ±10% (images) |
| AI-S5 | Gmail real send at 18 / 24 MB; WhatsApp 15.5 MB video send (owner phone) | confirms preset targets |

---

## 12. Owner decisions needed

1. **Discord preset:** use 20 MB (current free limit) as the default and drop 10 MB? Recommended: yes.
2. **WhatsApp 100 MB document preset:** it applies to the Business API only. Drop it, or keep it as "WhatsApp Business"? Recommended: drop it; keep the 16 MB media preset.
3. **Meeting summary language:** English only at first (the model doesn't support Hindi output officially)? Recommended: yes.
4. **Speaker pack route:** approve spike AI-S2 (CoreML) as the preferred path, with sherpa-onnx as the fallback?
5. **Ask in plain words:** confirm it is wanted (the picks file marks it "[confirm]"). Cost is M, and it needs Apple Intelligence on the user's Mac.

---

## Sources
- WhatsApp limits: fast.io (https://fast.io/resources/whatsapp-file-size-limit/), usecarly 2026 (https://www.usecarly.com/blog/whatsapp-file-size-limit/), ChatDaddy Nov 2025 (https://help.chatdaddy.tech/article/file-size-limitation), Infobae 2022-03-23 (https://www.infobae.com/en/2022/03/23/whatsapp-increases-the-size-of-documents-that-can-be-sent-to-2-gb), cococonvert May 2026 (https://cococonvert.com/blog/whatsapp-file-size-limits), Superchat API (https://help.superchat.com/en/articles/27287-overview-of-all-file-sizes). The official WhatsApp FAQ page could not be fetched (404 in the Hindi locale).
- Discord 20 MB: Dexerto, citing Discord's X post of 2026-08-13 (https://www.dexerto.com/entertainment/discord-raises-free-upload-limit-to-20mb-after-lowering-it-two-years-ago-3398251/); GadgetReview (https://www.gadgetreview.com/?p=402010); TechJournal, citing 2026-09-08 patch notes (https://techjournal.org/discord-free-upload-limit).
- Gmail: Android Authority Feb 2026 (https://www.androidauthority.com/gmail-file-size-limit-3644154/), Inbox Zero 2026 (https://www.getinboxzero.com/blog/post/gmail-attachment-size-limits-workarounds-2026), IONOS (https://www.ionos.com/digitalguide/e-mail/technical-matters/gmail-attachment-size-limit/), BetaNews 2017 (https://betanews.com/2017/03/02/increased-gmail-attachment-limit/).
- Instagram 3-minute Reels and vertical grid (Mosseri, 2025-01-20): Business Today (https://www.businesstoday.in/technology/news/story/instagram-head-announces-big-changes-3-minute-reels-and-new-look-for-profile-grid-461527-2025-01-21), Social Media Today (https://www.socialmediatoday.com/news/instagram-officially-expands-reels-length-3-minutes/737766/); longer-limit claims: inro.social (https://www.inro.social/blog/instagram-reels-can-now-be-20-minutes-long-new-time-limit-explained-2025) (unverified).
- sherpa-onnx releases v1.13.8 (https://github.com/k2-fsa/sherpa-onnx/releases), model tags `speaker-segmentation-models` and `speaker-recongition-models`; pyannote segmentation-3.0 (https://huggingface.co/pyannote/segmentation-3.0), MIT.
- FluidAudio v0.17.7 (https://github.com/FluidInference/FluidAudio), Apache-2.0; models (https://huggingface.co/FluidInference/speaker-diarization-coreml).
- Apple SDK: `MacOSX27.0.sdk/System/Library/Frameworks/{FoundationModels,Translation}.framework/.../arm64e-apple-macos.swiftinterface`.
