# 01b — Zivlet PRD additions for the owner's feature picks (FR-90…FR-141, NFR-21…NFR-24)

Date: 2026-10-21. Status: **approved by the owner 2026-10-21** ([00-decisions](../design/00-decisions.md)).
This file extends [01-prd.md](01-prd.md), which would pass 800 lines if merged; read the two together. IDs are
as corrected by the challenge pass ([17-roadmap-challenge.md](../design/17-roadmap-challenge.md)). Numbering continues after the PRD's
last requirement (FR-89, NFR-20). Format is the PRD §7 format: ID · requirement · acceptance criteria (AC) · phase.
Every AC is automated unless marked (M) = manual QA.

Phase labels: **P2a / P2b / P2c** = public betas 0.5 / 0.6 / 0.7 (Phase 2 split, see [17-feature-roadmap](../design/17-feature-roadmap.md) §4);
P3 = 1.0; P4 = 1.x. Tasks: see [05-task-list.md §9](05-task-list.md). Evidence: cluster reports `17a-pdf.md`, `17b-lock.md`, `17c-image.md`,
`17d-media-ai.md`, `17e-app.md` in `docs/design/`.

Naming follows PRD §5.9 (`<base> <Suffix>.<ext>`, multi-input `<first base> <Suffix>`). The cluster reports' parenthesised
names ("(No Silences)", "(WhatsApp)") are normalised here to the §5.9 form.

---

## A. Scope edits to existing PRD sections

| Section | Edit |
|---|---|
| §3.2 Non-goals | Add: Zivlet never recovers, guesses or bypasses a password it was not given (no brute force, no ZipCrypto known-plaintext attack, no stripping restrictions without the password, no DRM/IRM removal). |
| §6.2 Tools | Add the tools in §B below; retire "Create PDF" into "Combine PDF" (ToolID alias kept). Tool count no longer equals 27; parity accounting keeps the 27 originals. |
| §6.3 Actions | Actions wheel grows: `BOX` (renamed Float), `ZIP`, `LOCK`, `RENAME` default; `7Z`, `TAR.GZ`, `TAR.XZ`, `TAR.ZST` extras. Replace "never use the worker" with "Actions never import engines; ZIP and LOCK submit a job through the app coordinator". |
| §6.4 Settings | New panes/sections: Wheels (custom layouts), Presets (fit-to-size table + user presets), Text recognition (language order), History (retention), Engines (model packs). |
| §6.7 Float shelf | Becomes the Drop Box (§FR-132) with the notch tray as its primary home (§FR-133). |
| §6.9 Backlog | Remove the items now planned (B4-05/06/07 partly/09/10/12/15/16, B5-03/04). |
| §10 Phases | P2 row splits into P2a/P2b/P2c with exit criteria from 05 M5a/M5b/M5c (05 §9.2). |
| FR-20 [challenge] | "Actions: fixed 6" becomes "Actions: 9 default (FR-93), ≤ 12 with extras". 05 M5 and O-18's "6 actions" are read as "at least the 6 parity actions". |
| FR-39 / §6.6 [challenge] | Keep "Recent results (last 20)" and Undo for the last 20 operations. History (FR-135) is separate. Do not shrink the menu to 10. |
| FR-73 / §6.7 [challenge] | FR-73 is superseded by FR-132/FR-133. §6.7's "references files (never copies)" becomes "references files; owned copies only for promise/clipping content". |
| FR-88 [challenge] | FR-136 extends FR-88 (the CLI subset moves to P2c). The 0/1/2/3/130 exit codes are kept, and 5/6/7 are added. |
| §10 / 05 M5 / P2-61 [challenge] | "Public beta 0.5" now means wave 2A. The end of Phase 2 is 0.7 (`v0.7.0-beta`). The 221-pair / 19-tool exit applies to 0.7, not 0.5. |

## B. New tools and slices (summary; full wheel lists in 17-feature-roadmap §8)

| Wheel label | ToolID / ActionID | Inputs (single / multi) | Kind | Output | Ph |
|---|---|---|---|---|---|
| COPY TEXT | `textCopy` | raster images, PDF / multi | instant | clipboard; ⌥ `X Text.txt` | P2a |
| LOCK · UNLOCK (one slot) | `protect` | pdf, OOXML, zip / multi | window (sheet) | `X Locked.ext` / `X Unlocked.ext` | P2a |
| CHANGE PASSWORD (sheet mode, not a slice [challenge]: a slice that appears only for encrypted items changes the frame-1 set, FR-18) | `changePassword` | encrypted pdf, OOXML, zip | window | `X.ext` re-locked as `X Locked.ext` | P2a |
| LOCK (Actions) | `lock` | any file, folder, mix | window | `X Locked.zip` (or native) | P2a |
| RESIZE | `imageResize` | raster images / multi | window (popover) | `X Resized.ext` | P2b |
| RENAME… (Actions) | `rename` | any files / multi | window (sheet) | renamed in place (journal, Undo) | P2b |
| REMOVE BG | `imageCutout` | raster images / multi | instant | `X No Background.png` | P2b |
| COMBINE PDF / MERGE PDF | `pdfCombine` | multi only: images, svg, pdf (+ docs P2c) | window (optional review) | `<first> Combined.pdf` / `Merged.pdf` / `Images.pdf` | P2b |
| REEL | `mediaReel` | multi only: images + videos | window | `<first> Reel.mp4` | P2b |
| STITCH | `imageStitch` | multi only: images | instant (⌥ options) | `<first> Stitched.png` | P2b |
| GIF | `imageAnimate` | multi only: images | instant (⌥ options) | `<first> Animation.gif` | P2b |
| THUMBNAILS | `contactSheet` | multi only: images, videos, pdf | instant | `<first> Contact Sheet.pdf` | P2b |
| JOIN (audio) | `audioJoin` | multi only: audio | window | `<first> Joined.m4a` | P2b |
| NO SILENCE | `mediaSilence` | audio, video with audio / multi | instant (⇧ Tight) | `X No Silences.ext` | P2b |
| FIT FOR… | `fitFor` | video, audio, image, pdf / multi | ring or picker | `X WhatsApp.ext`, `X Reel.mp4` … | P2b |
| ZIP / 7Z / TAR.* (Actions) | `archiveZip` … | any / multi | instant (⌥ options) | `Folder.zip` / `Archive.zip` | P2c |
| PEEK | `archivePeek` | archives | window | none (extract selected) | P2c |
| SEARCHABLE | `pdfSearchable` | pdf / multi | instant | `X Searchable.pdf` | P2c |
| PAGE SIZE | `pdfPageSize` | pdf / multi | window | `X A4.pdf` | P2c |
| NO BLANKS | `pdfBlankPages` | pdf / multi | instant + Review | `X Blank Pages Removed.pdf` | P2c |
| SIGN | `pdfSign` | pdf | window | `X Signed.pdf` | P3 |
| JXL (convert target) | catalog pair | raster images → jxl; jxl → jpg (original) | conversion | `X.jxl` | P3 |
| TRANSCRIBE (reserved) | `transcribe` | audio, video | per docs/design/16-transcription.md | per 16 | P3 (slot) |
| TRANSLATE | `translate` | txt, srt, vtt transcripts | instant | `X English.srt` | P3 |
| NOTES | `meetingNotes` | audio, video (or option in TRANSCRIBE) | window | `X Meeting Notes.md` | P4 |

---

## C. Functional requirements

### C.1 Wheel and catalog

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-90 | Every slice list is capped at 12 by catalog visibility, not by truncation | Each applicability row marks tools `defaultVisible` or `extra`; builder caps tools, same-family conversions and actions at 12; lint fails if any default list > 12; extras reachable via custom wheels, App Intents and CLI; table test over all inputs | P2a |
| FR-91 | Combining tools appear for mixed-family multi-file drops | Images+PDF+docx drop shows COMBINE PDF; images+videos shows REEL; any mix shows Actions ZIP/LOCK; table tests over 30 mixed sets; combining tools never appear for single-file drops | P2a |
| FR-92 | Lock/Unlock share one slot whose label refines without moving slots | Frame-1 slot set unchanged (FR-18 replay suite still ≥ 99 %); label LOCK/UNLOCK/"LOCK · UNLOCK k of n" within ≤ 100 ms p95 of the tap; signpost test shows header probe ≤ 30 ms off the main thread. [challenge] "k of n" goes in the OWN-2 badge, because the 82 × 22 pt / 7.5 pt label frame can't hold it. The pre-drop probe reads no content from `SF_DATALESS`/non-current iCloud items and none that would raise a TCC prompt; those keep the provisional label. CHANGE PASSWORD is never added as a slice | P2a |
| FR-93 | Actions wheel adds ZIP, LOCK, RENAME (default) and archive-format extras | Actions list = AirDrop, BOX, Copy, Move, Copy Path, Terminal, ZIP, LOCK, RENAME by default (9 ≤ 12); `ZivletActions` imports no engine (check-imports); ZIP/LOCK jobs appear in the HUD and History like any job | P2a (LOCK) / P2b (RENAME) / P2c (ZIP) |
| FR-94 | Hot slice shows a size estimate | Tier 0 label on highlight read from cache in ≤ 1 frame; "≈ value (−n %)", "≤ target", "Already smaller" or a range; constant-quality video never shows a single number; setting default on; estimates never delay a drop; image tier 1 error ≤ ±10 % (P4). [challenge] Tier 0 uses only metadata (file size, type, Spotlight pixel size and duration) before the drop: no content reads, no ffprobe spawn and no dataless download during a drag. The value shows in the hub if the petal label frame can't fit a second line | P2c / P4 |
| FR-95 | Fit-to-size presets from a dated table | Defaults WhatsApp media 15.5 MB, Gmail 18 MB, Discord 19.4 MB; JSON fields `limitBytes`, `safetyMargin`, `kind`, `verifiedOn`, source; user presets; output ≤ target on the corpus on the first try for video (VT ABR) in ≥ 95 % of cases, retry ≤ 3; "Already fits" writes nothing; unreachable target refused before encoding with the minimum achievable size; PDF uses P2-33 search with the pre-flight guard | P2b |

### C.2 Passwords and protection

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-96 | One password sheet and one policy for every family | Lock (password + confirm + Suggest), Unlock (one field, shake on wrong, no attempt limit), Change (current + new + confirm); NFC/NFD retry; batch "same password for all" + failure re-list; passwords never stored (no Keychain), never logged, never in argv/env/History; footer "Zivlet can't recover forgotten passwords…"; policy tests (NFR-21) pass. [challenge] The Suggest → Copy button writes with `prepareForNewContents(with: .currentHostOnly)` (no Universal Clipboard sync) and marks the item `org.nspasteboard.ConcealedType`/`TransientType` so clipboard managers skip it | P2a |
| FR-97 | Lock, unlock and change password of PDFs with AES-256 only | qpdf R6 AESv3 output verified (`/Encrypt` R6) on every file; RC4/AES-128 never written; restrictions optional with separate owner password; restrictions removed only with the owner password ([challenge]: Unlock with the *user* password is allowed only when the file grants all permissions or user = owner, as qpdf reports which password matched; Zivlet never re-encrypts with owner = user; encrypted inputs to other tools keep their encryption as is via qpdf preserve-encryption, which may be RC4, and are re-encrypted as AES-256 only when the owner password is known; permission bits honoured per OWN-PDF-5); non-ASCII password warning + "opens on Mac" check result in the card; encrypted inputs to any PDF tool keep their protection; public-key encryption → `unsupportedEncryption`; S-PDF-LOCK matrix (M) | P2a |
| FR-98 | Lock, unlock and change password of Word, Excel and PowerPoint files | Agile AES-256/SHA-512/100,000 spins written; Agile and Standard read; byte-identical *plaintext* round trips against the reference oracle (dev-only) ([challenge]: ciphertext is never byte-identical because the salts are random); HMAC tamper → `integrityFailed`; IRM → `drmProtected`; 38 MB file lock ≤ 2 s on an idle M1; Word/Excel/PowerPoint open locked files with a prompt (LK-M1, LK-M2: release gate); Pages/Numbers/Keynote results are recorded and shown in the sheet note, but they are informational, not a gate ([challenge]: iWork support for encrypted OOXML is only statically inferred) | P2a |
| FR-99 | Lock, unlock and change password of ZIP archives | AES-256 (AE-1/AE-2) default; ZipCrypto only via an explicit weak toggle with ASCII passwords; change password in one pass; entries, dates, permissions kept; names NFC; wrong password → `wrongPassword`; Archive Utility prompts (LK-M4) | P2a |
| FR-100 | Lock any file, folder or mixed drop | Output `X Locked.zip` / `n Files Locked.zip` readable by bsdtar, 7-Zip and pyzipper; Office/PDF default to native lock ("Keep format"); encrypted DMG option `X Locked.dmg` mounts only with the password (P3); sheet notes that ZIP shows file names | P2a / P3 (DMG) |
| FR-101 | Encrypted inputs ask for the password instead of failing | Any route whose probe reports `passwordRequired` opens the Unlock sheet first; decrypted data only in memory or 0700 staging; converted output not encrypted and the card says so | P2a (ZIP, PDF) / P3 (documents) |
| FR-102 | Unlock legacy .doc, .xls, .ppt (never lock them) | Per format, ships only when its Office-made fixture corpus opens without a prompt in Word and Pages/Numbers; lock offers "convert to .docx/.xlsx/.pptx first" | P3 |
| FR-103 | iWork passwords and Office edit restrictions (opt-in, verified) | iWork via Apple Events only with O-17 opt-in and the app installed, `saving in keychain false`; edit restrictions removed only after verifying the typed password against the stored hash | P4 (owner gate) |

### C.3 Vision (OCR, background)

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-104 | One shared OCR core with Hindi-safe language order | Hindi first when Hindi/Marathi is in the user's languages or keyboards; auto-detect not default; all Vision work in the worker; capability probe hides Hindi where unsupported ([challenge]: match on `Locale.Language.languageCode == "hi"`, because the Swift API lists `hi-Deva-IN` while VN lists `hi-IN`; `RecognizeDocumentsRequest` has no recognition level, and only `RecognizeTextRequest` has `.accurate`); warm-up after onboarding and after OS updates; CI fixture fails if a Devanagari golden returns no Devanagari | P2a |
| FR-105 | Copy text from images (and PDF pages) to the clipboard | 12/12 rendered fixtures (Hindi, Hinglish Roman/mixed, English, dark, degraded, Devanagari digits) ≤ 1 % CER; real-scan median CER ≤ 0.05 (S-OCR-HI); ⌥ writes `X Text.txt` UTF-8 LF; multi combines with separators; "No text found" is not an error; History never stores the text; first use before warm-up shows the one-time state and completes. [challenge] PDF pages with an existing text layer: if the extracted text contains Devanagari, use OCR (or an own logical-order extractor), because PDFKit returns shaped Devanagari in visual order (17a-pdf.md L1, CER 0.105). Add a Word-made and a Chrome-made Hindi PDF to the fixtures. Clipboard writes use `.currentHostOnly` | P2a |
| FR-106 | Remove image background on device | One tap writes `X No Background.png` (HEIC/WebP keep format with alpha); soft mask at full resolution; "No subject found" is not an error; subject picker (P3) and macOS 27 refine (P4) | P2b / P3 / P4 |

### C.4 PDF suite

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-107 | qpdf is the structural PDF engine; PDFKit never re-saves signed, form or encrypted files unasked | Pre-flight reports encryption, AcroForm, signatures, tags, attachments, JS ≤ 50 ms/100 pages; every output passes qpdf `--check` and a re-open; merged forms stay live; any PDFKit write rewritten through qpdf | P2a |
| FR-108 | Merge and split ("unmerge") losslessly | Merge keeps the first file's outline and live fields; split instant (every page) plus Every N, Ranges (`end`, `z`, reverse), Odd/Even; 63-page split < 1 s; by size / by bookmarks (P4) | P2a / P4 |
| FR-109 | Make PDFs searchable (Hindi + English) without changing page content | Pages with text skipped; invisible per-word layer in logical order at natural advances; Preview Find finds 9/9 Hindi+English test words; poppler CER 0.000 on fixture; page images byte-identical to input; cancellable progress | P2c |
| FR-110 | Remove blank pages safely | 15/15 labelled corpus; 0 content pages classed blank on S-BLANK-1 with ≥ 95 % blanks caught; nearly-blank kept and listed with Review…; pages with fields, links or signatures never removed | P2c |
| FR-111 | Resize pages to a paper size | A4/Letter/Legal/A5/A3/custom, Fit/Fill/Actual, auto-orient; images not re-encoded (same byte size ± 1 %); flattening warned; lossless v2 keeps links and fields (P4) | P2c / P4 |
| FR-112 | Visual signatures | Draw/type/image capture; Keychain-only storage, `kSecAttrSynchronizable = false`, no iCloud sync option ([challenge]); placement on any page; written as an incremental update (original bytes are a prefix); existing signatures stay valid where DocMDP allows; refuse when DocMDP forbids changes; usability test (M) | P3 |
| FR-113 | Digital signatures (PAdES B-B), gated | Valid in Acrobat with a test CA and EU DSS; no network TSA by default | P4 (owner gate) |

### C.5 Images

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-114 | Batch resize | Long edge / width / percent / fit-in-box; never upscale by default; SSIMULACRA2 ≥ 90 vs linear Lanczos; EXIF date kept, orientation baked, P3 kept unless Web; animated inputs keep all frames; card "n resized · k skipped · size before → after" | P2b |
| FR-115 | Batch rename with preview and Undo | Tokens, presets, sort orders; conflicts block apply; swaps/cycles/case-only work; Undo restores exactly (`ls` diff clean) and skips changed files; crash recovery from the journal; capture time zone; sidecars move together | P2b |
| FR-116 | Smaller PNG | Every → PNG output is optimised losslessly (pixel-identical); lossy colour reduction only when quality ≥ 90, refused for photos with a convert suggestion; never bigger than input | P2b |
| FR-117 | JPEG XL output | JPEG → JXL lossless transcode reconstructs the identical JPEG (`cmp`); other inputs lossy d1.0 by default; metadata and ICC kept; ships only if the size decision allows (OWN-IMG-1) | P3 |

### C.6 Multi-file

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-118 | Combine anything into one PDF | Images, SVG, PDFs (P2b) and docx/xlsx/csv/pptx/md/txt (P2c) → one PDF; one bookmark per source; page size Fit/A4/Letter; order Finder/name/date; review sheet with drag reorder; optional contents page (P2c); encrypted PDFs prompted; 50-file golden | P2b / P2c |
| FR-119 | Photos and videos into one reel | Stills N s, clips kept, optional music (ducked), crossfades, 16:9/9:16/1:1; duration = Σ − crossfades ± 1 frame; A/V drift ≤ 1 frame; plays in QuickTime and is `isPlayable` | P2b |
| FR-120 | Stitch images into one long image | Vertical/horizontal; widths normalised; > 65,000 px handled (split or PNG with warning); ICC kept | P2b |
| FR-121 | Images to animated GIF | Frame delay, width, loop options; frame count = inputs; optional animated WebP | P2b |
| FR-122 | Contact sheet | Grid with captions, A4/Letter PDF or PNG; videos use the first frame, PDFs the first page | P2b |
| FR-123 | Join audio into one track | Order as dropped/name; optional crossfade; loudness matched (−16 LUFS ± 1 LU) unless off; duration within ± 1 frame | P2b |
| FR-124 | Batch actions on all files | Convert, Compress, Resize, Rename and Fit for… run on every file of a multi drop with one summary line; one failure never stops the batch (FR-43) | P2b |

### C.7 Media

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-125 | Remove silences from audio and video | Adaptive threshold; Natural/Tight; frame-accurate cuts; 100-segment fixture end drift ≤ 25 ms and A/V offset < 1 frame; "No long pauses found" writes nothing; transcript/subtitle sidecars (if any) remapped through the keep list | P2b |
| FR-126 | Instagram presets | Reel 9:16, Portrait 4:5, Square 1:1 for video and images; Fill/Fit/Blur fill; H.264 High + AAC + faststart; > 3:00 advisory with optional trim, never silent; smart crop (P4) | P2b / P4 |

### C.8 Archives

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-127 | Create archives from any drop | ZIP default; 7z, tar.gz, tar.xz, tar.zst extras; level, one-per-item, AES password (ZIP), Mac-junk stripping default on; names `Folder.zip` / `Archive.zip`; never RAR | P2c |
| FR-128 | Extract every format libarchive reads | zip, 7z, rar/rar5, tar family, gz, bz2, xz, zst, lz4, iso, cab, lha, cpio; smart single top folder; never overwrite; batch; limits and quarantine (NFR-13); encrypted 7z/RAR → clear unsupported copy until FR-131 | P2a |
| FR-129 | Peek inside an archive | Lists entries without extracting; Quick Look and extract of selected entries; limits enforced | P2c |
| FR-130 | Convert archive to archive | Any readable input → zip/7z/tar/tar.gz/tar.xz/tar.zst/tar.bz2 by streaming re-pack; metadata kept; encrypted inputs prompt | P2c |
| FR-131 | Encrypted 7z via a separately built 7-Zip helper (gated); no RAR creation, no unRAR | If approved: 7z AES read/write with header encryption, helper without RAR codecs; RAR stays input-only (unencrypted); encrypted RAR unsupported with a pointer to The Unarchiver/Keka. [challenge] The password must reach `7zz` without argv (pty or stdin, never `-p<pw>`), or the gate stays closed (NFR-21) | P3 (owner gate) |

### C.9 App

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-132 | Drop Box: one big temporary box with bulk actions | Collect from many places; Share/AirDrop/Copy/Copy paths/Move to/Copy to/Zip/Convert all/Remove/Trash/Clear; references by default, owned copies only for promise/clipping content; survives relaunch; missing/Trash items flagged; optional auto-clear; storage use shown; shake-to-open opt-in | P2c |
| FR-133 | Notch tray as the Drop Box's home | During a file drag near the notch the tray expands and accepts the drop; hover/click reopens it; works in full screen and on all Spaces; non-notch displays use a top-centre pill; Reduce Motion honoured; 0 permission prompts (TCC diff); never covers menu-bar items beyond the hover (M) | P2c |
| FR-134 | Custom wheels | Hide/show and reorder slices per mode and scope (format > family > default); ≤ 12 shown; per-wheel accent (P2c); per-slice colours with contrast outline, presets, import/export (P3); unknown ids reported, never silently dropped | P2c / P3 |
| FR-135 | History | Window with search/filter, Reveal, Undo (24 h, stamp-checked), Re-run, Clear; retention Off/7/30/90 days, max 500; file mode 0600, excluded from backup; never stores passwords or recognised text | P2c |
| FR-136 | Command-line tool | P2c: `formats`, `info`, `convert` headless with JSON envelope and exit codes 0/1/2/3/130; P3: tool verbs incl. lock/unlock/passwd (password via TTY or `--password-stdin` only; exit 5/6/7), pdf, archive, text, resize, rename, fit, insta, silence, combine, box, history; Homebrew cask | P2c / P3 |

### C.10 On-device AI and transcription

| ID | Requirement | Acceptance criteria | Ph |
|---|---|---|---|
| FR-137 | On-device AI only; optional model packs are verified data | `AICapability` drives visibility and degraded copy; CI lint bans `PrivateCloudComputeLanguageModel`; packs downloaded only on user action, SHA-256 pinned, data-only, removable in Settings. [challenge] OS-managed downloads (Translation languages, Vision `DownloadableAssetsRequest` assets for P4-110) also start only from a user-visible prompt and are named in the privacy copy. Packs are hosted on the project's own release assets | P3 |
| FR-138 | Transcription (reserved) | Defined by `docs/design/16-transcription.md` (not yet written). Reserved interfaces: TRANSCRIBE slot, history kind, CLI verb, segment model (timestamps, language, Roman + Devanagari forms) | P3 (slot) |
| FR-139 | Translate a transcript to English | Translation framework on device; source text is the **Devanagari** form from the transcript; Roman Hinglish as source hi only as a fallback ([challenge]: the Roman path is backed by one sentence in media-ai §6); timestamps preserved; missing language pack → system prompt in a window; original kept beside | P3 |
| FR-140 | Meeting notes with speaker labels | Speakers Auto/2–5+; summary with key points, decisions, action items by speaker; speaker rename/merge rewrites the file; labelled AI-generated; transcript-only fallback with reason; DER ≤ 20 % on AI-S1 set. [challenge] The measured route (sherpa-onnx) ships code and can't be a data-only pack; the CoreML route needs P3-190 numbers before this FR is scheduled | P4 |
| FR-141 | Ask in plain words | Every model plan is validated and shown in a confirm card before running; no destructive or networked operation exists; eval set of 100 EN/Hinglish/Devanagari requests ≥ 90 % correct; keyword fallback when Foundation Models is unavailable | P4 (owner confirm) |

---

## D. Non-functional additions

| ID | Requirement | Target / acceptance | Verified by | Ph |
|---|---|---|---|---|
| NFR-21 | Password hygiene | 0 occurrences of a test password in logs, History, diagnostics, crash data, UserDefaults, argv, env; plaintext only in memory (≤ 128 MB) or 0700 staging, removed on cancel/crash at next launch | Policy test suite (P2-102) | P2a |
| NFR-22 | Vision readiness | First user OCR after warm-up ≤ 3 s; cold path shows a determinate one-time state; Vision runs in one process identity | I-V1/S-V1 spike (extended by P2-190), signposts | P2a |
| NFR-23 | Offline AI and packs | Pair/tool matrix with network blocked passes with packs absent; pack download is Zivlet's only new network use and only on click; OS-managed downloads (Translation, Vision assets) only via a system prompt the user accepts ([challenge]); no code in packs | CI offline job, pack verifier tests | P3 |
| NFR-24 | Size with owner features | [challenge] No re-baseline: NFR-7's ≤ 70 MB target stands. The expected ungated size is ≈ 70.2–71.6 MB (swift-argument-parser is already budgeted), and any measured overage goes to OWN-SIZE-1 (85 MB / 40 MB DMG hard gates unchanged); JPEG XL (+2.5–3.3 MB) and 7zz (+2–3 MB) each need an owner size decision; every feature row lists its delta; model packs never in the bundle | Size gate per release | P2a→P3 |

## E. Success metric additions (PRD §9)

| Metric | Target | Source |
|---|---|---|
| Hindi + English OCR accuracy | 12/12 fixtures ≤ 1 % CER nightly; real-scan median CER ≤ 0.05 | OCR fixture job |
| Locked-file interoperability | 100 % of the lock interop matrix rows (ASCII passwords) open in the target apps | S-PDF-LOCK, LK-M1…LK-M5 records |
| Fit-to-size first-try hit rate | ≥ 95 % of corpus files ≤ target on the first encode | Nightly media job |
| Password leaks | 0 | NFR-21 suite |
