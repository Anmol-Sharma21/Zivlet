# Roadmap cluster: PDF suite

> Imported into the repository on 2026-10-21 from the roadmap drafts; approved by the owner the same day
> (see [00-decisions.md](00-decisions.md), 2026-10-21 section). The product name is Zivlet.
> Prototype folders named `<name>.XXXX/` are local prototypes and are not published.
> The "17-* files" below are now [17-feature-roadmap.md](17-feature-roadmap.md), [17-roadmap-challenge.md](17-roadmap-challenge.md),
> [01b-prd-additions.md](../plan/01b-prd-additions.md) and [05-task-list.md §9](../plan/05-task-list.md).

> [challenge] Adversarial review 2026-10-21 ([17-roadmap-challenge.md](17-roadmap-challenge.md)). The 17-* files are authoritative wherever they differ from this report. Corrections that apply here:
> - **F2 / D-PDF-4 owner-password bypass.** Unlocking with only the user password, when a separate owner password
>   sets restrictions, strips those restrictions (qpdf `--decrypt`). Allow user-password unlock only when the file grants
>   all permissions or user = owner. Other tools keep the input's encryption *as is* (preserve-encryption, which may be
>   RC4). They never re-encrypt with owner = user, and they honour permission bits unless the owner password is given
>   (OWN-PDF-5).
> - **Copy Text on born-digital Hindi PDFs:** PDFKit extraction is in visual order (L1: CER 0.105). Use OCR, or an own
>   logical-order extractor, when the extracted text contains Devanagari.
> - **Signatures:** Keychain with `kSecAttrSynchronizable = false`. No iCloud sync opt-in.
> - **Size:** 3.6 MB is the Homebrew dynamic libqpdf. The shipped build is static native-crypto, so measure it. The
>   OpenSSL "saving" is not a budget saving.
> - `RecognizeDocumentsRequest` has no recognition level; `.accurate` belongs to `RecognizeTextRequest` only
>   (Vision.swiftinterface, macOS 27 SDK).

Date: 2026-10-21. Scope: owner picks for PDF (00-decisions, 2026-10-21): **lock, unlock, compress, sign, merge, split
("unmerge"), remove blank pages, resize pages, make searchable (OCR incl. Hindi)**. Locking non-PDF files is covered in
`17b-lock.md`. This doc follows its shared password sheet and policy (§2) and agrees with its request to move PDF
Protect/Unlock to Phase 2.

Inputs read: `design/00-decisions.md`, `10-tech-strategy.md` (§4.7, §5, §9, §10, §12), `12-document-engine.md`,
`13-image-pdf-engine.md` (§4, §8), `14-app-platform.md`, `plan/01-prd.md`, `02-architecture.md`, `03a/03b`,
`05-task-list.md` (P2-13, P2-39, P2-43, B4-06, B4-07).

Probe machine: Apple M2 Pro, 16 GB, macOS 27.0 (26A428), Swift 6.4 / Xcode SDK `MacOSX27.0.sdk`. Every PROBED number
must be re-run on macOS 26.x (spike S-0). Labels: **PROBED** = measured here by running code. **DOC** = vendor docs or
SDK header. **EST** = estimate. **INFERRED** = reasoned from probes, not proven.

Clean room: all prototypes are new code written for this doc. No code or strings from the reference app or Open-Tangerine were used.

---

## 1. Summary

| # | Feature (wheel slice) | Engine | Licence / size | Effort | Phase |
|---|---|---|---|---|---|
| F1 | **Lock PDF…** (AES-256 password) | qpdf (libqpdf `qpdfjob` JSON) | Apache-2.0, in the qpdf budget | S | **2** (was B4-07) |
| F2 | **Unlock PDF…** (known password) | qpdf | same | S | **2** (was B4-07) |
| F3 | **Compress** (presets, target size, lossless) | Runtime Quartz filter + qpdf structural pass | system + qpdf | M | 2 (already planned, Tool #1) |
| F4 | **Merge PDFs** (multi) | **qpdf first** (was PDFKit first) | qpdf | S | 2 (P2-43, engine changed) |
| F5 | **Split / Unmerge** (each page, every N, ranges) | qpdf | qpdf | S | 2 (P2-39, extended) |
| F6 | **Remove Blank Pages** | Quartz render + own detector, then qpdf page selection | system + own code | M | 3 |
| F7 | **Resize Pages** (A4/Letter/A5…, Fit / Fill / Actual) | v1 Quartz redraw; v2 libqpdf form-XObject placement | system; qpdf | S (v1) / M (v2) | 3 (v1), 4 (v2) |
| F8 | **Make Searchable** (OCR text layer, Hindi + English) | Vision `RecognizeDocumentsRequest` + own invisible text layer | system (+ optional OFL font 0.2–0.4 MB) | M | **3** (was B4-06, Phase 4) |
| F9a | **Sign…** visual (draw / type / image, place on page) | own incremental-update writer (libqpdf helpers) | qpdf | M | 3 |
| F9b | Sign digitally (PAdES B-B, Keychain or USB-token identity) | own CMS (swift-asn1, Apache-2.0) + `SecKeyCreateSignature` | ~0.3–0.6 MB EST | L | 4, behind an owner gate |

The **net new bundle size** is about 0–1 MB. libqpdf + libjpeg-turbo are already budgeted at 3–6 MB in 10 §9 (PROBED:
the Homebrew arm64 `libqpdf.30.4.2.dylib` is **3.6 MB**). Vision, PDFKit and Quartz cost nothing. The only optional add
is a Devanagari text-layer font (§3.8).

### 1.1 Headline evidence (all PROBED on this Mac)
1. **PDFKit is not safe as the write engine for protection, forms or signatures.**
   - Given passwords, it writes **RC4-128 (V2/R3)**, not AES.
   - Given a non-ASCII password, it logs "password cannot be converted to ASCII", writes the file **unencrypted**, and
     `write()` still returns `true`.
   - Merging drops `/AcroForm`, so fields stop working.
   - It wrote a stream with **no `/Length`** after a widget was added.
   - Re-saving a signed PDF **breaks the signature**.
2. **qpdf handles all of these correctly.**
   - AES-256 (R6/AESv3) lock and unlock in about 1 s for an 8 MB file.
   - Merge keeps forms and renames clashing fields (`name` → `name+1`). Merge or split takes 0.03–0.06 s.
3. **Hindi OCR works.** Vision lists `hi-Deva-IN` and `mr-Deva-IN` for both accurate requests. Clean Devanagari reaches
   CER 0.005. A deliberately poor scan gives about 0.08–0.10.
4. **Caveat: the first call is slow.** The first Hindi recognition took **359 s**, and the first auto-detect call
   another **598 s**, because of a one-time on-device model compile. After that it takes 0.1–1.2 s per page.
5. **A naive Devanagari text layer is unsearchable in Preview.**
   - PDFKit ignores the `/ActualText` that CoreGraphics writes, so shaped text extracts in visual order (CER 0.105,
     4/9 searches found).
   - Writing **logical-order glyphs at natural advances** fixes it in PDFKit, poppler and pdfium: CER 0.000, 9/9 found.
6. **PDFKit's built-in `.saveTextFromOCROption` writes no text**, even on re-serialised documents. Spike S-PDF-3: fail.
7. **The blank-page detector classified 15/15 hard cases correctly** (noisy scans, bleed-through, hole punches,
   signature-only page, page-number-only page, white-on-white objects, dark mode). It runs at about 20 ms/page at 72 DPI.
8. **A cryptographic signature written as a true incremental update** verifies as "Signature is Valid" in poppler
   `pdfsig` for both `adbe.pkcs7.detached` and `ETSI.CAdES.detached`. Changing one byte gives "Digest Mismatch".

---

## 2. Cross-cutting decisions

**D-PDF-1 Engine split (this changes 13 §4.2).**
- **qpdf** is the engine for everything structural: merge, split, page selection and deletion, rotate, lock, unlock,
  lossless optimise, repair, linearize, and incremental-update helpers.
- **PDFKit/Quartz** is only for rendering (thumbnails, rasterising, OCR input, blank detection), UI (`PDFView`,
  `PDFThumbnailView`) and lossy Quartz-filter compression.
- Rationale: §1.1 items 1–2. 13 §4.2 had PDFKit first for merge and split, with qpdf as the fallback for forms and
  signatures. With qpdf at 0.03 s and lossless, there is no reason to keep two paths.

**D-PDF-2 Never re-serialise through PDFKit when a file is signed, has AcroForm fields, or is encrypted**, unless the
user accepts a pre-flight warning. The pre-flight runs `qpdf --json`, which reports `acroform.hasacroform`, signature
fields, `/StructTreeRoot`, `/EmbeddedFiles`, `/JavaScript` and encryption, in a few ms.

**D-PDF-3 Verify every output.**
- Run qpdf `--check` (in-process, `qpdfjob`) on every result.
- Re-open with the engine that should be able to read it. For Lock, that means confirming `/Encrypt` is present and
  using AESv3. Never trust `write() == true` (§1.1 item 1).
- Any PDFKit write gets a qpdf rewrite to repair it, for example a missing `/Length`.

**D-PDF-4 Encrypted inputs to any tool.**
- Prompt once with the shared Unlock sheet (17b-lock.md §3.2) and keep the password in memory for that job only.
- [challenge: "same password and AES-256" is only possible when the owner password is known; otherwise preserve the encryption as is] Outputs keep the input's protection, with the same password and AES-256, except for Unlock itself. qpdf preserves
  encryption by default when a password is supplied.
- Restrictions-only PDFs (open without a password, owner password set) can be read and processed, but **restrictions are
  only removed with the owner password** (17b-lock.md §2.1).

**D-PDF-5 Process.** All qpdf, PDFKit and Vision work runs in `ZivletWorker.xpc` (02 §6, P2-04), so a hostile PDF
cannot crash the wheel. Vision must always run in **one** process identity (§3.8 explains the compile cache).

**D-PDF-6 Naming and output.** Use native suffixes (OWN-3): `X Locked.pdf`, `X Unlocked.pdf`, `X Compressed.pdf`,
`<first> Merged.pdf`, `X Pages/X 001.pdf` (split), `X Blank Pages Removed.pdf`, `X A4.pdf`, `X Searchable.pdf`,
`X Signed.pdf`. Results go beside the original, never in place. History and Undo follow 02 §10. History never records
passwords.

**D-PDF-7 Test oracles in CI (not shipped).** Use poppler (`pdftotext`, `pdfsig`, `pdfinfo`) and pdfium (`pypdfium2`)
as independent readers for every fixture. Each one caught something PDFKit hid.

**D-PDF-8 qpdf crypto backend: native, not OpenSSL.** The Homebrew build links OpenSSL 4 (`libcrypto.4.dylib`
**4.8 MB**, PROBED). It **could not decrypt a PDFKit-made RC4 file** ("unable to load openssl legacy provider", exit 2).
Build qpdf with `-DREQUIRE_CRYPTO_NATIVE=ON`, which includes RC4/AES/SHA-2 (DOC). That saves about 4.8 MB and opens
legacy RC4 files. Native crypto is not hardened against side channels (DOC). That does not matter for local files, but
note it in the security doc. Optional v2: a qpdf `QPDFCryptoImpl` provider backed by CommonCrypto.

---

## 3. Features

### 3.1 F1 — Lock PDF (AES-256)

**Behaviour.**
- **Lock…** slice in Tools mode. It is live when at least one dropped PDF has no `/Encrypt`, and it shares the 17b-lock.md
  §3.1 slice logic.
- Sheet: Password + Confirm, strength hint, **Suggest** (`SecCreateSharedWebCredentialPassword`, 17b-lock.md §3.2), and
  optional **Restrictions**: printing (none / low / high), copying, editing.
- The owner password defaults to the user password. If restrictions are on, it defaults to a separate random 24-character
  value that is shown once with a Copy button.
- Copy under the restrictions: "Restrictions are honoured by most apps but are not security."
- **Password characters:** see the risk below. The recommended default is to allow any characters, but warn when a
  password has non-ASCII characters: "Preview on Mac can't open PDFs whose password uses non-English letters."
  **[OWNER OWN-PDF-1]**
- Batch: one password for all files (17b-lock.md §3.3). Output is `X Locked.pdf`.

**Engine.** qpdf `--encrypt <user> <owner> 256` (R6, AESv3), run through `qpdfjob` JSON in the worker, so the password
never appears in argv. Apache-2.0. No size beyond qpdf.

**Evidence (PROBED, `lock.hAdE/`).**
```
qpdf --encrypt --user-password='open sesame' --owner-password='0wn3r!' --bits=256 --print=low --modify=none --extract=n -- in.pdf locked.pdf
  → rc=0, 1.08 s wall for an 8.3 MB / 15-page file; R = 6, AESv3 for streams/strings/files
pdfinfo -upw 'open sesame' locked.pdf → Encrypted: yes (print:yes copy:no change:no addNotes:no algorithm:AES-256)
PDFKit (PDFDocument.unlock) on locked.pdf → true; isLocked before unlock = true
PDFKit write(.userPasswordOption/.ownerPasswordOption) → /V 2 /R 3 /Length 128  = RC4-128 (weak, deprecated in PDF 2.0)
PDFKit write with password "पासवर्ड-2026" → CG log "password cannot be converted to ASCII"; write() == true;
  qpdf --show-encryption → "File is not encrypted"; no /Encrypt in file              ← silent failure
qpdf AES-256 with "पासवर्ड-2026" or "café-2026": poppler opens both; PDFKit unlock fails (NFC and NFD tried)
```

**Risks.**
- *Non-ASCII passwords:* qpdf follows the standard (poppler agrees), but PDFKit, and therefore Preview, Quick Look and
  Spotlight, cannot open these files. Indian users may well type Devanagari passwords. Mitigation: the warning above, and
  a "Check it opens on Mac" verification that re-opens the output with PDFKit and reports the result.
- RC4/AES-128 output is never offered (17b-lock.md §2.3).
- Large files: qpdf streams them (1 s for 8 MB). EST about 10 s for 100 MB. Show progress.

**Effort:** S (qpdf and the sheet already exist by then). **Dependencies:** P2-13 qpdf xcframework (native crypto,
D-PDF-8), 17b-lock.md shared sheet, worker P2-04. **Phase: 2.**

### 3.2 F2 — Unlock PDF (known password)

**Behaviour.**
- **Unlock…** slice, live when the probe sees `/Encrypt`. The sheet has one password field, and a wrong password shakes it
  (17b-lock.md §3.2). Retry silently with NFC/NFD forms.
- [challenge: the user password alone may remove restrictions only when the file grants all permissions or user = owner] Removes the open password and all restrictions only when the right password is given. For restrictions-only files, the
  sheet asks for the **owner** password. Never bypass.
- Also used inline by every other PDF tool (D-PDF-4).
- Error rows: wrong password; `unsupportedEncryption` for certificate (public-key) security handlers or Adobe LiveCycle
  DRM.

**Engine.** qpdf `--password=… --decrypt` (via `qpdfjob`; the CLI equivalent is `--password-file=-`, PROBED with
a Devanagari password over stdin). Do not use PDFKit `unlock`+`write`. It works (PROBED 0.24 s), but it re-serialises
and loses forms and structure.

**Evidence (PROBED).**
```
qpdf --password=wrong --decrypt locked.pdf out.pdf        → "invalid password", exit 2
qpdf --password='open sesame' --decrypt locked.pdf u.pdf  → exit 0, 0.81 s; "File is not encrypted"; pdftotext identical to source
qpdf --check u.pdf → "No syntax or stream encoding errors found"
OpenSSL-backed qpdf on PDFKit RC4 file → "unable to load openssl legacy provider", exit 2   (→ D-PDF-8)
```

**Risks:**
- legacy files (RC4-40, AES-128, R2–R4 passwords in PDFDocEncoding): qpdf's `--password-mode=auto` handles them (DOC).
  Add fixtures from Acrobat, Word, LibreOffice and Preview;
- public-key encrypted PDFs are out of scope.

**Effort:** S. **Dependencies:** as F1. **Phase: 2.**

### 3.3 F3 — Compress PDF

**Behaviour.** The Compress tool (10 §5 #1) with presets **Light / Balanced / Strong** (q 0.85/220 DPI, q 0.7/150,
q 0.5/110; 13 §4.3), **Lossless optimise**, and **fit-to-size presets** from the owner picks: "Under 25 MB (Gmail)",
"Under 10 MB (Discord)", "Under 16 MB / 100 MB (WhatsApp)", plus custom.
- Target size uses the 13 §4.3 2-D search (max 6 passes) and then a qpdf pass.
- Never bigger than the input: otherwise report "Already optimal".
- Pre-flight (D-PDF-2): if forms, signatures, tags or attachments are present, offer "Lossless only (keeps forms and
  signatures)" by default.
- Hover-size preview (an owner pick) uses a one-page trial encode, extrapolated (EST ±25%).

**Engine.** Runtime `QuartzFilter(properties:)` written via PDFKit (system, 0 MB), then qpdf `--object-streams=generate
--recompress-flate --compression-level=9 --remove-unreferenced-resources=yes`. Ghostscript stays rejected (AGPL, 25–40 MB).

**Evidence (PROBED, `pageops.x513/`, 15-page scan corpus 8282 KB).**
```
Quartz filter q0.7 / 150 DPI → 5104 KB in 0.42 s, text layer kept
Quartz filter q0.5 / 110 DPI → 1688 KB in 0.46 s, text layer kept
qpdf lossless (object streams + Flate 9): corpus 8282 → 8086 KB (−2.4 %) 2.6 s; small form PDF 18 → 15 KB (−17 %)
qpdf --optimize-images --jpeg-quality=70: 8282 → 8278 KB (no gain on these grey scans; it never downsamples)
```
(13 §4.3 has the earlier 14.7 MB → 0.86–6.8 MB series.)

**Risks:**
- the Quartz rewrite is a PDFKit write, so the merge evidence implies it loses `/AcroForm` and signatures. The pre-flight
  is mandatory;
- target-size passes on 300-page scans: EST 0.5 s per pass per 15 pages, so a 300-page file is about 10 s per pass. Add
  a cancellable progress bar.

**Effort:** M (mostly already in P2 Compress). **Dependencies:** qpdf, pre-flight JSON, fit-to-size presets (UX
cluster). **Phase: 2.**

### 3.4 F4 — Merge PDFs

**Behaviour.**
- Multi-file drop → **Merge PDFs** (multi-only). Order is the drop or Finder order, and a sheet lets the user reorder by
  dragging thumbnails.
- The first file is the *primary*: its metadata and outline are kept (qpdf rule, DOC). Optional (v2): "Add a bookmark per
  file".
- Encrypted inputs are asked for in turn (D-PDF-4). Output `<first> Merged.pdf`. Mixed images + PDFs → images are
  converted first (Create PDF tool #13).

**Engine.** qpdf `first.pdf --pages first.pdf second.pdf … -- out.pdf` (`--empty` when the first input should not be
primary). PDFKit only for the thumbnails.

**Evidence (PROBED).**
```
qpdf --empty --pages form.pdf corpus.pdf form.pdf -- merged-forms-qpdf.pdf → 0.03 s;
  acroform: hasacroform=True, fields [('name','Sample'), ('name+1','Sample')]   (clash renamed, both live)
PDFKit insert(page.copy()) merge of the same three files → acroform: hasacroform=False, fields []  (dead widgets)
PDFKit merge, 63 pages → 1.01 s (identical image streams de-duplicated: 8350 KB, not ≈33 MB)
```

**Risks:**
- outlines from non-primary files are dropped (DOC). A v2 "bookmark per file" needs libqpdf object code (M);
- tagged structure (`/StructTreeRoot`) from secondary files is not merged (DOC). Warn when a file is tagged.

**Effort:** S. **Dependencies:** P2-13. **Phase: 2** (update P2-43 to qpdf first).

### 3.5 F5 — Split / "Unmerge"

**Behaviour.**
- **Split PDF** stays *instant* by default (every page → folder `X Pages/X 001.pdf`, D-5).
- ⌥-drop or the sheet offers: **Every N pages**, **Ranges** ("1-3, 7, 10-end"; one file per range, or one combined
  "Extract"), **Odd/Even**, and later **By size** ("parts under 25 MB", reusing the fit-to-size presets) and **By
  bookmarks** (top-level outline).
- The range parser accepts `end`/`z`, reverse ranges and spaces, and rejects out-of-range input with a clear message.

**Engine.** qpdf `--split-pages=N` and `--pages in.pdf <ranges> --`. Lossless and streaming.

**Evidence (PROBED).**
```
qpdf --split-pages=4 merged.pdf split-%d.pdf    → 63 pages → 16 files in 0.06 s (names split-01-04.pdf …)
qpdf corpus.pdf --pages . 1-3,7,z-12 -- r.pdf   → 8 pages (reverse range works)
PDFKit split every 5 of the same 63 pages       → 2.56 s (re-serialising)
```

**Risks:**
- qpdf's file-name pattern must be replaced by our own naming. Call it per range via `qpdfjob`;
- by-size splitting needs repeated trial writes (EST M on its own).

**Effort:** S (base), M (by size or bookmarks). **Dependencies:** qpdf. **Phase: 2** (base + N + ranges); by size and
by bookmarks in 4.

### 3.6 F6 — Remove Blank Pages

**Behaviour.**
- **Remove Blank Pages** tool. In the instant wheel path, only pages classed **blank** are removed. The result card
  reads "Removed 3 blank pages · 2 nearly-blank pages kept", with **Review…**.
- Review uses the Organize PDF thumbnail grid (P2): blank pages are pre-ticked, nearly-blank pages are shown with a badge
  and not ticked, and the user can toggle any page. A sensitivity setting offers *Strict / Normal / Aggressive*.
- Never removes a page that has a form field, a link or a signature annotation (checked via qpdf JSON).

**Engine.** Render each page with Quartz (`PDFPage.draw(with:to:)` into an 8-bit grey context at 72–100 DPI), analyse it
with our own detector, then delete pages losslessly with qpdf `--pages . <kept> --`. System + own code, 0 MB.

**Algorithm (prototype `blank.mptA/detect.swift`).**
1. Render at 72 DPI (default) on white. `/Rotate` and annotations are honoured.
2. **Paper colour** = the mode of the 256-bin luminance histogram. This handles grey scan paper (228–239), white and
   dark-mode pages (20).
3. **Ink** = pixels with |lum − paper| > **64** (25 %). This ignores bleed-through, measured at about 27 levels below
   the paper.
4. Take 8-connected components and drop noise:
   - specks with a bounding box under **0.8 mm**;
   - components that touch the page edge and are thin (< 8 % of the side) or cover > 90 % (scanner shadow or border);
   - round components (aspect 0.75–1.33, fill > 0.6) of **4–9 mm** within 20 mm of an edge (hole punches).
5. Classify by kept-ink coverage:
   - **blank** below **0.002 %**;
   - **nearly blank** below **0.3 %**;
   - otherwise **content**;
   - a page that renders blank but has a text layer becomes "nearly blank (hidden text)".

**Evidence (PROBED, generated corpus `corpus.pdf`, 15 labelled pages).**

| Page | Expected | Ink % (72 DPI) | Result |
|---|---|---|---|
| white empty | blank | 0 | blank |
| body text | content | 11.39 | content |
| page number only "- 3 -" | nearly | 0.0058 | nearly (kept) |
| scan, clean grey paper + noise | blank | 0 | blank |
| scan, dirty: 400 specks, edge shadow, 3 hole punches | blank | 0 (233 parts dropped) | blank |
| scan, mirrored bleed-through + specks | blank | 0 (73 dropped) | blank |
| scan with text | content | 10.62 | content |
| thin 0.5 pt grey line chart | content/nearly | 0.139 | nearly (kept) |
| one faint 9 pt grey word | content/nearly | 0.008 | nearly (kept) |
| white rectangle + white text | blank | 0, has text | nearly (hidden text) |
| uniform black page | blank | 0 | blank |
| dark-mode text | content | 12.56 | content |
| **signature only** (blue scribble) | content | 0.056 | nearly (kept) |
| scan with small red "PAID" stamp | content | 0.314 | content |
| scan + invisible OCR layer | content | 10.61 | content |

- **15/15 correct, and no content page was ever classed blank.** The results were identical at 72, 100 and 150 DPI.
- Before the speck rule, 2 of 4 blank scans were misclassed as "nearly". The 0.8 mm bounding-box rule fixed both, which
  shows that threshold is load-bearing.
- Speed, single thread: **20 ms/page at 72 DPI** (63 pages in 1.27 s) and 54 ms/page at 100 DPI. Page removal with qpdf
  `--pages . 2,3,7-10,12-15 --` → 10 pages, instant.

**Risks:**
- real scans are more varied than a generated corpus: JPEG ringing, colour casts, folded corners, punched holes at odd
  sizes, faint pencil. Build a 300-page real fixture set (S-BLANK-1) and tune for **zero false "blank"** first, recall
  second;
- the first page often is a separator sheet. Fine, it is blank;
- the "Aggressive" mode (header or footer only) is not prototyped: EST S.

**Effort:** M (detector S, review UI M, shared with Organize). **Dependencies:** qpdf, Organize grid (P2), worker.
**Phase: 3.**

### 3.7 F7 — Resize Pages

**Behaviour.**
- **Resize Pages** with targets A4, Letter, Legal, A5, A3 and custom (mm/in).
- Modes:
  - **Fit** (default): scale proportionally, centre, white margins;
  - **Fill**: scale to cover and crop the overflow;
  - **Actual size**: change the paper only, centred, may clip.
- **Auto-orientation:** landscape pages get a landscape target. On by default.
- Mixed-size documents are normalised to one size, which is the main use case: scans plus Letter pages → A4 for printing
  or upload portals.

**Engine.**
- **v1:** a new Quartz PDF context and `PDFPage.draw(with: .cropBox, to:)` under a fit/fill transform. Vectors, text and
  images are reused without re-encoding.
- **v2:** a lossless libqpdf path: `QPDFPageObjectHelper::getFormXObjectForPage` + `placeFormXObject` (DOC), plus
  transforming annotation `/Rect`s, so links and fields stay live.
- PDFKit `setBounds` is only an "Actual size" shortcut that keeps annotations.

**Evidence (PROBED, `pageops.x513/`).**
```
fixture: A4 portrait (link + text field) ; A4 landscape ; A4 with /Rotate 90
resize Letter fit → 612x792 ; 792x612 ; 792x612 (rotation normalised to r0), text extractable, 0.007 s
resize A5 fit / A5 fill / Letter actual → correct boxes, auto-orient applied
form value "Sample" drawn into page content (flattened); Link and Widget annotations are gone
PDFKit setBounds (rebox to Letter) → annotations kept, but landscape page clipped ("e page"), no scaling
15-page scan corpus fit → Letter: 1.06 s, 8282 KB → 8282 KB (images reused, not re-encoded)
```

**Risks:**
- v1 flattens forms and drops links and the outline. Pre-flight warns: "Links and form fields will be flattened."
  Use v2 when the pre-flight finds them;
- Fill crops content. The sheet shows a live preview.

**Effort:** S (v1), M (v2). **Dependencies:** none (v1); qpdf C++ shim (v2, the same shim as the 13 §4.3 recompressor).
**Phase: 3 (v1), 4 (v2).**

### 3.8 F8 — Make Searchable (OCR text layer, Hindi + English)

**Behaviour.**
- **Make Searchable** tool. For each page: skip it if it already has a usable text layer (10 §4.7 test: ≥ 20 printable
  characters, < 5 % U+FFFD). Otherwise render at **300 DPI**, OCR it, and add an **invisible, selectable** text layer on
  top of the **unchanged original page**. Vectors stay vectors and nothing is rasterised.
- Languages: automatic, with **Hindi + English** as the defaults, plus Marathi and the other 31 Vision languages in
  Settings. Romanised Hinglish is read by the English model.
- Output `X Searchable.pdf`. The result card reads "12 pages made searchable · 3 already had text". The pages then work
  in Preview Find, Spotlight and copy-paste.
- Shares one **OCR core service** with "Copy text from image", which the owner rates VERY IMPORTANT, and with PDF → txt
  (10 §4.7), so warm-up, language settings and fixtures are built once.

**Engine.**
- Vision `RecognizeDocumentsRequest` (macOS 26). `RecognizeTextRequest` `.accurate` has the same language list. The
  `.fast` path is Latin-only (6 languages), so it is unusable for Hindi.
- Text layer: drawn by us with CoreGraphics in **invisible mode, as logical-order glyphs at natural advances, scaled to
  each line box** (prototype `ocrpdf.eZaF/probe.swift`).
- Font: the system **Kohinoor Devanagari** (OS/2 fsType 0 = installable, PROBED), or bundle **Noto Sans Devanagari**
  (OFL-1.1, EST 0.2–0.4 MB) so we do not depend on the Apple system-font EULA **[OWNER OWN-PDF-4]**.
- Do **not** use PDFKit `.saveTextFromOCROption` (it writes nothing).

**Evidence (PROBED, `ocr-hindi.G1sV/`, `searchable.bM8g/`, `ocrpdf.eZaF/`, `pdfkitocr.OwP9/`, `anecache.5eRA/`).**

*Language support:*
```
RecognizeTextRequest .accurate (33): … hi-Deva-IN mr-Deva-IN ; .fast (6): en fr it de es pt only
RecognizeDocumentsRequest (33): same list incl. hi-Deva-IN, mr-Deva-IN ; VNRecognizeTextRequest: "hi-IN", "mr-IN"
```
*Accuracy* (5 known lines: 3 Hindi, 1 Hindi + digits + ₹ + "GST", 1 Roman Hinglish; CER on Unicode scalars):

| Rendering | `hi` | `hi+en` | auto |
|---|---|---|---|
| Kohinoor Devanagari 34 pt (clean) | 0.005 | 0.005 | 0.005 |
| Devanagari Sangam MN / ITF Devanagari (clean) | 0.005 | 0.005 | 0.005 |
| 14 pt small | 0.014 | 0.014 | 0.010 |
| "bad scan": 24 pt, 1.5° skew, 2.5× down-up sampling (≈70 DPI) | 0.096 | 0.096 | 0.079 |

- Clean output was exact except for "—" read as "-".
- Bad-scan errors look like real OCR errors: र→ग, ध→प, सहित→साहेत; the Hinglish line comes out as "mecting … nai" in
  `hi` mode and is perfect in auto mode.
- Both request types gave identical text.

*First-call model compile (this macOS build):*
```
first RecognizeTextRequest(hi) in a new executable: 358.6 s   (process idle; ANECompilerService busy)
first automaticallyDetectsLanguage call:           597.6 s
afterwards: 0.1–0.4 s per image; whole 30-run probe re-run: 13.3 s
rebuilt binary, same name "probe", new cdHash → fast (1.15 s)   | new binary named "searchable" → 734.5 s again
end-to-end prototype built as "probe" → fast (OCR 0.61–1.06 s/page)
```
INFERRED: the compiled-model cache is keyed by process identity (name or bundle id), not by code hash. So an app update
probably keeps it, but **the app and the worker would each pay it**.

*Text-layer encoding* (same 6 Hindi lines, invisible text over a scan; PDFKit CER / searches found of 9):

| Variant | PDFKit (Preview, Spotlight) | poppler | pdfium (Chrome) |
|---|---|---|---|
| L1 shaped `CTLineDraw` (CG writes `/ActualText` per cluster) | 0.105 / 4 ("िवशाल", "माचर्") | 0.000 / 8 | ≈0 / 9 |
| L2 L1 + explicit `CGPDFContextBeginTag(.span, ActualText)` | 0.105 / 4 (no change) | 0.000 / 8 | ≈0 / 9 |
| L3 logical glyphs, uniform spacing | 0.000 / 1 (fake word breaks) | 0.035 / 2 | ≈0 / 2 |
| **L5 logical glyphs at natural advances** | **0.000 / 9** | **0.000 / 9** | **≈0 / 9** |

(pdfium's 0.026 in the raw score is the CLI's "# Page 1" header.)

*End to end* (`input.pdf`: Hindi scan page + English scan page + born-digital page):
```
page 1: OCR 6 lines in 1.06 s ; page 2: OCR 12 lines in 0.61 s ; page 3: has text layer, skipped ; total 1.98 s
PDFKit findString: विशाल 1, दस्तावेज़ 1, हस्ताक्षर 1, मार्च 1, क्षमा 1, त्रिपाठी 1, agreement 12, quarterly 38
poppler page-1 CER vs truth 0.000 (whitespace-insensitive); file 4858 KB → 4870 KB (+11 KB font subsets)
PDFKit .saveTextFromOCROption (unmodified, modified, fresh-copy doc): 0 characters written
```

**Risks.**
1. **First-use compile of 6–10+ minutes** (if macOS 26 behaves like this build). Mitigations:
   - pin all Vision work to `ZivletWorker`;
   - after onboarding, warm up at background QoS with a 64 px image for `hi+en` and auto;
   - show "Preparing text recognition (one time)…" with a cancel button;
   - re-measure on 26.x (S-V1, which must now include Hindi and auto-detect).
2. Word spacing: poppler sometimes merges words ("इसदस्तावेज़को") because the text is placed per line. Fix by placing
   per word with `RecognizedTextObservation.boundingBox(for:)` (S). This also makes selection highlights match.
3. Rotated or skewed pages: Vision returns quadrilaterals. Use them as the text matrix (S). Not prototyped.
4. Complex layouts or tables: reading order comes from Vision paragraphs. Acceptable for search.
5. Very large scans: about 1 s/page, so 300 pages ≈ 5 min. Use a cancellable progress bar, and parallelise across pages
   (Vision is thread-safe per request, DOC).

**Effort:** M. **Dependencies:** OCR core service (shared with Copy Text from Image), warm-up infra, worker, optional
font. **Phase: 3**, the same phase as Copy Text from Image (moved from B4-06 / Phase 4).

### 3.9 F9 — Sign

**Decision.** Ship **visual signatures first** (F9a), which is what "sign them" means for most users (the Preview-style
"put my signature on it"). Put **cryptographic PAdES** (F9b) behind an owner gate in Phase 4 **[OWNER OWN-PDF-2]**.

**F9a behaviour.**
- **Sign…** opens a placement window on page 1 (or the last page).
- Choose a saved signature, or create one by:
  - **drawing** (trackpad or mouse), or
  - **typing** in a script font (system fonts such as Snell Roundhand or Bradley Hand), or
  - **importing an image**, with the background removed by threshold or by Vision foreground mask (shared with the
    background-removal pick).
- Drag and resize to place. Optional date and initials-on-every-page.
- Saved signatures live in the **Keychain** (as data, never synced [challenge: opt-in iCloud sync removed]) and nowhere else.
- Output is written as an **incremental update**: the original bytes stay intact, a new content stream (image or vector
  XObject) is appended to the page, and existing digital signatures are kept valid where DocMDP allows.
- Copy: "This is a visual signature. It doesn't prove who signed."

**F9b behaviour (Phase 4, gated).**
- **Sign digitally…** uses an identity from the Keychain or a USB token through CryptoTokenKit. Indian Class-3 DSC tokens
  used for GST/MCA filing appear this way if their driver is installed.
- Writes PAdES **B-B** (`ETSI.CAdES.detached`, signing-certificate-v2, SHA-256), with a visible appearance placed as in
  F9a.
- B-T (timestamp) needs a network TSA. That conflicts with offline-by-default, so it would be opt-in only.
- No self-signed "identity creation" in v1. Such signatures show "unknown issuer" everywhere, so they mostly confuse.

**Engine.**
- F9a: our own incremental-update writer. libqpdf can produce the appended objects, or we write a small writer for the
  update section (prototype below). No PDFKit write at all.
- F9b: the same writer, plus our own CMS SignedData builder. **CMSEncoder (Security.framework) cannot add the
  ESS signing-certificate-v2 attribute** (SDK `CMSEncoder.h`: only S/MIME caps, signing time and Apple attributes), so it
  can produce `adbe.pkcs7.detached` but not strict PAdES. Use swift-asn1 (Apache-2.0, EST 0.3–0.6 MB) for DER and
  `SecKeyCreateSignature` for the signature, which works with Keychain and token keys.

**Evidence (PROBED, `sign.pg8l/`).** `sign.py` (stdlib only) appends a signature dict with a /ByteRange
placeholder, a `/FT /Sig` widget, an appearance XObject, the updated page `/Annots` and `/AcroForm /SigFlags 3`, and a
new xref section. The CMS comes from `openssl cms -sign -binary -md sha256 [-cades]` with a throwaway self-signed P-256
certificate (no keychain change).
```
pdfsig signed-adbe.pdf  → Signature Type: adbe.pkcs7.detached ; Total document signed ; Signature is Valid
pdfsig signed-pades.pdf → Signature Type: ETSI.CAdES.detached ; Total document signed ; Signature is Valid
                          Certificate Validation: Certificate issuer is unknown   (expected, self-signed)
cmp: original file is a byte-exact prefix of the signed file (true incremental update)
PDFKit opens it: annotations [Link, Widget/Tx, Widget/Sig] (existing ones preserved after the indirect-/Annots fix)
1 byte changed in a signed range (/MediaBox 595→596) → "Digest Mismatch"
PDFKit re-save of the signed file → "Illegal values in ByteRange array", "Not total document signed", cert info lost
```
- One bug was found during the prototype: a page with an *indirect* `/Annots` array first got a duplicate key and lost
  its annotations. The product writer must resolve indirect objects (use libqpdf object helpers, not regex).
- The prototype CMS also includes a signing-time attribute, which PAdES baseline forbids. The Swift builder must leave
  it out and use `/M`.

**Risks:**
- F9a: placement UI quality is what matters most to users. Run usability tests;
- signing an already-signed PDF: the appended content must be allowed by the existing signature's DocMDP level, so check
  `/Perms` first and refuse when it is "no changes";
- F9b: PKI corner cases (chains, revocation, LTV), token drivers, and legal meaning under the Indian IT Act or eIDAS.
  Keep the wording neutral ("digitally signed with your certificate").

**Effort:** F9a M (writer S, capture and placement UI M); F9b L. **Dependencies:** qpdf, Keychain wrapper, placement UI
(shared with Annotate), background removal (optional). **Phase: F9a 3, F9b 4 (gate).**

---

## 4. Proposed task-list changes (05-task-list.md)

| ID | Change | Phase |
|---|---|---|
| P2-13 | qpdf xcframework **with `REQUIRE_CRYPTO_NATIVE=ON`**, no OpenSSL. The smoke test also decrypts an RC4 fixture and an AES-256 fixture | 2 |
| P2-13a (new) | `PDFPreflight` (qpdf `--json`): encryption, AcroForm, signatures, tags, attachments, JS, page count. Used by every PDF tool | 2 |
| P2-13b (new) | `PDFVerify`: qpdf `--check` + re-open with the expected reader; rewrite PDFKit outputs through qpdf | 2 |
| P2-39 | Split: add Every N, Ranges, Odd/Even (qpdf) | 2 |
| P2-43 | Merge: qpdf first (primary input), PDFKit only for thumbnails | 2 |
| B4-07 → P2-44 (new) | Lock / Unlock PDF (qpdf AES-256), shared 17b-lock.md sheet, non-ASCII warning, verify `/Encrypt` | 2 |
| P3-new-1 | OCR core service: Vision in the worker, warm-up, language settings; shared with Copy Text from Image | 3 |
| B4-06 → P3-new-2 | Make Searchable (L5 text layer, per-word boxes, skip pages with text) | 3 |
| P3-new-3 | Remove Blank Pages (detector + review in the Organize grid) | 3 |
| P3-new-4 | Resize Pages v1 (Quartz redraw, Fit / Fill / Actual, auto-orient) | 3 |
| P3-new-5 | Visual signature: capture (draw / type / image), Keychain store, placement, incremental-update writer | 3 |
| P4-new | Resize v2 lossless (form XObjects); split by size and by bookmarks; merge "bookmark per file" | 4 |
| P4-gate | PAdES B-B digital signing with Keychain or token identities **[OWNER]** | 4 |

CLI (P3-31, owner pick): `zivlet pdf lock|unlock|merge|split|compress|remove-blank|resize|ocr|sign-visual`. Passwords
come from the TTY or `--password-stdin` only (17b-lock.md §3.6). Exit codes: 5 = wrong password, 6 = unsupported
encryption, 7 = verification failed.

---

## 5. Open spikes

| Spike | Question | Pass bar |
|---|---|---|
| S-V1 (extended) | Vision first-call compile on **macOS 26.x** for `hi`, `hi+en` and auto; does the cache survive an app update and a reboot? Does it differ between the app and an XPC service? | First OCR ≤ 3 s after background warm-up; warm-up ≤ 15 min worst case |
| S-OCR-HI | Real Hindi scans (government forms, typed letters, school certificates, 150–300 DPI JPEG phone photos) | Median CER ≤ 0.05 at 300 DPI; Hindi words found in Preview |
| S-BLANK-1 | 300-page real scan set (duplex scanners, phone scans) | 0 content pages classed blank; ≥ 95 % of blank pages caught |
| S-PDF-2 (extended) | Exact list of what the Quartz-filter and redraw paths drop (forms, signatures, tags, links, outline, attachments, layers) | Documented list drives the pre-flight copy |
| S-PDF-LOCK | Interop matrix: our AES-256 output opened by Preview, Acrobat Reader, Chrome, Edge, Android/iOS viewers; legacy fixtures from Word, LibreOffice and Preview | All open with ASCII passwords; non-ASCII results documented |
| S-SIGN-1 (Phase 4) | Swift CMS builder → PAdES B-B accepted by Acrobat (with a test CA) and by EU DSS validation | "Signature is valid" (chain trusted under the test CA) |

---

## 6. Corrections to existing docs (to fold in when the PDF track starts)

- **13 §4.1/§4.2:** PDFKit "password open/save" must not be used for saving: it writes RC4-128 and silently skips
  encryption for non-ASCII passwords. Make merge and split qpdf first. PDFKit merge drops `/AcroForm`, and PDFKit wrote
  a stream with no `/Length`.
- **13 §4.2 OCR row / S-PDF-3:** answered. `.saveTextFromOCROption` writes nothing. Draw our own layer, using the L5
  encoding, not shaped text.
- **13 §8.1:** the 57.8 s first-call note is the English figure. Hindi and auto-detect cost 359 s and 598 s on this
  build, per process identity. Update the warm-up design to cover the Hindi and auto models and to pin one process.
- **10 §12:** move "Make PDF Searchable" and "PDF Protect, Unlock" out of Phase 4 (into 3 and 2). Add Remove Blank Pages,
  Resize Pages and Visual Sign to Phase 3.
- **10 §9:** qpdf row: measured dylib 3.6 MB. Avoid OpenSSL (−4.8 MB) with native crypto.

## 7. Owner decisions requested

| ID | Question | Recommendation |
|---|---|---|
| OWN-PDF-1 | Allow non-ASCII PDF passwords even though Preview can't open them? | Allow, with a clear warning and a "check it opens on Mac" result |
| OWN-PDF-2 | Digital (certificate) signatures in 1.x? | No. Visual signatures in Phase 3; PAdES B-B as a Phase 4 gate |
| OWN-PDF-3 | Blank-page default | Remove only "blank"; keep "nearly blank" with a review list |
| OWN-PDF-4 | Text-layer font | Bundle Noto Sans Devanagari (OFL, ≤ 0.4 MB) instead of embedding Apple system fonts |

## 8. Prototype index (local prototypes, not published)

| Folder | Contents |
|---|---|
| `ocr-hindi.G1sV/` | `probe.swift`: language lists, Hindi/English OCR CER matrix, rendered test images, `run1.txt`/`run2.txt` |
| `anecache.5eRA/` | rebuilt-binary cache test (same name, new cdHash) |
| `searchable.bM8g/` | `searchable.swift` (PDFKit OCR option vs own layer), `textlayer.swift` + `score.py` (L1–L6 encodings × 3 extractors), `fstype.swift` |
| `pdfkitocr.OwP9/` | `.saveTextFromOCROption` on modified and fresh documents |
| `ocrpdf.eZaF/` | end-to-end Make Searchable (`probe.swift`, `input.pdf`, `searchable.pdf`) |
| `blank.mptA/` | `gen.swift` (labelled corpus), `detect.swift` (detector), `corpus.pdf`, `labels.txt` |
| `lock.hAdE/` | qpdf AES-256 lock/unlock, PDFKit RC4 and non-ASCII silent-failure probes, Unicode password matrix |
| `pageops.x513/` | `pageops.swift` (resize, rebox, merge, split, Quartz compress), `mkform.py` (real AcroForm fixture), `mergekit.swift`, qpdf outputs |
| `sign.pg8l/` | `sign.py` (incremental-update signer), `resave.swift`, signed, tampered and re-saved PDFs, `sigthumb-1.png` |
| `qpdf-bottle.vaak/` | Homebrew qpdf 12.4.2 + openssl@4 bottles (sha256-verified, unpacked only, not installed) used as the test qpdf |

Run qpdf from the bottle like this: `DYLD_FALLBACK_LIBRARY_PATH=<bottle>/qpdf/12.4.2_1/lib:<bottle>/openssl@4/4.0.3/lib:/opt/homebrew/opt/jpeg-turbo/lib`.
Use the shell's `time`, not `/usr/bin/time`, which strips `DYLD_*` under SIP.
