# 17 — Adversarial review of the feature roadmap (17-feature-roadmap, 01b-prd-additions, 05 §9, cluster reports)

> Imported into the repository on 2026-10-21 from the roadmap drafts; approved by the owner the same day
> (see [00-decisions.md](00-decisions.md), 2026-10-21 section). The product name is Zivlet.
> Prototype folders named `<name>.XXXX/` are local prototypes and are not published.
> File map: PRD additions are in [01b-prd-additions.md](../plan/01b-prd-additions.md); task rows are in
> [05-task-list.md §9](../plan/05-task-list.md); the challenge pass is [17-roadmap-challenge.md](17-roadmap-challenge.md);
> cluster reports are [17a-pdf](17a-pdf.md), [17b-lock](17b-lock.md), [17c-image](17c-image.md),
> [17d-media-ai](17d-media-ai.md) and [17e-app](17e-app.md).

Date: 2026-10-21. Reviewer: challenge pass. Every fix is applied in place and marked **[challenge]**. The repository was
only read, never modified.

**Scope.** Every roadmap file, as it was in the 2026-10-21 drafts (now imported; see the file map above):
- the three 17-* files;
- `17b-lock.md`, `17a-pdf.md`, `17c-image.md`, `17d-media-ai.md`, `17e-app.md`.

**Checked against:**
- `docs/design/00-decisions.md`, `10-tech-strategy.md` (§9, §10, §12, §13);
- `docs/plan/01-prd.md`, `02-architecture.md`, `03a`, `03b`, `05-task-list.md`, `09-m3-record.md`;
- current `ToolTable.swift`;
- the macOS 27.0 SDK swiftinterfaces and headers in `/Applications/Xcode.app`.

**Evidence labels:**
- **SDK:** read in the macOS 27.0 SDK.
- **PROBED:** run here; experiment folder named.
- **TALLY:** computed from 05.
- **INFERRED:** reasoning only.

---

## 1. Key corrections (most important first)

| # | Severity | Finding | Fix applied |
|---|---|---|---|
| C1 | **High (policy)** | **PDF owner-password bypass.** P2-106 allowed "Unlock with user or owner password". PROBED (`owner-bypass.ho4Z/probe.txt`): qpdf 12.4.2 `--password=<user> --decrypt` on an R6 file with `print/modify/extract = none` writes a file with **no encryption and no restrictions**. qpdf also reports "Supplied password is user password", so the case can be detected. A plain rewrite with the user password keeps the restrictions. | User-password unlock is allowed only if the file grants all permissions or user = owner. Otherwise the owner password is required. Other tools preserve encryption as is (may be RC4) and never set owner = user. FR-97, P2-106/107, 17a-pdf.md, OWN-PDF-5 |
| C2 | High (policy) | **Permission bits ignored.** "Restrictions-only PDFs can be read and processed" lets Copy Text/Searchable run on extract-disallowed files, and Merge/Split/Page Size/No Blanks on modify- or assembly-disallowed files. That is a bypass in effect under OWN-LK-1. | New owner decision OWN-PDF-5 (recommend: honour the bits unless the owner password is given); risk R12 |
| C3 | High (product) | **Garbled Hindi Copy Text on born-digital PDFs.** 17a-pdf.md's own L1 result shows PDFKit extracts shaped Devanagari in visual order (CER 0.105). P2-104 used PDFKit text for pages that already have text. | Detect Devanagari, then OCR (or an own logical-order extractor); Word- and Chrome-made Hindi PDF fixtures. FR-105, P2-104, R13 |
| C4 | High (privacy/UX) | **Pre-drop content reads.** The LOCK/UNLOCK label probe (FR-92) and tier-0 size estimates (FR-94) read files *during the drag*. That can download iCloud dataless files (network) and can raise TCC folder prompts mid-drag: user-intent access comes with the drop, not on hover (INFERRED; no existing doc covers dataless files). | Before the drop: metadata and Spotlight attributes only; skip `SF_DATALESS` (SDK `sys/stat.h`) and non-current ubiquitous items; content probes after the drop. FR-92/94, P2-114/140, P2-197 scope, R11 |
| C5 | High (spec conflict) | **CHANGE PASSWORD slice breaks FR-18.** It was "visible by default only when every item is encrypted". That adds a slice after the frame-1 header probe, which changes the frame-1 slice set. | It becomes a mode of the Unlock sheet, never a slice. The encrypted-PDF list drops to 11 |
| C6 | High (planning) | **Phase arithmetic mixes units.** The +27 weeks come from the S/M/L tally; the 8–10 weeks are 10 §12's calendar estimate. On the same tally, 05's 47 original Phase 2 rows = **156 days ≈ 31 weeks** (2A originals alone 38 days, not "≈ 3 weeks") (TALLY). Phase 2 **about doubles (+97 %)**; it does not quadruple. The beta release rows (S each) also leave out stabilisation. | Corrected in roadmap §1/§4.1 and tasks §10. Re-sized P2-108 M→L, P2-124 M→L, P2-146 S→M; +1 week stabilisation per beta; P2-10/P2-31 moved out of 2A |
| C7 | Medium (size) | **The 72 MB re-baseline double-counts swift-argument-parser.** It is already in 10 §10, and the CLI is already in 10 §9's Swift-code row. "qpdf saves 4.8 MB" compares against OpenSSL, which was never budgeted, and 3.6 MB is the Homebrew *dynamic* dylib, not the static native-crypto build. | Ungated total ≈ **70.2–71.6 MB**; NFR-24's re-baseline withdrawn; the NFR-7 70 MB target stands; OWN-SIZE-1 |
| C8 | Medium (API) | **`RecognizeDocumentsRequest` has no `.accurate`.** SDK: its `TextRecognitionOptions` = minimumTextHeightFraction, automaticallyDetectLanguage, recognitionLanguages, useLanguageCorrection, customWords, maximumCandidateCount. Only `RecognizeTextRequest` has a recognition level. Language IDs differ by API (Swift `hi-Deva-IN`, VN `hi-IN`). | P2-103, FR-104: match on `languageCode == "hi"` |
| C9 | Medium (privacy) | **Cloud paths left open:** <br>• visual signatures "synced unless opted in" (iCloud Keychain); <br>• P4-110 refine uses `GenerateIterativeSegmentationRequest`, a `DownloadableAssetsRequest` (SDK, macOS 27: `downloadAssets()`), so Apple downloads assets; <br>• the Suggest-password Copy button would go to Universal Clipboard and clipboard managers. | <br>• `kSecAttrSynchronizable = false`, no opt-in; <br>• the download is user-initiated, with a card; NFR-23/FR-137 name OS-managed downloads; <br>• `prepareForNewContents(with: .currentHostOnly)` (SDK, macOS 10.12) plus concealed/transient pasteboard types |
| C10 | Medium (licence/size) | **Diarisation evidence is for an unshippable route.** Only sherpa-onnx was MEASURED, and it ships onnxruntime code (≈ 60 MB), which fails P3-109's data-only rule and library validation. The chosen CoreML route is unmeasured. | sherpa-onnx is a test baseline only; P3-190 must pass first; the licence audit covers the embedding model too |
| C11 | Medium (policy) | **The 7-Zip helper takes passwords on argv** (`-p<pw>`, visible in `ps`), which breaks NFR-21. | P3-113/FR-131: prove a pty/stdin path, or the gate stays closed |
| C12 | Medium (IDs) | **Spike ID collisions with 10 §13:** <br>• lock QA M-1…M-6 vs media spikes M-1…M-6; <br>• I-C1 means two different things; <br>• P-W4 (dwell ring vs UI-sound key); <br>• I-V2 duplicates I-V1/S-V1 in P2-06. <br>Also P3-31 pointed at **P2-152** (Remove Blank Pages) instead of P2-146 (CLI subset). | Renamed LK-M1…6, I-C2, P-W5; P2-190 extends I-V1; P3-31 fixed |
| C13 | Medium (spec) | **Silent PRD changes:** <br>• Recent menu 20 → 10 (PRD §6.6, FR-39); <br>• FR-20 "Actions: fixed 6"; <br>• FR-73 Float, FR-88 CLI and §6.7 "never copies" left as duplicate specs; <br>• P2-61/M5 still mean "beta 0.5 = end of Phase 2" (tag `v0.5.0-beta`, "6 actions"). | Recent stays 20; §A rows added; P2-61 → `v0.7.0-beta`, M5 "9 actions" |
| C14 | Low–Medium | **"LOCK · UNLOCK k of n" overflows the label frame** (03a: 7.5 pt, 82 × 22 pt), and the hot-slice size estimate as a second label line may not fit either. | "k of n" in the OWN-2 badge; estimate in the hub |
| C15 | Low | **ADD BG leaves the default image list.** O-18 defines 1.0 as "27 tools". | Parity counts "reachable" tools, or ADD BG shares a slot with REMOVE BG (folded into OWN-APP-4) |
| C16 | Low | **Roman Hinglish → Translation with source = hi rests on one sentence** (media-ai §6). | Use the transcript's Devanagari form first |
| C17 | Low | **FR-98 "byte-identical round trips"** can only mean the plaintext (the salts are random). iWork opening encrypted OOXML is statically inferred, but it was a release gate. | Clarified; iWork made informational; Word/Excel/PowerPoint (LK-M1/M2) stay the gate |

---

## 2. API claims checked against the macOS 27.0 SDK

The deployment target is macOS 26.0. Availability is taken from the `@available` annotations.

| Claim (where) | SDK evidence | Verdict |
|---|---|---|
| `RecognizeDocumentsRequest` (P2-103) | `@available(macOS 26.0)`, Vision.swiftinterface | OK. **No `.accurate`** (C8) |
| `RecognizeTextRequest .accurate` | macOS 15.0 | OK (fallback) |
| `GenerateForegroundInstanceMaskRequest` (Swift) | macOS 15.0 exists; 17c-image.md PROBED it returns `requestCancelled` | Keep the VN path (P2-194) |
| `VNGenerateForegroundInstanceMaskRequest`, `VNInstanceMaskObservation.instanceMask/allInstances` | VNObservation.h | OK |
| `instanceAtPoint(_:)` (P3-103) | Only on Swift `InstanceMaskObservation` | On the VN path, read `instanceMask` (fixed) |
| `GenerateIterativeSegmentationRequest` (P4-110) | macOS 27.0; conforms to `DownloadableAssetsRequest` | OK, but **network** (C9) |
| `GenerateObjectnessBasedSaliencyImageRequest` (P4-104) | macOS 15.0 | OK |
| `SecCreateSharedWebCredentialPassword` (P2-101) | `API_AVAILABLE(macos(11.0))`; format `xxx-xxx-xxx-xxx` | OK |
| `NSScreen.safeAreaInsets`, `auxiliaryTopLeftArea/RightArea` (P2-143) | `API_AVAILABLE(macos(12.0))` | OK |
| Bookmark `.withoutImplicitSecurityScope` / `.withoutImplicitStartAccessing` (P2-141) | macOS 10.7 / 11.2 | OK |
| `TranslationSession(installedSource:target:)` (P3-112) | macOS 26.0; `canRequestDownloads`, `isReady` macOS 26.0 | OK |
| `.translationTask` (P3-112) | `_Translation_SwiftUI` | OK |
| `SystemLanguageModel.tokenCount(for:)` (P4-101) | **macOS 26.4** | Needs a gate or fallback (fixed) |
| `contextSize` | back-deployed (before 26.4) | OK |
| `PrivateCloudComputeLanguageModel` (FR-137 lint) | Exists in FoundationModels, macOS 27 (`networkFailure`, `quotaUsage`) | The lint target is real. Keep the ban |
| `PDFDocumentWriteOption.saveTextFromOCROption` | PDFDocument.h + apinotes | Exists; 17a-pdf.md PROBED that it writes nothing. The own text layer stays |
| `NSPasteboardContentsCurrentHostOnly` | macOS 10.12 | Use it for password/OCR copies |
| `SF_DATALESS` | `sys/stat.h` | Use it for pre-drop skipping |

Not checkable here: behaviour on macOS 26.x (this Mac runs 27.0 build 26A428). Every PROBED result still needs a 26.x
re-run (P2-190, P0-30).

---

## 3. Phase realism (TALLY, S = 1 d, M = 3 d, L = 7.5 d)

| Block | Days | Weeks (5 d) | Note |
|---|---|---|---|
| 05 Phase 0 rows (40) | 108 | 21.6 | 10 §12 says "about 3 weeks" |
| 05 Phase 1 rows (46) | 136.5 | 27.3 | 10 §12 says "6–8 weeks" |
| **05 Phase 2 rows (47)** | **156** | **31.2** | 10 §12 says "8–10 weeks"; the roadmap compared its additions against this calendar number |
| 05 Phase 3 rows (29) | 119.5 | 23.9 | 10 §12 says "10–12 weeks" |
| 17 Phase 2 additions (as written) | 136.5 + 14 spikes | 30.1 | — |
| 17 Phase 2 additions (after re-sizing + stabilisation) | ≈ 163 + 14 | ≈ 35 | P2-108/124 → L, P2-146 → M, 3 × 5 d of beta stabilisation |

**Reading.**
- 10 §12's calendar figures are about 3.5× faster than the tally throughout, which matches agent-built speed (M1–M3
  took days).
- So the honest statement is: **Phase 2 roughly doubles**. In 10 §12 terms, that is ≈ **+9–11 calendar weeks**
  (≈ 17–21 weeks in total).
- The "≈ 38 weeks, nearly quadruples" claim is wrong both ways: too large in calendar terms, and too small in tally
  terms (≈ 66 weeks).
- The cut list (§4.3) stays valid.

**Wave fixes:**
- **P2-10 ZivletRS has no 2A consumer.** Move P2-10 and P2-31 to 2B (−6 days from the first beta).
- **0.5 now ships without documents and promise drags.** P2-61/M5/PRD §10 must be relabelled (C13).

**Effort re-sizes:**

| Row | Was | Now | Why |
|---|---|---|---|
| P2-108 EngineOfficeCrypto | M | **L** | The crypto is proven (spike, 508 lines). The rest is CFB v3+v4 writing, DIFAT, Standard read, IRM detection and a fuzz harness to production quality |
| P2-124 Rename | M | **L** | Journal, two-phase rename, crash recovery, sidecar/Live Photo grouping, per-volume name rules |
| P2-146 CLI subset | S | **M** | JSON/NDJSON, SIGINT process-group teardown, helper lookup, matrix wiring |

**Still optimistic, not changed:**
- P2-121 Reel (L): mixed stills and clips with different fps/sizes/audio presence, plus a ducked music bed.
- P2-150 Searchable (M): needs its overlay-per-page writer productised, beyond the prototype.

---

## 4. Size budget

- 10 §9 expected: 68.8 MB. The roadmap's ungated additions were +2.2–3.6 MB.
- Remove swift-argument-parser (+0.83): it is already budgeted. That gives **+1.4–2.8 MB → ≈ 70.2–71.6 MB**.
- That is still over the 70 MB target by up to 1.6 MB. The uncertainty in the Swift-code row (6–14 MB) dwarfs it.
- **Decision:** keep NFR-7. Decide on the measured P1-52 DMG (OWN-SIZE-1).
- **Cheap levers:**
  - subset Noto Sans Devanagari to Devanagari + Latin;
  - keep the JXL and 7zz gates closed.
- libjxl: 17c-image.md's 3.28 MB is Homebrew **0.11.2** dylibs. The 0.12 static figure (2.5–3 MB) is an estimate. 10 §9
  says +3–5 MB. Use the range 2.5–5 MB until it is measured.
- Model packs, Translation packs and Vision assets: never in the bundle. Confirmed.

---

## 5. Licences (GPL-3.0-or-later)

No conflicts found. Notes:
- **Compatible, already in 10 §10:**
  - qpdf (Apache-2.0);
  - libarchive (BSD-2);
  - oxipng (MIT);
  - imagequant (GPL-3.0+, ties `libzivlet_rs` to GPLv3, already accepted);
  - libjxl (BSD-3 + patent grant);
  - swift-argument-parser and swift-asn1 (Apache-2.0).
- **Noto Sans Devanagari (OFL-1.1):** fine as an aggregate. Ship it with `OFL.txt` as a separate resource, as 10 does
  for Carlito/Caladea. Embedding subsets in output PDFs is allowed.
- **EngineOfficeCrypto:** our own code from MS-OFFCRYPTO/MS-CFB. The Open Specification Promise is a patent non-assert;
  its GPL fit has been questioned, but the risk is low because there is no copied code (INFERRED, not legal advice).
  msoffcrypto-tool, pyzipper, poppler and pdfium are test-only oracles and are never shipped. Confirmed.
- **7-Zip helper:** LGPL-2.1+/BSD-3 without RAR codecs, as a separate program. The licence is fine. The policy problem
  is passwords on argv (C11).
- **Diarisation packs:** FluidAudio code is Apache-2.0. The models need a per-model audit covering the embedding model
  (CAM++/WeSpeaker, VoxCeleb-derived) as well as segmentation (pyannote seg-3.0 MIT, community-1 CC-BY-4.0
  attribution). Host them on project release assets, not on gated Hugging Face URLs.
- **RAR:** no creation and no unRAR code. libarchive's own RAR reader is BSD. Confirmed.

---

## 6. Privacy and network

| Path | Status after review |
|---|---|
| Vision OCR, background removal, saliency, Foundation Models, PDFKit/Quartz, libarchive, qpdf, Office crypto | On device |
| Model packs (speaker, transcription) | User click; SHA-256 pinned; own hosting |
| Translation language packs (macOS) | OS download after a system prompt. Now named in NFR-23/FR-137 |
| Vision downloadable assets (P4-110, macOS 27) | **Added:** user-initiated card, privacy copy |
| Signatures in Keychain | **Fixed:** never synchronizable |
| Suggest-password / OCR clipboard | **Fixed:** `.currentHostOnly`; concealed/transient markers for passwords |
| Pre-drop probes (lock label, size estimates) | **Fixed:** metadata only; skip dataless; no TCC-triggering reads mid-drag (needs the P2-197/P0-33 spike) |
| Drop Box owned copies | Local, under `Application Support`. Auto-clear stays OWN-APP-3 |
| Share/AirDrop from the Drop Box | User-chosen system services. Fine |
| Private Cloud Compute | The symbol exists in the macOS 27 SDK. The CI lint ban is meaningful |
| No telemetry | No new telemetry found. The local estimate-vs-actual log must stay out of Copy Diagnostics, or be stripped of file names |

---

## 7. Lock and unlock scope (no cracking)

**Holds:**
- no brute force, no ZipCrypto known-plaintext attack, no IRM/DRM removal;
- the NFC/NFD retry re-encodes the same password, so it is not guessing;
- edit-restriction removal (P4-109) needs a verified password;
- no attempt limit, which is right for local files.

**Was broken:**
- PDF user-password unlock stripping owner restrictions (C1, PROBED);
- tools ignoring permission bits (C2).

Both are now covered by the rule and OWN-PDF-5.

---

## 8. Office encryption in Swift: feasible

- 17b-lock.md's `lock-swift.1LSg` spike (CFB + ECMA-376 Agile on CommonCrypto, 508 lines) decrypts reference-encrypted
  docx/xlsx/pptx byte-identically and produces files the reference tool decrypts. It covers HMAC tamper detection and
  the DIFAT path (38 MB, lock 318 ms under load).
- CommonCrypto provides everything needed: AES-CBC, SHA-512, HMAC-SHA512, and RC4/MD5 for legacy unlock.
- Remaining risks:
  - Word/Excel/PowerPoint acceptance of our CFB (LK-M1/M2, the gate);
  - v4 4096-byte sectors on small files (17b-lock.md already says use v3);
  - iWork acceptance (inferred, now informational).
- Effort: L, not M (C6).

---

## 9. Hindi OCR claims

- **Verified (macOS 27 only):**
  - `hi-Deva-IN`/`mr-Deva-IN` are listed for the accurate requests;
  - 12/12 rendered fixtures at 0–0.8 % CER with `[hi, en]`;
  - a synthetic bad scan (≈ 70 DPI) at CER 0.079–0.096.
- **Not verified:**
  - macOS 26.x language support (the minimum OS);
  - real scans and phone photos (P2-191);
  - Roman Hinglish quality in `hi`-first mode. 17a-pdf.md shows "mecting … nai" on the bad scan, perfect in auto mode;
    17c-image.md shows all 12 pass. The evidence is mixed.
- **Cold compile:** 6–10 minutes. Keying the cache by process identity is INFERRED from one test, and 17c-image.md
  disagrees. Pinning Vision to the worker is right either way.
- **FR-105's release gate** (real-scan median CER ≤ 0.05) is reasonable, but it is a gate on data that doesn't exist
  yet. OWN-OCR-1 decides the fallback if 26.x lacks Hindi.

---

## 10. Conflicts with existing IDs and wheel caps

- **FR-90…141 and NFR-21…24** don't collide with the PRD (last FR-89, NFR-20). Task IDs ≥ 100 don't collide with 05
  (last P2-61, P3-42).
- **`ToolID.pdfCombine` already exists** in `ToolTable.swift` as MERGE PDF (multi-only, editor, suffix "Merged").
  Folding CREATE PDF (`pdfFromImages`) into it, as the roadmap does, is consistent. Keep `pdfFromImages` as a decode
  alias, as planned.
- **Caps (after the fixes):**
  - images multi 12 (at cap);
  - video single 12 (at cap, including the reserved TRANSCRIBE);
  - encrypted PDF single **11** (was 12);
  - Actions 9 default + 4 extras.
- **Video single at the cap leaves no room** for anything 16-transcription.md may want (for example SUBTITLES).
  Transcription must replace a default or use extras.
- **W-6 dwell ring:** geometry beyond r 125.92 conflicts with FR-24 edge clamping. The spike (now P-W5) and the picker
  fallback are kept.
- **Duplicate FRs to mark:** FR-136 ⊃ FR-88, FR-132/133 ⊃ FR-73, FR-93 amends FR-20 (C13).

---

## 11. Clean-room spot check

New labels were checked against the reference app's public UI copy: COPY TEXT, REMOVE BG, FIT FOR…, STITCH, REEL,
NO SILENCE, SEARCHABLE, NO BLANKS, PAGE SIZE, PEEK, BOX. **None of them matches the reference app's UI strings.**
"Fit for email" is our own wording from earlier product notes (not published), and no reference-app wording is reused. Prior-art shelf
apps are named but not copied.

---

## 12. Owner decisions (new or amended by this review)

| ID | Question | Recommendation |
|---|---|---|
| **OWN-PDF-5** (new) | Honour PDF permission bits when the owner password isn't given? | **Yes.** Copy Text/Searchable ask for the owner password when extraction is disallowed; Merge/Split/Organize/Page Size/No Blanks do the same for assembly/modify; Compress keeps encryption as is |
| **OWN-SIZE-1** (new) | Expected ≈ 70.2–71.6 MB ungated. Accept the overage or cut? | Keep the 70 MB target; decide on the measured DMG |
| **OWN-OCR-1** (new) | Fallback if macOS 26.x lacks Vision Hindi | Hide Hindi below 27 with a reason. A Tesseract `hin` pack is code, not data, so avoid it unless P2-190 fails |
| **OWN-PICK-1** (new) | Confirm the dictation readings "JPEG XL" (not Excel output) and "remove *image* background" (not PDF background/watermark) | Confirm |
| OWN-PLAN-1 (amended) | Phase 2 ≈ 2× original (tally) or ≈ +9–11 calendar weeks; three betas | Accept the split; apply the re-sizes; keep the cut list |
| OWN-MA-4 (amended) | Speaker pack: CoreML only; sherpa-onnx is not a shipped fallback | Yes, after P3-190 measures CoreML |
| OWN-APP-4 (amended) | "More…" overflow **and** how parity counts tools moved to extras (ADD BG) | Count "reachable" for O-18 |
| OWN-APP-5 (amended) | History 30 days / 500 entries; **Recent menu stays 20** | Yes |
| OWN-ARC-2 (amended) | 7-Zip helper only if passwords avoid argv | Gate stays closed until proven |

All other OWN-* items in 17-feature-roadmap §14 stand as written.

---

## 13. Files changed by this review

All changes were made in the draft copies, before the import into `docs/`:
- `17-feature-roadmap.md`: §1, §2, §4.1, §5.1, §5.3, §5.4, §5.5, §8.1, §8.4, §9, §10, §11, §12 (R11–R14), §14
  (4 new decisions).
- `01b-prd-additions.md`: §A (5 rows), §B CHANGE PASSWORD, FR-92/94/96/97/98/104/105/112/131/137/139/140, NFR-23/24,
  ID renames.
- `05-task-list.md` §9:
  - §0 ID renames; P2-13/61, P3-31 fix;
  - P2-103/104/106/107/108/109/111/114/119/124/131/139/140/146/159;
  - P3-101/103/104/113, P4-100/101/110;
  - spikes P2-190/193/195/196/197, P3-190; tally note.
- `17b-lock.md`, `17a-pdf.md`, `17c-image.md`, `17d-media-ai.md`, `17e-app.md`: a [challenge] header each, plus inline marks in `17a-pdf.md`
  (D-PDF-4, F2, signatures) and `17e-app.md` (Recent 20).
- Experiments and tools (local prototypes, not published):
  - `owner-bypass.ho4Z/` (qpdf probe; `probe.txt`);
  - `challenge-tools.0iTM/` (anchor-checked edit scripts).
