# 17 — Zivlet feature roadmap: the owner's 2026-10-21 picks merged into the phases

> Imported into the repository on 2026-10-21 from the roadmap drafts; approved by the owner the same day
> (see [00-decisions.md](00-decisions.md), 2026-10-21 section). The product name is Zivlet.
> Prototype folders named `<name>.XXXX/` are local prototypes and are not published.
> File map: PRD additions are in [01b-prd-additions.md](../plan/01b-prd-additions.md); task rows are in
> [05-task-list.md §9](../plan/05-task-list.md); the challenge pass is [17-roadmap-challenge.md](17-roadmap-challenge.md);
> cluster reports are [17a-pdf](17a-pdf.md), [17b-lock](17b-lock.md), [17c-image](17c-image.md),
> [17d-media-ai](17d-media-ai.md) and [17e-app](17e-app.md).

Date: 2026-10-21. Status: **approved by the owner 2026-10-21** (00-decisions); its §14 decisions are adopted at their
recommendations.

Companions: [01b-prd-additions.md](../plan/01b-prd-additions.md) (FR-90…FR-141, NFR-21…24) and
[05-task-list.md §9](../plan/05-task-list.md) (05-format rows, milestones M5a/b/c, effort tally).

> **Update 2026-10-22** (owner, after M4; [00-decisions.md](00-decisions.md) OWN-PLAN-3, OWN-HUD-1): the notch Drop Box
> and the new **Notch HUD** lead the first beta (§4.2); the notch tray leaves the cut list; picker style and place stay
> last. §1, §2, §4–§9, §10, §12 and §14 are updated; the earlier wording is in git history.

Inputs:
- `docs/design/00-decisions.md`, `10-tech-strategy.md` (§9 size, §10 licences, §12 roadmap), `12`, `13`, `14`;
  `docs/plan/01-prd.md`, `02-architecture.md`, `03a`, `03b`, `05-task-list.md`, `09-m3-record.md` (M3 is code complete).
- The owner's picks with interpretation: [00-decisions.md](00-decisions.md) (2026-10-21 section).
- Cluster research with prototypes (docs/design 17a–17e): `17a-pdf.md`, `17b-lock.md`, `17c-image.md`, `17d-media-ai.md`, `17e-app.md`.
- Transcription: [16-transcription.md](16-transcription.md) and [16a-transcription-evidence.md](16a-transcription-evidence.md)
  (imported 2026-10-22) fill the slot reserved in §7.

Principles held throughout:
- local and offline;
- no telemetry, no cloud APIs (Apple's Private Cloud Compute model is banned by lint);
- installed size target ≤ 70 MB, with large models as optional verified downloads;
- GPL-3.0-or-later;
- clean room: no code or strings from the reference app or Open-Tangerine, and prior-art shelf/notch apps are described only in our
  own words.

Evidence labels come from the cluster reports: PROBED/MEASURED (run on the dev Mac, macOS 27, often under heavy load),
DOC, EST. Every PROBED number still has to be re-run on macOS 26.x.

---

## 1. Summary

**What changes.**
- Every YES pick gets a phase, a module, an engine, an effort, a licence and a size cost (§5).
- Phase 1 (to M4, private alpha) is **unchanged**. One pure task, the catalog cap rule (P2-100), may start during Phase 1.
- Phase 2 becomes **three public betas**, ordered by the owner's priorities:
  - **0.5:** first the Drop Box with the notch tray and the Notch HUD (owner, 2026-10-22), then OCR copy-text,
    lock/unlock for Office/ZIP/any file, and the PDF basics (lock, unlock, merge, split, compress);
  - **0.6:** images, the top three multi-file features (combine into one PDF, reel, stitch), share presets, remove
    silences;
  - **0.7:** documents, custom wheels, history, archives, searchable PDF, blank pages, page size.
- Phase 3 (1.0) adds visual signatures; JPEG XL (only if the size gate allows); legacy Office unlock; custom-wheel
  colours and import/export; the full CLI; and **transcription** ([16-transcription.md](16-transcription.md)), with
  translation.
- Phase 4 (1.x) adds meeting notes with speaker labels, "ask in plain words", digital signatures (gated), smart crop and
  lossless page resize.

**Cost.**
- About **27 engineer-weeks** are added to Phase 2, on top of its original 8–10 weeks.
- About 8.5 weeks are added to each of Phases 3 and 4.
- All figures assume one engineer and are ESTIMATES (05 §9.10).
- §4.3 is the cut list if Phase 2 must stay shorter.

> [challenge] **Units are mixed.** The 27 weeks come from the S = 1 / M = 3 / L = 7.5 day tally. The "8–10 weeks" is
> 10 §12's calendar estimate. Using the same tally, 05's original 47 Phase 2 rows come to **156 engineer-days
> (≈ 31 weeks)**, and the 2A originals alone to 38 days (≈ 7.6 weeks, not "≈ 3"). The 136.5 added days plus 14 spike
> days therefore make Phase 2 **about double (+ 97 %)**, not "nearly quadruple". In 10 §12's calendar terms (8–10 weeks
> for 156 days), the additions are about **+8–10 calendar weeks, so Phase 2 takes ≈ 16–20 weeks** (≈ +9–11 / 17–21 weeks after the re-sizes in 17-roadmap-challenge §3). Each public beta
> also needs about one week of stabilisation (notarised build, Sparkle beta feed, regression pass, fixes) that the
> one-day P2-119/139/159 rows leave out. M1–M3 were built by agents in days, so read every figure as **relative**
> size, not as a date. See 17-roadmap-challenge §3.

**Size.**
- With no gated items, the bundle grows by about 2–3 MB, to about **71–72 MB expected**. That is above the 70 MB target
  and below the 85 MB hard gate.
- JPEG XL (+2.5–3.3 MB) and a 7-Zip helper (+2–3 MB) are owner-gated.
- Speaker models (~16 MB) and transcription models are downloads, never part of the bundle (§9).

> [challenge] **Do not re-baseline to 72 MB.** swift-argument-parser is already in 10 §10's dependency table, and the
> CLI is already inside 10 §9's "Swift code: app, … CLI" row (6–14 MB). Counting it again as +0.83 MB double-counts it.
> The corrected ungated delta is **+1.4–2.8 MB, ≈ 70.2–71.6 MB expected**. NFR-7 (≤ 70 MB target) stays. If the measured
> DMG at P1-52 is over 70 MB, the owner decides (OWN-SIZE-1) whether to accept the overage or to cut it (for example,
> Noto subset to Devanagari + Latin only, or the CLI's JSON/NDJSON layer kept in `ZivletCLIKit` only). The ±4 MB
> uncertainty in the Swift-code row is larger than every addition here combined.

**Licences.** Nothing new conflicts with GPL-3.0-or-later. Every addition is one of:
- a system framework;
- our own code;
- an already-planned dependency (qpdf Apache-2.0, libarchive BSD-2, oxipng MIT, imagequant GPL-3.0+);
- a small permissive one (ArgumentParser Apache-2.0, Noto Sans Devanagari OFL-1.1, libjxl BSD-3).

RAR creation and unRAR stay out (§10).

---

## 2. The owner's picks and where they landed

| Owner said (2026-10-21, as interpreted in 00-decisions) | Verdict | Where |
|---|---|---|
| Copy text from image (OCR, incl. Hindi): "very important" | YES, **priority 1** | P2a: P2-103/104 |
| Lock/unlock other files (Word, Excel, PowerPoint, ZIP; CSV/others via encrypted ZIP), locally: "very important" | YES, **priority 1** | P2a: P2-101…114 |
| PDF: lock, unlock, compress, sign, merge, unmerge, cut blank pages, resize, make searchable | YES, **priority 1** (suite marked important) | P2a (lock, unlock, compress, merge, split), P2c (searchable, blank, page size), P3 (sign) |
| Batch rename and batch resize images: "important" | YES, priority 2 | P2b: P2-123/124 |
| Multi-file: combine anything into one PDF ⭐, photos+videos reel ⭐, stitch ⭐ (owner order 1-2-3) | YES, priority 2 | P2b: P2-120/121/122 (Office inputs to Combine in P2c) |
| Multi-file: images → GIF, contact sheet, join audio, batch actions, ZIP all; collage already planned | YES | P2b (GIF, sheet, join, batch), P2c (ZIP), P3-23 (collage, unchanged) |
| Archives: every format, both directions, peek inside, convert any→any | YES (RAR creation: no, §10) | P2a (extract all), P2c (create, peek, convert), P3 gate (encrypted 7z) |
| JPEG XL output, smaller PNG ("nice quality") | YES | P2b (PNG), P3 size-gated (JXL) |
| Remove background | YES | P2b one tap, P3 picker, P4 refine |
| Fit-to-size presets (WhatsApp, Gmail, Discord), Instagram presets | YES | P2b: P2-131…133 |
| Size preview while hovering a slice | YES | P2c tier 0, P4 tiers 1–2 |
| Remove silences | YES | P2b: P2-134/135 |
| Custom wheels: choose slices and order ("which we need and which we don't"), colours | YES | P2c v1, P3 v2 |
| History of recent conversions | YES | P2c: P2-145 |
| Command-line tool | YES | P2c subset, P3 complete |
| Drop box → notch tray ("a big box… temporary") | YES; first in 0.5 (owner, 2026-10-22) | P2a: P2-197 spike, P2-141/142/143 + P2-55 |
| Notch HUD: progress and results at the notch (2026-10-22 pick) | YES | P2a: P2-115 NotchIsland core, P2-116 Notch HUD |
| Transcription (EN/HI/Hinglish, two script files) | YES, designed in 16 | P3 wave 3B (§7) |
| Translate transcript, meeting summary with speakers | YES | P3 (translate), P4 (notes) |
| Ask in plain words | YES **[confirm]** | P4: P4-102 |
| Watch folders; video/audio extras group (highlights, extract audio, normalise, screen recording → GIF) | LATER | not scheduled (§13) |
| Text to speech, filler-word removal, burn-in subtitles, "Replace" | NO | not scheduled |

> [challenge] **Two picks rest on interpreting the dictation. Confirm them with the owner (OWN-PICK-1):**
> - "JPEG, Excel, and smaller PNG output" was read as **JPEG XL + smaller PNG**. That reading fits the image context,
>   but "Excel output" could be literal.
> - "removable PDF background" was read as **image** background removal. No plan item removes a *PDF* background,
>   watermark or scan tint.
>
> Both readings come from the interpreted picks (00-decisions, 2026-10-21), not from the owner directly.

---

## 3. Sequencing rules used

1. **Owner priority first, then dependencies.** Within a wave, rows follow the priority tiers in §2. A row only moves
   earlier when its dependencies are already in that wave.
2. **Build shared pieces once, in the wave that first needs them.** Examples: password sheet (P2-101); OCR core
   (P2-103); PDF pre-flight and verify (P2-105); `ResizeSpec` (P2-123); preset table (P2-131); keep-list model
   (P2-134); shelf core (P2-141); NotchIsland panel (P2-115); catalog cap rule (P2-100); model packs (P3-109).
3. **The catalog cap rule comes before any new slice.** The owner's tools take the PDF and video tool lists to 12–13
   (§8.1). P2-100 lands first.
4. **No new engine without a measured prototype.** Every Phase 2 feature has prototype evidence in a cluster report.
   Features without one (reel, join audio, GIF, contact sheet, peek, archive convert, notch tray) use bundled engines
   with well-known recipes, and each carries a spike or a golden test in its acceptance.
5. **Owner gates stay gates.** These are not scheduled as work until the owner says yes:
   - JPEG XL size;
   - 7-Zip helper;
   - digital signatures;
   - iWork Apple Events;
   - Office edit-restriction removal;
   - "ask in plain words".

---

## 4. Phase plan

### 4.1 Phases, waves and releases

| Phase / wave | Release | Original 05 rows in this release | Added rows (17) | Weeks (EST) | Exit |
|---|---|---|---|---|---|
| Phase 1 (to M4) | alpha 0.1 | all P1 rows (unchanged) | P2-100 may start early | as 05 | 05 M4 |
| **2A** | **beta 0.5** | P2-55 (→ Drop Box, first), P2-01 worker, P2-10 ZivletRS, P2-12, P2-13 qpdf, P2-19 libarchive, P2-30 tool window, P2-31, P2-33, P2-39, P2-41, P2-43, P2-51 Vision base, P2-57 | P2-115/116 (NotchIsland, Notch HUD), P2-141…143 (Drop Box, notch tray), P2-100…114, spikes P2-197 (first), P2-190/192/193 | ≈ 4.5 (orig.) + 11 + 1 | M5a |
| **2B** | **beta 0.6** | P2-03/04 spikes, P2-11 SVG, P2-18 subtitles, P2-23 extras, P2-32, P2-34…38, P2-40, P2-42 (→ Combine v1), P2-44…50 | P2-120…135, spikes P2-191/194/195/196/199 | ≈ 3 + 9 + 1 | M5b |
| **2C** | **beta 0.7 (= M5)** | P2-02, P2-05/06, P2-14…17, P2-20…22 (documents), P2-56, P2-60, P2-61 | P2-140, P2-144…153, spike P2-198 | ≈ 2.5 + 6 + 1 | M5c = 05 M5 |
| **3A** | 1.0 track | P3-01…11 documents, P3-20…28 tools | P3-100…107, P3-113 (gate) | 05 + ≈ 6 | — |
| **3B** | 1.0 track | P3-30…35 platform | P3-108…112 (P3-111 = transcription, TR-10…TR-43 in [05b](../plan/05b-task-additions-transcription.md)), spikes P3-190…192, TR-01…TR-07 | 05 + ≈ 2.5 + ≈ 11 (transcription, 55.5 d) | 05 M6 |
| **4** | 1.x | B4 backlog | P4-100…111 | ≈ 8.5 | per-feature addendum |

Phase 2 (one engineer) becomes ≈ 38 weeks across three betas, instead of 8–10 weeks; the two Notch HUD rows added on
2026-10-22 bring it to ≈ 39 (EST). Each beta is a coherent, announceable increment, and the owner's top-priority
features ship in the first one.

2026-10-22 split (EST, 05 §9.10 tally): P2-141/142/143 (13.5 d) and P2-55 (7.5 d) move from 2C to 2A and P2-115/116
(6 d) are new, so 2A ≈ 54.5 added days (≈ 11 weeks; P2-55 counts as orig.) and 2C ≈ 30 (≈ 6). Spikes stay separate.

> [challenge] The "orig." column is not on the same scale as the "added" column (see §1). On 05's own tally, the
> original rows per wave are about 2A ≈ 7.6 weeks, 2B ≈ 10 weeks and 2C ≈ 13.6 weeks (31 in total). Read the whole
> phase as **≈ 2× the original Phase 2**. Two further fixes:
> - **P2-10 ZivletRS has no consumer in 2A.** Its users (P2-11 SVG, P2-31 Compress images, P2-125 Smaller PNG) are
>   in 2B or are not owner priorities. Move P2-10 and P2-31 to 2B. That frees about 6 days in the first beta.
> - **Renaming the betas changes existing artefacts.** 05 P2-61 and M5 ("public beta 0.5", tag `v0.5.0-beta`, "221
>   pairs, 19 tools, 6 actions"), PRD §10's P2 row and 10 §12's heading all mean the *end* of Phase 2. After the split,
>   P2-61 must tag `v0.7.0-beta`, and M5 must read "9 actions" (FR-93). 0.5 then ships without documents (P2-14…22) or
>   promise drags (P2-02). O-18 ("Phase 2 ships as public beta") still holds.

### 4.2 Order inside each wave (owner priority, then dependency)

**2A (beta 0.5)**, reordered by the owner on 2026-10-22 (OWN-PLAN-3): the notch Drop Box comes first.
1. P2-197 notch spike (P-N1): panel above the menu bar in full screen, drag-near-notch detection, no TCC prompt.
2. P2-115 **NotchIsland core** (shared panel, geometry, pill fallback) + P2-116 **Notch HUD**.
3. P2-141 shelf core → P2-55 **Drop Box panel** (replaces Float) → P2-142 bulk actions → P2-143 **notch tray**.
4. P2-100 catalog cap rule.
5. P2-01 worker → P2-103 OCR core → **P2-104 Copy Text**.
6. P2-30 tool window → P2-101 password sheet + P2-102 policy tests.
7. P2-13 qpdf → P2-105 pre-flight/verify → **P2-106 PDF lock/unlock** → P2-107 encrypted inputs.
8. P2-108 Office crypto → **P2-109 Office lock/unlock**.
9. P2-19 libarchive → P2-113 NFC patch → P2-110 ZIP passwords → **P2-111 lock any file** → P2-112 unlock-then-convert.
10. P2-114 slot label refinement.
11. P2-43 merge (qpdf first), P2-39 split (ranges), P2-33 compress (pre-flight guard), P2-41 extract (all formats).

Dependency notes for the new order:
- **P2-142's Zip button** depended on P2-147 (2C). The box ships its other bulk actions first; Zip joins once libarchive
  writing exists in 2A (P2-19 → P2-111), so the dependency becomes P2-111.
- **Steps 1–3 need no XPC worker (P2-01)**: app-side AppKit and pure models; the Notch HUD re-hosts `ZivletUI` content.
- **No new slice**: BOX replaces FLOAT in the same Actions slot, so rule 3 still holds with P2-100 at step 4.

**2B (beta 0.6)**
1. P2-123 ResizeSpec + **Resize** → P2-124 **Rename**.
2. P2-40 Organize → **P2-120 Combine into one PDF** v1.
3. P2-46 Join Videos + P2-131 presets → P2-133 Instagram framing → **P2-121 Reel**.
4. **P2-122 Stitch**.
5. P2-125 Smaller PNG, P2-126 Remove BG.
6. P2-132 image fit search.
7. P2-134/135 Remove Silences (with P2-49).
8. P2-127 GIF, P2-128 contact sheet, P2-129 join audio, P2-130 batch semantics.

**2C (beta 0.7)**
1. PDF suite completion (owner priority): P2-150 **Make Searchable**, P2-152 **Remove Blank Pages**, P2-151 **Page
   Size**.
2. Documents P2-14…22 → P2-153 Combine v2 (Office inputs).
3. P2-144 custom wheels v1.
4. P2-145 history.
5. P2-147 archive creation → P2-148 peek → P2-149 archive convert.
6. P2-140 size estimates (tier 0).
7. P2-146 CLI subset. (The Drop Box rows moved to the front of 2A on 2026-10-22.)

**3A (1.0 track, first)**
1. P3-100/101 **visual signature**: the last item of the owner's PDF suite. Its placement UI is reused by P3-21
   Annotate.
2. P3-102 JPEG XL (gate).
3. P3-103 background picker.
4. P3-104 legacy Office unlock.
5. P3-105 encrypted DMG, P3-106 unlock-then-convert for documents.
6. P3-107 wheels v2.

**3B (1.0 track, second)**
1. P3-109 model packs → **P3-111 transcription** (TR-10…TR-43, [16](16-transcription.md)) → P3-112 translate.
2. P3-110 AI capability gate.
3. P3-108 CLI owner verbs (with P3-31).

### 4.3 Cut list (what slips first if Phase 2 must be shorter)

The owner's priority-1 and priority-2 rows are never cut. They are:
- Copy Text;
- all lock/unlock in 2A;
- PDF lock, unlock, merge, split and compress;
- Combine v1, Reel and Stitch;
- Resize and Rename;
- the Drop Box, the notch tray and the Notch HUD (owner decision 2026-10-22: the notch tray is no longer a cut
  candidate unless the owner says so).

Cut in this order, from first to last:

| # | Slip | To | Saves (EST) |
|---|---|---|---|
| 1 | P2-140 size estimates tier 0 | P4 (with tiers 1–2) | 3 d |
| 2 | P2-148 peek, P2-149 archive convert | P3 | 6 d |
| 3 | P2-127 GIF, P2-128 contact sheet | P3 | 2 d |
| 4 | P2-153 Combine v2 (Office inputs) | P3 | 3 d |
| 5 | P2-151/152 page size, blank pages | P3 (the original 17a-pdf.md placement) | 4 d |
| 6 | P2-150 Make Searchable | P3 (owner asked twice: cut last) | 3 d |

The former item 4 (P2-143 notch tray, 7.5 d) was removed on 2026-10-22 (OWN-PLAN-3).

### 4.4 Optional pulls into an earlier beta (owner's call, OWN-PLAN-2)

- **Visual signature (P3-100/101, 6 d) into 0.7.** This finishes the whole PDF suite at beta. It costs Annotate reuse
  timing and nothing else.
- **Copy Text (P2-103/104) into late Phase 1, in-process.** Not recommended. Vision would first run in the app process,
  then move to the worker. If the compiled-model cache is keyed by process identity (17a-pdf.md INFERRED), users would pay
  the multi-minute first-use compile twice. Spike P2-190 settles the question.

---

## 5. Master feature table

Columns:
- **Pri:** owner priority tier (1 = "very important"/"important"; 2 = picked; 3 = depends on transcription or Apple
  Intelligence).
- **Effort:** S ≤ 1 d, M 2–4 d, L 5–10 d.
- **Size Δ:** installed bundle delta. "0" means a system framework or an already-budgeted library; Swift code for all
  features together is estimated at +1–2 MB (§9).

### 5.1 Wave 2A — beta 0.5

The first six rows are the owner's 2026-10-22 reorder (OWN-PLAN-3, OWN-HUD-1). Their priority tier stays 2 (picked);
"built first" records the owner's order, not a new tier.

| Feature | Pri | Module(s) | Engine | Effort | Licence | Size Δ | FR | Tasks |
|---|---|---|---|---|---|---|---|---|
| **NotchIsland core** (shared panel above the menu bar: notch geometry, collapsed/expanded island, hover, top-centre pill on displays without a notch, Reduce Motion fade) | 2, built first | **ZivletNotch** (new, proposed: AppKit panel + pure geometry and state) | AppKit `NSPanel`; `NSScreen.safeAreaInsets`, `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` | M | system + GPL-3.0+ (own) | 0 | 133, 150 | P2-115 |
| **Notch HUD** (progress ring, hover details, done/failure cards, action toasts, "n jobs" list, drag-out; Settings › General placement choice) | 2, built first | ZivletUI (HUD content reused), ZivletNotch, ZivletSettings | existing `ZivletUI` HUD models on the NotchIsland panel | M | system + GPL-3.0+ (own) | **0 MB** | 150 | P2-116 |
| Drop Box core (+ opt-in shake) | 2, built first | **ZivletShelfCore** (new), Trigger | Foundation bookmarks + JSON | M | system | 0 | 132 | P2-141 |
| Drop Box panel (replaces Float) | 2, built first | Actions | AppKit `NSPanel`, QuickLookThumbnailing | L (orig.) | system | 0 | 132 | P2-55 |
| Drop Box bulk actions (Share, AirDrop, Copy, Move/Copy to, Convert all; Zip once P2-111 lands) | 2, built first | Actions, UI | `NSSharingServicePicker`, Move action, EngineArchive | M | system | 0 | 132 | P2-142 |
| **Notch tray** (island expands while dragging near the notch; pill on non-notch displays) | 2, built first | Actions, TriggerHost, Trigger, ZivletNotch | NotchIsland panel + existing permission-free drag sampler | L | system | 0 | 133 | P2-143 |
| Catalog visibility + 12-cap + combining rule | infra | Core, WheelCore | own | M | GPL-3.0+ | 0 | 90, 91 | P2-100 |
| Password sheet + policy (no recovery, no storing) | 1 | UI, Core, tests | SwiftUI `SecureField`, `SecCreateSharedWebCredentialPassword` | M + S | system | 0 | 96 | P2-101/102 |
| OCR core (Hindi-first order, warm-up, worker-pinned) | 1 | EngineVision | Vision `RecognizeDocumentsRequest` | M | system | 0 | 104 | P2-103 |
| **Copy text from image** (and PDF pages) | 1 | EngineVision, UI | Vision | M | system | 0 | 105 | P2-104 |
| PDF pre-flight + verify (qpdf-first rule) | 1 | EnginePDF | qpdf `--json`, `--check` | M | Apache-2.0 | 0 (qpdf budgeted; measured 3.6 MB) | 107 | P2-105 |
| **PDF lock / unlock / change password** (AES-256) | 1 | EnginePDF | qpdf `qpdfjob` (native crypto, no OpenSSL) | M + S | Apache-2.0 | 0 (saves 4.8 MB vs OpenSSL) | 97 | P2-106/107 |
| **Word/Excel/PowerPoint lock / unlock** | 1 | **EngineOfficeCrypto** (new) | own CFB + ECMA-376 Agile on CommonCrypto (from public MS specs) | M + S | GPL-3.0+ | +0.15–0.3 MB | 98 | P2-108/109 |
| **ZIP lock / unlock / change password** | 1 | EngineArchive, Vendor | libarchive 3.8.10 AES-256 via CommonCrypto + NFC patch | M + S | BSD-2-Clause | 0 (budgeted) | 99 | P2-110/113 |
| **Lock any file** (CSV, folders, mixes → AES ZIP); Actions LOCK | 1 | EngineArchive, Actions | libarchive | S | BSD-2 | 0 | 100, 93 | P2-111 |
| Unlock-then-convert (ZIP, PDF) | 1 | Runtime | as above | S | — | 0 | 101 | P2-112 |
| One LOCK·UNLOCK slot with label refinement | 1 | WheelCore, Wheel | header probe ≤ 30 ms | S | GPL-3.0+ | 0 | 92 | P2-114 |
| **Merge PDFs** (qpdf first, forms stay live) | 1 | EnginePDF | qpdf | S (mod) | Apache-2.0 | 0 | 108 | P2-43 |
| **Split / unmerge** (every page, every N, ranges, odd/even) | 1 | EnginePDF | qpdf | S (mod) | Apache-2.0 | 0 | 108 | P2-39 |
| **Compress PDF** + pre-flight guard (+ fit presets in 2B) | 1 | EnginePDF | Quartz filter + qpdf lossless | S (mod) | system + Apache-2.0 | 0 | 95, 107 | P2-33 |
| Extract every libarchive read format | 2 | EngineArchive | libarchive | S (mod) | BSD-2 | 0 | 128 | P2-41 |

> [challenge] Two corrections to the PDF rows above:
> - **Size.** 3.6 MB is the *Homebrew dynamic* `libqpdf` (OpenSSL linked externally, libjpeg-turbo separate). It is not
>   the static native-crypto build that 10 §10 ships. OpenSSL was never in the 10 §9 budget, so "saves 4.8 MB" is not a
>   budget saving. The delta stays 0, to be measured.
> - **Owner-password bypass.** "Unlock with user or owner password" breaks OWN-LK-1. If a PDF has a separate owner
>   password with restrictions, qpdf `--decrypt` with only the **user** password writes a fully unrestricted file. Rule:
>   unlock with the user password only when the file grants all permissions or the user and owner passwords are the
>   same (qpdf reports which one matched). Otherwise ask for the owner password. Encrypted inputs to other tools keep
>   their encryption *as is* (qpdf preserve-encryption, which may be RC4). They are re-encrypted as AES-256 only when the
>   owner password is known, and Zivlet never sets owner = user. See OWN-PDF-5 for the permission bits.

### 5.2 Wave 2B — beta 0.6

| Feature | Pri | Module(s) | Engine | Effort | Licence | Size Δ | FR | Tasks |
|---|---|---|---|---|---|---|---|---|
| **Batch resize** (hybrid thumbnail + Lanczos) | 1 | EngineImage, UI | ImageIO + Core Image | M | system | 0 | 114 | P2-123 |
| **Batch rename** (tokens, preview, journal, Undo); Actions RENAME | 1 | **ZivletRename** (new), Actions, Runtime | own | M | GPL-3.0+ | 0 | 115, 93 | P2-124 |
| **Combine anything into one PDF** v1 (images, SVG, PDFs; bookmark per file; review sheet) | 1 ⭐1 | EnginePDF, UI | Quartz (images) + qpdf merge + libqpdf outline shim | L | system + Apache-2.0 | 0 | 118 | P2-120 (= P2-42) |
| **Photos + videos → reel** | 1 ⭐2 | EngineMedia, UI | ffmpeg (`xfade`, `acrossfade`, loop stills, VT H.264) | L | GPL ffmpeg (bundled) | 0 | 119 | P2-121 |
| **Stitch into one long image** | 1 ⭐3 | EngineImage | Core Graphics + hybrid resampler | M | system | 0 | 120 | P2-122 |
| Smaller PNG (lossless default on every → PNG; safe colour reduction) | 2 | EngineImage | oxipng 10.2.1 + imagequant 4.4.1 in ZivletRS | S | MIT + GPL-3.0+ | 0 (≈ 0.75 MB inside the budgeted ZivletRS) | 116 | P2-125 |
| Remove background (one tap) | 2 | EngineVision, EngineImage | Vision `VNGenerateForegroundInstanceMaskRequest` | S | system | 0 | 106 | P2-126 |
| Images → animated GIF | 2 | EngineImage | ffmpeg palettegen/paletteuse (or ImageIO) | S | GPL / system | 0 | 121 | P2-127 |
| Contact sheet | 2 | EnginePDF, EngineImage | Quartz | S | system | 0 | 122 | P2-128 |
| Join audio (crossfade, matched loudness) | 2 ⭐ | EngineMedia | ffmpeg concat + `acrossfade` + `loudnorm` | M | GPL | 0 | 123 | P2-129 |
| Batch actions on all (convert, compress, resize, rename, fit) | 2 | Core, Runtime | — | S | — | 0 | 124 | P2-130 |
| Fit-to-size presets (dated table, FIT FOR… slice) | 2 | Core, Wheel, UI | existing target-size code (VT ABR, x264 2-pass) | M | GPL / system | < 0.05 MB JSON | 95 | P2-131 |
| Image fit-to-size search | 2 | EngineImage | ImageIO quality search + downscale; libwebp `target_size` | M | system + BSD-3 | 0 | 95 | P2-132 |
| Instagram presets (Reel 9:16, 4:5, 1:1; crop/pad/blur fill) | 2 | EngineMedia, EngineImage | ffmpeg filters | S | GPL | 0 | 126 | P2-133 |
| Remove silences (adaptive threshold, frame-accurate) | 2 | EngineMedia, UI | ffmpeg `silencedetect` + trim/concat or frame-snapped `select` | S + M | GPL | 0 | 125 | P2-134/135 |

### 5.3 Wave 2C — beta 0.7

| Feature | Pri | Module(s) | Engine | Effort | Licence | Size Δ | FR | Tasks |
|---|---|---|---|---|---|---|---|---|
| **Make searchable PDF** (Hindi + English text layer) | 1 | EnginePDF, EngineVision | Vision + own invisible L5 text layer (logical glyphs at natural advances) | M | system (+ OFL font) | +0.2–0.4 MB if Noto Sans Devanagari (OWN-PDF-4) | 109 | P2-150 |
| **Remove blank pages** (detector + review) | 1 | EnginePDF, UI | Quartz render + own detector + qpdf page selection | M | system + Apache-2.0 | 0 | 110 | P2-152 |
| **Resize pages** v1 (A4/Letter…, Fit/Fill/Actual) | 1 | EnginePDF | Quartz redraw | S | system | 0 | 111 | P2-151 |
| Combine v2: Word/Excel/PowerPoint/MD/TXT inputs, contents page | 1 | EnginePDF, EngineDocs | existing → PDF routes + qpdf | M | as routes | 0 | 118 | P2-153 |
| Custom wheels v1 (hide, order, per-wheel accent) | 2 | **ZivletPresets** (new, pulled from 1.x), WheelCore, UI | own | M | GPL-3.0+ | 0 | 134 | P2-144 |
| History (window, Re-run, retention, Undo) | 2 | Runtime, UI | JSON actor (SwiftData rejected: deleted paths linger) | M | system | 0 | 135 | P2-145 |
| CLI subset (`formats`, `info`, `convert`) | 2 | **ZivletCLIKit** (new), zivlet-cli | swift-argument-parser 1.7.2 | S | Apache-2.0 + RLE | +0.83 MB (measured) | 136 | P2-146 |
| Archive creation from any drop (ZIP default; 7z, tar.gz/xz/zst extras) | 2 | EngineArchive, Actions | libarchive (+ `ditto` for Mac-faithful ZIP) | M | BSD-2 | 0 | 127, 93 | P2-147 |
| Peek inside an archive | 2 | EngineArchive, UI | libarchive listing + staging | M | BSD-2 | 0 | 129 | P2-148 |
| Archive → archive (any readable → zip/7z/tar family) | 2 | EngineArchive, Core | libarchive streaming re-pack | M | BSD-2 | 0 | 130 | P2-149 |
| Size preview on the hot slice (tier 0) | 2 | Core, WheelCore, Wheel | estimator maths from the probe | M | — | 0 | 94 | P2-140 |

> [challenge]
> - **CLI size.** swift-argument-parser is already in 10 §10, and the CLI is already in 10 §9's Swift-code row. So the
>   CLI subset adds about 0 MB beyond the budget, not +0.83 MB.
> - **Pre-drop reads (tier 0 and the lock label).** Size estimates and the LOCK/UNLOCK label need data *before* the
>   drop. A content read during a drag can:
>   - download an iCloud "dataless" file (network, plus a stall);
>   - raise a TCC folder prompt in the middle of the drag for Desktop, Documents or Downloads, because user-intent
>     access is granted at the drop, not on hover (INFERRED; extend spike P0-33/S-P1).
>
>   Rule: before the drop, read only file-system metadata and Spotlight attributes (`fileSize`, `contentType`,
>   `kMDItemPixelWidth/Height`, `kMDItemDurationSeconds`). Skip any item with `SF_DATALESS` or
>   `ubiquitousItemDownloadingStatus != .current`. Do header and content probes only after the drop. Where data is
>   missing, keep the provisional label or estimate.
> - **Notch tray.** It has no prototype yet. It is the only Phase 2 L-size item with no evidence. Keep it behind spike
>   P2-197. (2026-10-22: the row moved to §5.1, 17e-app §2a now holds the notch island design, and the tray is no
>   longer on the cut list.)

### 5.4 Phase 3 (1.0)

| Feature | Pri | Module(s) | Engine | Effort | Licence | Size Δ | FR | Tasks |
|---|---|---|---|---|---|---|---|---|
| **Visual signature** (draw/type/image, Keychain store, incremental update) | 1 | EnginePDF, UI | own incremental writer on a libqpdf shim | M + M | Apache-2.0 + own | 0 | 112 | P3-100/101 |
| JPEG XL output + JXL → original JPEG | 2 | Vendor, EngineImage | libjxl 0.12 static (`SKCMS`) | M | BSD-3 + patent grant | **+2.5–3.3 MB** (gate OWN-IMG-1) | 117 | P3-102 |
| Background subject picker | 2 | EngineVision, UI | Vision instances | M | system | 0 | 106 | P3-103 |
| Legacy .doc/.xls/.ppt unlock | 1 | EngineOfficeCrypto | own RC4 / CryptoAPI / XOR (MS-OFFCRYPTO) | L | GPL-3.0+ | ~0.05 MB | 102 | P3-104 |
| Encrypted disk image option (hides names) | 1 | EngineArchive | system `hdiutil` (stdin password) | S | system | 0 | 100 | P3-105 |
| Unlock-then-convert for documents | 1 | EngineDocs, Runtime | EngineOfficeCrypto | S | — | 0 | 101 | P3-106 |
| Custom wheels v2 (slice colours, presets, import/export, pinned presets) | 2 | ZivletPresets, UI | own | M | GPL-3.0+ | 0 | 134 | P3-107 |
| CLI owner verbs (lock, pdf, archive, text, resize, rename, fit, …) + cask | 2 | zivlet-cli | ArgumentParser | M (+ P3-31 M) | Apache-2.0 | 0 | 136 | P3-108, P3-31 |
| Model-pack infrastructure (verified, data-only) | 3 | Runtime, UI | URLSession on user click, SHA-256 pin | M | system | 0 | 137 | P3-109 |
| AI capability gate + PCC ban | 3 | Core, **EngineAI** (new) | Foundation Models / Translation availability | S | system | 0 | 137 | P3-110 |
| **Transcription** (EN/HI/Hinglish; Roman + Devanagari files; TXT/SRT/VTT) | 3 | **ZivletTranscript** (new, pure), **EngineSpeech** (new), EngineSubtitles, `zivlet-whisper` helper (new) | Apple `SpeechTranscriber` for English without the pack; whisper.cpp v1.9.5 + Trelis Hinglish model (our ggml q5_0 conversion, 1.08 GB pack) + Silero VAD | ≈ 55.5 d (16 §13) | system + MIT (whisper.cpp, Silero) + Apache-2.0 (model, download) | **+7–7.5 MB** (≈ +2 MB if shaders move to the pack, OWN-TR-3); models are downloads | 138, 142–149 | P3-111 (TR-01…TR-43) |
| Translate transcript → English | 3 | EngineAI, UI | Apple Translation (offline packs managed by macOS) | S | system | 0 | 139 | P3-112 |
| Encrypted 7z via 7-Zip helper (gate) | 2 | Vendor, EngineArchive | `7zz` 26.x built without RAR codecs | M | LGPL-2.1+ / BSD-3 | **+2–3 MB** (gate OWN-ARC-2) | 131 | P3-113 |

> [challenge]
> - **Visual signatures:** store them in the Keychain with `kSecAttrSynchronizable = false`. P3-101's "not synced unless
>   opted in" would put signature images in iCloud Keychain, which is a cloud path. Drop the opt-in.
> - **7-Zip helper:** `7zz` takes passwords as `-p<pw>` on argv, which is visible in `ps` and violates NFR-21. It may
>   prompt on a TTY. P3-113 must prove a non-argv path (pty or stdin) before the gate can open. Otherwise the row closes.
> - **Subject picker:** `instanceAtPoint(_:)` exists only on the Swift `InstanceMaskObservation`
>   (Vision.swiftinterface, macOS 15+). On the VN fallback (`VNInstanceMaskObservation`), read the `instanceMask` pixel
>   value at the point instead.

### 5.5 Phase 4 (1.x)

| Feature | Pri | Module(s) | Engine | Effort | Licence | Size Δ | FR | Tasks |
|---|---|---|---|---|---|---|---|---|
| Meeting notes with speaker labels | 3 | EngineAI, UI | CoreML diarisation pack (FluidAudio-style, Apache-2.0 code; per-model licence audit) + Foundation Models map-reduce | L + M | Apache-2.0 / CC-BY-4.0 models / system | 0 bundled; **~16 MB download** | 140 | P4-100/101 |
| Ask in plain words | 3 | EngineAI, UI | phrase table + Foundation Models guided generation + validator + confirm card | M | system | 0 | 141 | P4-102 |
| Size estimates tiers 1–2 | 2 | EngineImage, EngineMedia | tile and sample encodes | M | — | 0 | 94 | P4-103 |
| Smart crop for presets | 2 | EngineMedia | Vision objectness saliency | M | system | 0 | 126 | P4-104 |
| Resize pages v2 (lossless, links stay) | 1 | EnginePDF | libqpdf form XObjects | M | Apache-2.0 | 0 | 111 | P4-105 |
| Split by size / by bookmarks | 1 | EnginePDF | qpdf | M | Apache-2.0 | 0 | 108 | P4-106 |
| Digital signature PAdES B-B (gate) | 1 | EnginePDF | own CMS (swift-asn1) + `SecKeyCreateSignature` / CryptoTokenKit | L | Apache-2.0 | +0.3–0.6 MB | 113 | P4-107 |
| iWork lock/unlock (Apple Events, opt-in) | 2 | Runtime | Pages/Numbers/Keynote scripting | M | system | 0 | 103 | P4-108 |
| Office edit-restriction removal (verified password; gate) | 2 | EngineOfficeCrypto | own | M | GPL-3.0+ | 0 | 103 | P4-109 |
| Interactive background refine (macOS 27) | 2 | EngineVision, UI | Vision iterative segmentation | M | system | 0 | 106 | P4-110 |
| Shake-to-open on by default | 2 | Trigger | own detector | S | — | 0 | 132 | P4-111 |

> [challenge]
> - **Diarisation evidence is for the wrong route.** media-ai §5.3 MEASURED **sherpa-onnx**, which is about 60 MB and
>   ships `libonnxruntime.dylib` as code. As a pack, that code fails library validation and breaks P3-109's data-only
>   rule; bundling it breaks the size budget. The chosen CoreML (FluidAudio) route is **unmeasured** for both size and
>   DER. So P3-190 must pass before P4-100 is scheduled, and sherpa-onnx stays a test baseline only, never a shipped
>   fallback (OWN-MA-4 amended).
> - **OS-managed downloads:** P4-110 uses `GenerateIterativeSegmentationRequest`, which conforms to
>   `DownloadableAssetsRequest` (macOS 27, `downloadAssets()`). Its model comes from Apple over the network. It has to be
>   user-initiated, with an explicit card, just like Translation packs.
> - **`SystemLanguageModel.tokenCount(for:)`** is `@available(macOS 26.4)`. P4-101 chunking needs a 26.4 gate or a
>   character-count fallback on 26.0–26.3.

---

## 6. Dependency spine

```
P2-100 catalog cap ──────────────┬─ every new slice ─ P2-144 wheels v1 ─ P3-107 wheels v2
P2-01 worker ──┬─ P2-103 OCR core ─┬─ P2-104 COPY TEXT ─ P2-150 SEARCHABLE
               │                   └─ P2-126 REMOVE BG ─ P3-101 SIGN (image import), P3-103
               ├─ P2-108 Office crypto ─ P2-109 Office LOCK ─ P3-104 legacy, P3-106, P4-109
               └─ P3-109 model packs ─ P3-111 TRANSCRIBE (16) ─ P3-112 TRANSLATE ─ P4-101 NOTES
                                                              └─ P4-100 diarisation ─┘
P2-30 tool window ─ P2-101 password sheet ─┬─ P2-106 PDF LOCK ─ P2-107 encrypted inputs
                                           ├─ P2-109, P2-110, P2-111 LOCK any ─ P3-105 DMG
                                           └─ P2-112 unlock-then-convert
P2-13 qpdf ─ P2-105 preflight/verify ─┬─ P2-43 MERGE, P2-39 SPLIT, P2-33 COMPRESS
                                      ├─ P2-120 COMBINE v1 (+P2-40 grid) ─ P2-153 COMBINE v2 (+docs)
                                      ├─ P2-150, P2-151 PAGE SIZE, P2-152 NO BLANKS (+P2-40)
                                      └─ P3-100 incremental writer ─ P3-101 SIGN ─ P4-107 PAdES
P2-19 libarchive ─ P2-113 NFC ─ P2-110 ZIP passwords ─ P2-111 ─ P2-147 ZIP/7Z/TAR ─ P2-149 convert
                └─ P2-41 extract all ─ P2-148 PEEK                       └─ P2-142 Box "Zip"
P2-123 ResizeSpec ─ P2-122 STITCH, P2-127 GIF, P2-128 THUMBNAILS, P2-132 image fit
P2-131 presets ─ P2-133 Instagram ─ P2-121 REEL (+P2-46 join video) ; P2-140 estimates ; P4-102 Ask
P2-49 trim audio ─ P2-134 keep list ─ P2-135 NO SILENCE (keep list reused by transcript remap)
P1-15 UndoLog ─ P2-124 RENAME, P2-145 HISTORY
P2-197 notch spike ─ P2-115 NotchIsland ─┬─ P2-116 NOTCH HUD
                                        ├─ P2-143 NOTCH tray
                                        └─ picker at the notch (last phase)
P2-141 shelf core ─ P2-55 Drop Box panel ─ P2-142 bulk actions ─ P2-143 NOTCH tray
```

---

## 7. Transcription slot (designed in 16)

- **Status (2026-10-22):**
  - Designed in [16-transcription.md](16-transcription.md), evidence in
    [16a-transcription-evidence.md](16a-transcription-evidence.md), rows in
    [05b-task-additions-transcription.md](../plan/05b-task-additions-transcription.md) (not yet merged into 05/01b).
  - Engines: Apple `SpeechTranscriber` for English when no pack is installed; whisper.cpp v1.9.5 in a new signed helper
    `zivlet-whisper` with the Trelis Hinglish model (Apache-2.0, our own ggml q5_0 conversion) as a 1.08 GB "Hindi &
    Hinglish" pack. Modules `ZivletTranscript` (pure) and `EngineSpeech`.
  - Defaults adopted 2026-10-22: OWN-TR-8 (a), OWN-TR-9 (word timing), OWN-TR-10 ([00-decisions.md](00-decisions.md)).
  - It stays in Phase 3 wave 3B, after P3-109; 16 did not pull it into Phase 2.
  - Owner answers (2026-10-21): English, Hindi, Hinglish and mixes. Two transcript files for Hindi/Hinglish (Roman,
    and Devanagari with English words kept in Roman). One file for pure English. TTS or freely licensed recordings
    only, labelled.
- **Slot:** P3-111 in wave 3B, after P3-109 (model packs), which it shares with the Speaker pack. 16 may move it.
  - Its only hard dependencies are P2-01 (worker) and P3-109.
  - If 16 pulls it into Phase 2, P3-109 moves with it.
- **Reserved now, so nothing has to be renumbered later:**
  - a `TRANSCRIBE` slice in the audio and video Tools lists, counted inside the 12-cap (§8.1);
  - the History kind `transcribe` (language, model id);
  - the CLI verb `zivlet transcribe`;
  - FR-138;
  - module name: 16 chose a separate `EngineSpeech` (16 §6).
- **What dependents need from 16** (media-ai §9):
  - segments with timestamps (word times if available) and a language tag per segment;
  - both script forms per segment;
  - a `task=translate` decision (never a turbo model for translation);
  - the shared model-pack mechanism;
  - a phase.
- **Dependents:**
  - P3-112 translate ships in the same release as transcription.
  - P4-100/101 meeting notes follow it.
  - Remove Silences (P2-135) remaps a transcript sidecar through its keep list when one exists.

---

## 8. Wheel and catalog changes

### 8.1 Tools lists per input, with caps

The default-visible lists are in catalog order. Extras are reachable through custom wheels, App Intents and the CLI.
The cap is 12 (FR-27/FR-90). New items are in **bold**. (P3) or (P4) marks the phase where an item appears.

| Input | Single-file default visible | Single extras | Multi-file default visible | Multi extras |
|---|---|---|---|---|
| jpg png webp heic tiff | **COPY TEXT**, COMPRESS, **RESIZE**, **REMOVE BG**, **FIT FOR…**, CROP, EDIT, ANNOTATE, METADATA, REDACT (10) | ADD BG | **COMBINE PDF**, **STITCH**, **REEL**, **COPY TEXT**, COMPRESS, **RESIZE**, **FIT FOR…**, **GIF**, COLLAGE, **REMOVE BG**, CROP, METADATA (12, at cap) | **THUMBNAILS** |
| avif bmp gif | READ QR, **COPY TEXT** (+ METADATA for gif) | — | READ QR, **COPY TEXT**, **COMBINE PDF** (avif/bmp) | — |
| svg | READ QR | — | **COMBINE PDF**, COLLAGE, READ QR | — |
| pdf (not encrypted) | COMPRESS, **LOCK**, **SIGN** (P3), **SEARCHABLE**, **COPY TEXT**, SPLIT, ORGANIZE, **NO BLANKS**, **PAGE SIZE**, METADATA, READ QR (11) | **FIT FOR…** | **MERGE PDF**, COMPRESS, **LOCK**, SPLIT, **SEARCHABLE**, **NO BLANKS**, **PAGE SIZE**, **COPY TEXT**, METADATA, READ QR (10) | **THUMBNAILS**, **FIT FOR…** |
| pdf (encrypted) | as above with **UNLOCK** + **CHANGE PASSWORD** (12, at cap) | — | as above with **UNLOCK** | **CHANGE PASSWORD** |
| mp3 m4a wav flac | COMPRESS, **NO SILENCE**, **TRANSCRIBE** (P3), TRIM, NORMALIZE, CHANNELS, BLEEP, VISUALIZE, METADATA, **FIT FOR…** (10) | **NOTES** (P4) | COMPRESS, **JOIN**, **NO SILENCE**, **TRANSCRIBE**, NORMALIZE, METADATA, **FIT FOR…** (7) | — |
| mp4 mov mkv | COMPRESS, **FIT FOR…**, TRIM, CROP, SPLIT, SPEED, MUTE, **NO SILENCE**, **TRANSCRIBE** (P3), SNAPSHOT, METADATA, REDACT (12, at cap) | **NOTES** (P4) | COMPRESS, JOIN, **REEL**, **FIT FOR…**, MUTE, **NO SILENCE**, **TRANSCRIBE**, METADATA (8) | **THUMBNAILS** |
| docx/xlsx/pptx (+ macro/template, xlsb) | **LOCK · UNLOCK** | **CHANGE PASSWORD** | **LOCK · UNLOCK**, **COMBINE PDF** (P2c) | **CHANGE PASSWORD** |
| doc/xls/ppt | **UNLOCK** (P3, encrypted only) | — | same | — |
| zip, 7z, rar, tar family, iso, cab, lha, cpio | EXTRACT, **PEEK**, **LOCK · UNLOCK** (zip; 7z only with the P3-113 gate) | **CHANGE PASSWORD** | EXTRACT, **LOCK · UNLOCK** | — |
| txt srt vtt (transcripts) | **TRANSLATE** (P3) | — | **TRANSLATE** | — |
| mixed families (multi) | — | — | combining tools whose families cover every item: **COMBINE PDF** (images, svg, pdf, documents), **REEL** (images + videos) | — |

Notes:
- **Instagram presets live inside FIT FOR…** (Reel 9:16, 4:5, 1:1 sit beside WhatsApp, Gmail, Discord and Custom).
  That saves a slot in every media list.
- **Meeting notes** is reached from the TRANSCRIBE progress card's Change… menu or a setting, not a sheet (TRANSCRIBE
  is one drop with no dialog, 16 §4.1), so it doesn't need a default slot.
- **CREATE PDF is retired into COMBINE PDF.** The label is MERGE PDF when every item is a PDF. The output names keep
  parity: `Images.pdf`, `Merged.pdf`, `Combined.pdf`.
- **Lock · Unlock is one slot** (`tools.protect`). The label refines from the header probe (FR-92). This keeps the
  first-frame slice set stable (FR-18) and saves a slot in every family.
- Three lists sit at the cap: images multi, encrypted PDF single, video single. The next tool added to any of them must
  replace a default or go to extras. The P2-100 lint enforces this. The "More…" overflow slice stays an owner decision
  after the usability test (OWN-APP-4).

> [challenge] Three fixes to the lists above:
> - **CHANGE PASSWORD breaks FR-18.** The label refinement is acceptable because no slot moves. But making CHANGE
>   PASSWORD appear only "when every item is encrypted" (P2-114) adds a slice *after* frame 1, which changes the frame-1
>   slice set. Fix: CHANGE PASSWORD is never a wheel slice. It is a "Change password…" mode in the Unlock sheet (and a
>   CLI verb). That leaves the encrypted-PDF single list at 11, so no list hits the cap because of encryption.
> - **"LOCK · UNLOCK k of n" does not fit.** Tool labels are 7.5 pt in an 82 × 22 pt frame (03a §2). Show "k of n" with
>   the existing badge (OWN-2) and keep the label as LOCK, UNLOCK or LOCK · UNLOCK.
> - **ADD BG drops off the default image list,** and EDIT, ANNOTATE and REDACT stay on it. O-18 defines 1.0 as "27
>   tools". Parity counting must say "reachable (wheel, custom wheel, App Intents, CLI)", not "visible by default", or
>   ADD BG has to share a slot with REMOVE BG. Owner call, folded into OWN-APP-4.

### 8.2 Actions wheel (any file, folder or mix)

| Default visible (9) | Extras |
|---|---|
| AirDrop, **BOX** (was FLOAT; `ActionID.pinFloating` raw value kept), Copy, Move, Copy Path, Terminal, **ZIP**, **LOCK**, **RENAME…** | **7Z**, **TAR.GZ**, **TAR.XZ**, **TAR.ZST** |

PRD §6.3 changes from "Actions never use the worker" to "Actions never import engines". ZIP and LOCK submit jobs
through the ZivletUI coordinator, which keeps dependency rule R3.

### 8.3 Convert wheel

| Input | Change | Phase |
|---|---|---|
| Raster images | **+ JXL** target (8 targets); `jxl → jpg` reconstructs the original JPEG | P3 (gate) |
| Archives | inputs expand to 7z, tgz/tbz2/txz/tzst, xz, zst, bz2, lz4, iso, cab, lha, cpio. Targets: **zip, 7z, tar, tar.gz, tar.xz, tar.zst, tar.bz2** (≤ 7, any → any). RAR stays input-only | P2c |
| PNG targets | every → PNG output gets the lossless oxipng pass by default (no new slice) | P2b |

### 8.4 Interaction changes

| # | Change | FR | Risk / spike |
|---|---|---|---|
| W-1 | Catalog `defaultVisible` / `extra`, a 12-cap on every list (fixes the builder gap: only mixed conversions are capped today) | 90 | — |
| W-2 | Combining rule for mixed-family multi drops | 91 | usability |
| W-3 | One slot whose label refines (LOCK / UNLOCK / k of n) | 92 | first-frame replay suite |
| W-4 | Actions grows from 6 to 9 default slices and may submit jobs | 93 | — |
| W-5 | Second label line on the hot slice with a size estimate, read from cache only | 94 | wrong estimates erode trust: ranges |
| W-6 | **FIT FOR… dwell ring**: holding over the slice ≈ 350 ms opens an outer ring of presets. Dropping on the parent uses the last preset | 95 | new geometry beyond r 125.92 conflicts with edge clamping (FR-24). Spike **P2-196**; the fallback is a compact picker after the drop |
| W-7 | Custom layouts filter and order the catalog's offer; per-wheel accent; per-slice colours with an automatic outline below 3:1 | 134 | colour never the only cue |
| W-8 | Notch tray is a second drop surface during drags. The wheel wins when both are hit. Trays appear only near the notch | 133 | spike **P2-197** (full screen, menu bar, Apple changes) |
| W-9 | **Notch HUD** (2026-10-22): job progress, results and action toasts show on the NotchIsland at the notch (or a top-centre pill on the drop's display) instead of the HUD card near the drop; a Settings › General choice | 150 | spike **P2-197**; must never cover the wheel or the menu bar beyond the island |

> [challenge] W-3 and W-5 need a probe before the drop. They must follow the pre-drop metadata-only rule (§5.3
> challenge): no content reads of dataless or TCC-protected items during a drag. W-5's second line also has to fit the
> 82 × 22 pt label frame. The hub (58 × 28 pt) is the safer place for "≈ 4.2 MB".

---

## 9. Size budget impact (vs 10 §9 expected 68.8 MB)

| Item | Δ installed | Status |
|---|---|---|
| All system-framework features (Vision, PDFKit/Quartz, Translation, Foundation Models, AppKit shelf/notch, Notch HUD, hdiutil) | 0 | — |
| qpdf native crypto instead of OpenSSL | 0 vs budget; measured dylib 3.6 MB (budget 4.5 expected) | saves 4.8 MB vs the Homebrew build |
| libarchive formats, AES ZIP | 0 (budgeted 1.8 MB) | — |
| oxipng + imagequant | 0 (≈ 0.75 MB measured inside the 4–6 MB ZivletRS row) | — |
| EngineOfficeCrypto | +0.15–0.3 MB | measured `__text` 147 KB in the spike |
| swift-argument-parser (CLI) | +0.83 MB | measured, stripped |
| Noto Sans Devanagari (text layer) | +0.2–0.4 MB | OWN-PDF-4 |
| Swift code for all new features | +1–2 MB | EST |
| Preset JSON, wheel layouts | < 0.05 MB | — |
| **Subtotal, ungated** | **+2.2–3.6 MB → ≈ 71–72 MB expected** (above 70 target, below 85/40 MB gates) | measure at the P1-52 size gate |
| libjxl (JPEG XL) | +2.5–3.3 MB | **gate OWN-IMG-1** |
| 7-Zip `7zz` helper | +2–3 MB | **gate OWN-ARC-2** |
| swift-asn1 (PAdES) | +0.3–0.6 MB | P4 gate |
| Speaker pack (CoreML), transcription models, Translation packs | 0 (downloads; Translation packs managed by macOS) | P3/P4, user-initiated |
| `zivlet-whisper` helper (transcription, Phase 3) | +7–7.5 MB (≈ +2 MB if the Metal shaders move to the pack) | **OWN-TR-3**, 16 §8; measured minimal helper 6.7 MB installed / 1.56 MB gzip |

Recommendation:
- Ship the ungated set.
- Decide JPEG XL only after the real DMG shows the measured headroom. 10 §9's Swift-code row (6–14 MB) is still an
  estimate.
- If both gates open, the expected size is ≈ 76–78 MB: still under the 85 MB hard gate, but 6–8 MB over target.

> [challenge] Remove the swift-argument-parser row from the subtotal: it is already budgeted in 10 §9/§10. The ungated
> total is **≈ 70.2–71.6 MB**. NFR-24's "re-baseline to ≤ 72 MB" is withdrawn. NFR-7's 70 MB target stays, and any
> overage goes to the owner (OWN-SIZE-1) once P1-52 has measured it.

---

## 10. Licence summary for the additions

| Component | Licence | GPL-3.0+ compatible | Shipped how |
|---|---|---|---|
| Own code (EngineOfficeCrypto from MS-OFFCRYPTO/MS-CFB under the Microsoft Open Specification Promise; ZivletRename, ZivletShelfCore, ZivletPresets, detectors, text layer) | GPL-3.0-or-later | yes | source |
| qpdf 12.4.x (native crypto) | Apache-2.0 | yes | static, reproduce NOTICE |
| libarchive 3.8.10 + NFC vendor patch | BSD-2-Clause | yes | static, patch noted in SPDX |
| oxipng / imagequant | MIT / GPL-3.0-or-later | yes | ZivletRS |
| swift-argument-parser 1.7.2 | Apache-2.0 with Runtime Library Exception | yes | SPM |
| Noto Sans Devanagari | OFL-1.1 | yes (font) | resource |
| libjxl 0.12 (gate) | BSD-3-Clause + PATENTS grant | yes | static |
| 7-Zip `7zz` without RAR codecs (gate) | LGPL-2.1-or-later + BSD-3-Clause | yes (separate helper) | helper + source |
| swift-asn1 (P4 gate) | Apache-2.0 | yes | SPM |
| whisper.cpp v1.9.5 + ggml (transcription helper, P3) | MIT | yes | static in `zivlet-whisper`; our mixedcode patch proposed MIT (16 §9) |
| Trelis/whisper-hinglish-preview, our ggml q5_0 conversion (P3) | Apache-2.0 (NOTICE credits Trelis, ARTPARK-IISc Whisper-Vaani, OpenAI Whisper) | yes | user-initiated download (pack), never bundled |
| Silero VAD v6.2.0 ggml (P3) | MIT | yes | in the same pack |
| FluidAudio-style diarisation code / models (P4) | Apache-2.0 code; models need a per-model audit (pyannote community-1 is CC-BY-4.0: attribution) | yes with attribution (AI-S2 confirms) | data-only download |
| msoffcrypto-tool, pyzipper, python-docx/openpyxl/pptx, poppler, pdfium | MIT / GPL | n/a | **test oracles only, never shipped** |
| **Never:** unRAR code, RAR writer, Ghostscript (AGPL, 25–40 MB), Private Cloud Compute model, network TSA by default | — | — | CI/licence gate |

**RAR creation** (owner asked to investigate):
- Recommendation: **no** (OWN-ARC-1).
- A store-only RAR5 writer built from the public format notes adds no compression.
- It reimplements a proprietary format whose compression is licensed.
- 13 §6.4 already dropped it.
- ZIP and 7z cover the need.
- Encrypted RAR stays unsupported, because the only decoder carries the unRAR restriction. The copy points users to
  The Unarchiver or Keka.

> [challenge] Licence notes (none of them blocks anything):
> - **Noto Sans Devanagari (OFL-1.1)** is compatible as an *aggregate*, not as GPL code. Ship it as a separate resource
>   with `OFL.txt`, the same way as Carlito/Caladea in 10 §10. Embedding subsets in output PDFs is allowed.
> - **Microsoft Open Specification Promise:** it covers conforming implementations of MS-OFFCRYPTO/MS-CFB. GPL
>   compatibility of the OSP has been questioned (it is a patent non-assert, not a copyright licence). Our code is our
>   own, so the risk is low (INFERRED, not legal advice).
> - **Diarisation:** the per-model audit has to cover the *embedding* model as well as segmentation: CAM++ (3D-Speaker)
>   or WeSpeaker, and the VoxCeleb-derived training terms. Host packs on the project's own release assets, not on
>   gated Hugging Face URLs.
> - **imagequant GPL-3.0-or-later** ties `libzivlet_rs` to GPLv3. That was already accepted in 10 §10.

---

## 11. Reconciliations between the cluster reports and existing docs

| Topic | Conflict | Resolution here |
|---|---|---|
| OCR phase | 17c-image.md: P2 first tool; 17a-pdf.md: OCR core in P3 | **P2a** (owner priority 1). Make Searchable rides on the same core in P2c |
| Lock slices | 17b-lock.md: two slices (Lock, Unlock); 17e-app.md cap analysis counts both | **One slot with label refinement** (FR-92); Change Password is an extra |
| Drop Box home | 17e-app.md: floating/docked panel from Float; owner picks: notch tray primary | **Notch tray primary** (P2-143); the panel stays for the expanded view and docking, and non-notch displays get a pill; both use ZivletShelfCore |
| Discord limit | owner said 10 MB; media-ai verified 20 MB since 2026-08-13 | 19.4 MB target (20 MB limit) by default, OWN-MA-1 |
| WhatsApp 100 MB | Business API only; consumer documents are 2 GB | drop the preset, keep 15.5 MB media (OWN-MA-2) |
| Task IDs | 17a-pdf.md "P2-44" collides with Crop Video; 17e-app.md P2-70…73 | new IDs ≥ 100 (05 §9.0) |
| Create PDF vs Combine | two multi-file PDF builders | Combine supersedes Create PDF (P2-42 → P2-120), parity names kept |
| Actions and the worker | PRD §6.3 "Actions never use the worker" vs ZIP/LOCK in Actions | "Actions never import engines" (R3); jobs go via the coordinator |
| History size | 05 P1-15 "50" vs code and 03a "20" | Recent menu 10, History max 500 / 30 days, Undo 24 h |
| Vision cache keying | 17a-pdf.md: per process identity (INFERRED); 17c-image.md: cached system-wide | Pin Vision to the worker either way; P2-190 decides |
| Swift vs VN background API | 13 §8.2 uses the Swift `GenerateForegroundInstanceMaskRequest` (fails here) | VN API behind `ForegroundMasker` until P2-194 passes |
| Resize decode | 03b §6.1 thumbnail-only resize is soft (SSIMULACRA2 66.8) | hybrid thumbnail ≥ 2× + Lanczos |
| Naming | media-ai uses "(No Silences)", "(WhatsApp)" | PRD §5.9 form: `X No Silences.mp4`, `X WhatsApp.mp4` |
| PDFKit writes | 13 §4.1/4.2 used PDFKit for password save, merge and split | qpdf-first (RC4 output, silent non-ASCII failure, dropped AcroForm, missing `/Length` all PROBED) |
| ZivletPresets phase | 02 §5.2 lists it for 1.x | pulled to P2c (custom wheels v1) |

> [challenge] Reconciliations that were wrong or missing:
> - **History size:** PRD §6.6 says "Recent results (last 20)", and FR-39 says "survives relaunch for the last 20
>   operations". Changing the menu to **10** silently changes the PRD. Keep 20 in the menu. History (500 entries / 30
>   days) is separate.
> - **Spike ID collisions with 10 §13:**
>   - 17b-lock.md's manual QA **M-1…M-6** clashes with the media spikes M-1…M-6, so it is renamed **LK-M1…LK-M6**;
>   - 17c-image.md's **I-C1** (oxipng/cjxl timings) clashes with 10's I-C1 (jpegli/libavif A/B) → **I-C2**;
>   - app/media **P-W4** (dwell ring) clashes with 10's P-W4 (UI-sound key) → **P-W5**;
>   - **I-V2** duplicates 10's **I-V1**/13's **S-V1** (already in P2-06), so P2-190 *extends* I-V1 instead of adding
>     an ID.
> - **Duplicate FRs:** FR-136 extends FR-88 (CLI), FR-132/133 supersede FR-73 (Float), and FR-93 amends FR-20 ("Actions:
>   fixed 6"). Mark the old ones so the PRD doesn't carry two specs for the same feature.
> - **PRD §6.7 says the shelf "references files (never copies)".** Owned copies for promise/clipping content change that
>   sentence. It needs a §A edit.

### 11.1 Edits to fold into `docs/` (01-prd and 05 done on 2026-10-21; the others are still open)

- **10 §12:**
  - replace the Phase 4/5 owner items with the placements above;
  - add the beta split;
  - move B4-05/06/07/09/10/12/15/16 and B5-03/04.
- **10 §9:** qpdf measured at 3.6 MB with native crypto; add the rows in §9 above.
- **13:**
  - §4.1/4.2: qpdf-first, no PDFKit password saves;
  - §4.2 OCR row: the L5 text layer, since `.saveTextFromOCROption` writes nothing;
  - §8.1: Hindi and auto-detect cold compile takes 5–10 min, not 58 s;
  - §8.2: VN API.
- **03b:**
  - §6.1: hybrid resize;
  - §9: encrypted OOXML becomes `passwordRequired` instead of being refused.
- **02 §4.1:**
  - add EngineOfficeCrypto, ZivletRename, ZivletShelfCore, ZivletCLIKit, EngineAI;
  - ZivletPresets moves to Phase 2;
  - zivlet-cli becomes "P2 subset, P3 complete".
- **01-prd:** see 01b-prd-additions §A.
- **05:** see 05 §9.1 and §9.9.

---

## 12. Top risks

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R1 | Schedule: Phase 2 nearly quadruples (≈ 38 weeks for one engineer) | High / High | Beta split, priority-1 work first, cut list §4.3, owner decision OWN-PLAN-1 |
| R2 | Hindi OCR is missing or slow on macOS 26.0 (Hindi may be new in 27; cold compile takes minutes) | Medium / High | Spike P2-190 first in 2A; capability probe hides Hindi where it is absent; warm-up after onboarding; determinate one-time state |
| R3 | Word or Excel rejects our encrypted CFB container | Low / High | DataSpaces byte-equal to the reference; MS-CFB-valid tree; v3 sectors for small files; LK-M1/LK-M2 before 0.5 |
| R4 | libarchive writes NFD names (certain) | Certain / Medium | P2-113 patch + NFC test, release blocker |
| R5 | Non-ASCII PDF passwords: Preview can't open AES-256 files that qpdf and poppler accept | Medium / Medium | Warning + "opens on Mac" check (OWN-PDF-1) |
| R6 | Wheel overcrowding: three lists at the 12-cap | Medium / Medium | Visibility rule, Instagram inside FIT FOR…, one lock slot, custom wheels, usability test before 0.6 |
| R7 | Notch tray and Notch HUD: panel above the menu bar in full screen, accidental opens, Apple changes to notch areas; both now ship first, in 0.5 | Medium / Medium | Spike P2-197 first in 2A; recorded-trace thresholds; the floating Drop Box panel and today's HUD card stay as fallbacks (Settings choice), since the tray is no longer on the cut list (OWN-PLAN-3) |
| R8 | PDFKit silent failures leak into tools (RC4, no encryption, dead forms) | Was certain / High | qpdf-first rule, `PDFVerify` on every output (FR-107) |
| R9 | Foundation Models hallucinates plans or action items; limited availability; Hindi unsupported | High / Medium | Validator + confirm card; "AI-generated" label; translate first; English summaries; transcript-only fallback |
| R10 | Size creep beyond 70 MB | High / Low–Medium | Per-row Δ, ungated ≈ 71–72 MB, gates for JXL and 7zz, measure at P1-52 |
| R11 [challenge] | Pre-drop reads (lock label, size estimates) download iCloud dataless files or raise TCC prompts mid-drag | Medium / High | Metadata-only before the drop; skip `SF_DATALESS`; content probes after the drop; extend P0-33 |
| R12 [challenge] | Tools ignore PDF permission bits (Copy Text/Searchable on extract-disallowed files; Merge/Split/Page Size on modify/assemble-disallowed files): a bypass under OWN-LK-1 | Medium / Medium | OWN-PDF-5: honour the bits unless the owner password is given |
| R13 [challenge] | PDFKit extracts shaped Devanagari in visual order (17a-pdf.md L1: CER 0.105), so Copy Text on born-digital Hindi PDFs comes out garbled | High / High for this owner | Detect Devanagari in the extracted text and use the OCR path (or an own ToUnicode-order extractor); add a Word/Chrome-made Hindi PDF fixture to FR-105 |
| R14 [challenge] | Hindi OCR is verified only on macOS 27 (build 26A428); the minimum OS is 26.0 | Medium / High | P2-190 first; OWN-OCR-1 decides the fallback if Hindi is missing on 26.x |

---

## 13. Not scheduled (owner said later or no)

| Item | Owner verdict | Note |
|---|---|---|
| Watch folders | later | Natural follow-on once the CLI (P3-108) and History exist. Would need its own background-activity design (FSEvents, energy) |
| Video/audio extras group: highlights, extract audio, normalise, screen recording → GIF | later ("fifth trick can be skipped for now") | Normalise already exists (P2-36); video → m4a extra is P2-23 |
| Text to speech | no | — |
| Filler-word removal | no | Would depend on word timestamps from transcription |
| Burn-in subtitles | no | — |
| "Replace" (find/replace in names) | no | Rename has no find/replace mode; can be added as a token-free mode if wanted |

---

## 14. Owner decisions (consolidated)

| ID | Question | Recommendation |
|---|---|---|
| OWN-PLAN-1 | Accept Phase 2 as three public betas (0.5 / 0.6 / 0.7, ≈ 38 weeks for one engineer), or apply the §4.3 cut list? | Accept the split; keep the cut list ready |
| OWN-PLAN-2 | Pull visual signature into 0.7? Keep searchable / blank / page size in 0.7? | Keep them in 0.7; sign stays at the start of Phase 3 unless you want the whole PDF suite at beta |
| OWN-W-1 | Actions wheel grows to 9 (ZIP, LOCK, RENAME); Lock/Unlock is one slot | Yes |
| OWN-PDF-1 | Allow non-ASCII PDF passwords even though Preview can't open them? | Allow, with a warning and a check result |
| OWN-PDF-2 | Digital (certificate) signatures in 1.x? | Visual in Phase 3; PAdES B-B as a Phase 4 gate |
| OWN-PDF-3 | Blank-page default | Remove only "blank"; list "nearly blank" for review |
| OWN-PDF-4 | Text-layer font | Bundle Noto Sans Devanagari (OFL, ≤ 0.4 MB) |
| OWN-LK-1 | Policy: no password recovery or bypass; passwords never stored | Approve |
| OWN-LK-2 | Legacy .doc/.xls/.ppt unlock (L effort, shrinking user base) in Phase 3? | Yes, after LK-M3 fixtures exist |
| OWN-LK-3 | Remove Office edit restrictions with a verified password (Phase 4)? | Optional; low value |
| OWN-ARC-1 | RAR creation | No |
| OWN-ARC-2 | 7-Zip helper for encrypted 7z (+2–3 MB) | Phase 3 gate; decide on demand |
| OWN-APP-1 | BOX label; drops go to the most recent box | Yes |
| OWN-APP-2 | Notch tray as the primary home; shake-to-open opt-in in Phase 2 | Yes |
| OWN-APP-3 | Owned-copy storage warning at 2 GB; auto-clear off by default | Yes |
| OWN-APP-4 | "More…" overflow 12th slice | Off; decide after the usability test |
| OWN-APP-5 | History: 30 days, 500 entries, excluded from Time Machine, "Off" keeps 24 h undo data | Yes |
| OWN-APP-6 | CLI subset in 0.7; own Homebrew tap first | Yes |
| OWN-IMG-1 | JPEG XL output at +2.5–3.3 MB | Decide after the measured DMG; accept ≈ 74 MB if needed |
| OWN-MA-1 | Discord preset at 20 MB (drop 10 MB)? | Yes |
| OWN-MA-2 | Drop the WhatsApp 100 MB "document" preset (Business API only)? | Yes |
| OWN-MA-3 | Meeting summaries in English only at first? | Yes |
| OWN-MA-4 | Speaker pack via CoreML (data-only download), sherpa-onnx as fallback? | Yes, after AI-S2 |
| OWN-MA-5 | Confirm "ask in plain words" (needs Apple Intelligence on the Mac) | Confirm; Phase 4 |
| OWN-QA-1 | Manual checks needing your apps: Word/Excel/PowerPoint, iWork, Archive Utility, a Windows 11 VM; real sends to Gmail and WhatsApp; real Hindi scans | Schedule before 0.5 (lock) and 0.6 (presets) |
| OWN-SIZE-1 [challenge] | Expected ungated size is ≈ 70.2–71.6 MB (over the 70 MB target). Accept the overage, or cut it? | Keep the 70 MB target; decide on the measured P1-52 DMG |
| OWN-PDF-5 [challenge] | Honour PDF permission bits when only the user password (or none) is known? | Yes. Copy Text/Searchable ask for the owner password when extraction is disallowed; Merge/Split/Organize/Page Size/No Blanks do the same when assembly/modification is disallowed; Compress keeps the encryption as is |
| OWN-OCR-1 [challenge] | If macOS 26.x has no Hindi in Vision: hide Hindi below 27, or add an optional Tesseract `hin` pack (Apache-2.0; adds code, so it can't be a data-only pack)? | Hide below 27 and say why; revisit only if P2-190 fails on 26.x |
| OWN-PICK-1 [challenge] | Confirm the interpretations "JPEG XL" (not Excel output) and "remove *image* background" (not PDF background/watermark removal) | Confirm |
| OWN-PLAN-3 (2026-10-22) | Order of the first beta | **Decided by the owner:** notch Drop Box first in 0.5 (P2-197 → P2-115 + P2-116 → P2-141 → P2-55 → P2-142 → P2-143), then the earlier 0.5 contents; picker style and place last; the notch tray leaves the cut list |
| OWN-HUD-1 (2026-10-22) | Notch HUD | **Decided by the owner:** yes. Defaults proposed by the assistant: on for Macs with a notch; Settings › General "Show progress and results: At the notch \| Bottom-right corner"; pill on displays without a notch; Reduce Motion → fade |
| OWN-HUD-2 (open) | Today's HUD card opens below-right of the drop point, not in a fixed corner. Name the second choice for what it does, or move it to a fixed bottom-right corner? | Keep today's placement and label it "Near the drop" (17e-app §2a.6) |

---

## 15. Sources

- Cluster reports (prototypes and measurements, 2026-10-21): `17a-pdf.md` §1–§7; `17b-lock.md` §1–§15;
  `17c-image.md` §0–§7; `17d-media-ai.md` §0–§12, including dated web sources for platform limits; `17e-app.md` §1–§7.
- Repository docs (read only): `docs/design/00-decisions.md`; `10-tech-strategy.md` §9, §10, §12;
  `13-image-pdf-engine.md` §4, §6, §8; `docs/plan/01-prd.md` §5.9, §6, §7, §10; `02-architecture.md` §4–§5;
  `05-task-list.md`; `09-m3-record.md`. Added 2026-10-22: `16-transcription.md`, `16a-transcription-evidence.md`.
- Current code (read only): `Packages/ZivletKit/Sources/ZivletCore/Catalog/ToolTable.swift`, which holds today's
  per-format tool lists. Those lists are the basis for the §8.1 counts.
- Owner inputs: the owner picks and the transcription owner answers, both recorded in [00-decisions.md](00-decisions.md) (2026-10-21 section).
