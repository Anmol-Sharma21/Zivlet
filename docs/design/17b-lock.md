# Roadmap cluster: Lock / Unlock for non-PDF files (Office, ZIP, any file, iWork)

> Imported into the repository on 2026-10-21 from the roadmap drafts; approved by the owner the same day
> (see [00-decisions.md](00-decisions.md), 2026-10-21 section). The product name is Zivlet.
> Prototype folders named `<name>.XXXX/` are local prototypes and are not published.
> The "17-* files" below are now [17-feature-roadmap.md](17-feature-roadmap.md), [17-roadmap-challenge.md](17-roadmap-challenge.md),
> [01b-prd-additions.md](../plan/01b-prd-additions.md) and [05-task-list.md §9](../plan/05-task-list.md).

> [challenge] Adversarial review 2026-10-21 ([17-roadmap-challenge.md](17-roadmap-challenge.md)). The 17-* files are authoritative wherever they differ from this report. Corrections that apply here:
> - Manual QA **M-1…M-6 is renamed LK-M1…LK-M6**, because 10 §13 already uses M-1…M-6 for media spikes.
> - §3.1: Lock and Unlock become **one slot** with a refining label. **Change Password is a mode of the Unlock sheet,
>   not a slice**: a slice that appears only for encrypted drops changes the frame-1 set (FR-18). "k of n" goes in the
>   badge, because the 82 × 22 pt label frame can't hold it.
> - §3.1 probe: the header read must not run before the drop on iCloud dataless files (it would download them) or in
>   TCC-protected folders that aren't granted yet (it would prompt mid-drag). Keep the provisional label there.
> - §3.2 Suggest → Copy: write to the pasteboard with `.currentHostOnly` and the concealed/transient markers.
> - "Byte-identical round trips" means the *plaintext*. Ciphertext differs by design (random salts).
> - Pages/Numbers/Keynote opening our encrypted OOXML is statically inferred, so it is informational, not a release gate.
>   Archive Utility AES support is inferred too (LK-M4 is a beta gate).

Date: 2026-10-21. Status: proposal for the owner. Scope: the owner's "VERY IMPORTANT" pick (owner picks, 00-decisions 2026-10-21):
"Lock/unlock OTHER files too: Word, Excel, PowerPoint, ZIP; CSV/others via encrypted ZIP. Local only. Remove or add
protection with a password the user knows." PDF lock and unlock belong to the PDF cluster (qpdf, B4-07). This file only
shares the password sheet and the rules with it (§3, §11). Transcription is designed separately and is not touched here.

Inputs read: design/00-decisions, 10-tech-strategy (§4.12 archives, §4.14 extras, §9 size, §10 licences, §12 roadmap),
12-document-engine (OOXML hardening), 13-image-pdf-engine (§6 archives, libarchive build, qpdf protect), 14-app-platform
(secure input); plan/01-prd (NG5, FR-63 tool window), 02-architecture (§4 modules, `passwordRequired` error), 03b (§9
hardening: today a CFB `EncryptionInfo` is *refused*), 05-task-list (P2-19, P2-41, B4-07, B4-12, P3-31).

Principles applied: offline only, no telemetry, nothing uploaded. Passwords are never stored (no Keychain by default),
never logged and never passed on argv. Bundle impact is below 0.3 MB (§12). Clean room: the Office crypto prototype was
written from Microsoft's public [MS-OFFCRYPTO] and [MS-CFB] specifications. msoffcrypto-tool (MIT) was used **only as a
black-box test oracle** through its CLI and Python API. Its source was not read or ported. Nothing comes from the reference app
or Open-Tangerine.

Evidence caveat: prototypes ran on this Mac (macOS 27.0 build 26A428, arm64, Xcode at `/Applications/Xcode.app`) while
other agents were building. `uptime` showed load averages of 30–94, so timings are upper bounds. **GUI apps were not
driven.** The owner was using the desktop, and a first Apple Events probe opened Microsoft Word, which then sat on a
modal dialog. I quit it (SIGTERM, no user documents) and stopped there. Checks that need Word, Pages, Numbers or Archive
Utility on screen are listed as manual QA in §14.

---

## 1. Summary

| # | Feature | What the user gets | Engine (licence, size) | Proven on this Mac | Effort | Phase |
|---|---|---|---|---|---|---|
| F1 | **Lock / Unlock Word, Excel, PowerPoint** (.docx/.xlsx/.pptx and macro/template variants) | Password-protect a document so Office, Pages, Numbers, Keynote and LibreOffice ask for the password. Remove the password (you type it). Change the password. | **Own Swift code**: CFB reader/writer + ECMA-376 Agile Encryption (AES-256-CBC, SHA-512, 100,000 spins) on CommonCrypto. GPL-3.0-or-later, ≈ 150 KB `__text`, 0 new deps | **Yes.** Byte-identical round trips both ways against the reference tool. HMAC tamper check works. 38 MB file: lock 318 ms, unlock 232 ms | **M** | **P2** |
| F2 | **Unlock old .doc/.xls/.ppt** (RC4, RC4 CryptoAPI, XOR) | Remove the password from 1997–2004-era files. **No locking** into these broken ciphers. | Own Swift code on the F1 CFB reader + record-level decrypt | No fixture could be made without driving Word. Support matrix and Numbers' own readers confirmed statically | **L** | **P3** |
| F3 | **Lock / Unlock / change password of ZIP** | Make an AES-256 ZIP. Remove a ZIP password. Change it in one pass. Optional "compatible (weak)" ZipCrypto. | **libarchive 3.8.10** (BSD-2), already planned for P2-19. AES via CommonCrypto, no OpenSSL. **+0 MB** beyond the planned 1.5–2 MB | **Yes.** Built 3.8.10 static with the doc's flags. AES-256 wrap, unlock, change password, wrong-password handling and ZipCrypto all verified with pyzipper, system bsdtar and unzip. Two defects found (§6.4) | **M** | **P2** |
| F4 | **Lock any file** (CSV, TXT, images, folders, mixed drops) | Drop anything, type a password, get `… Locked.zip` (AES-256). Recipients open it with any modern unzip tool, no Zivlet needed. Optional **Mac-only encrypted disk image** that also hides file names. | F3 path. DMG via system `hdiutil` (0 MB) | **Yes** (AES ZIP, encrypted DMG round trip, wrong-password failure) | **S** (+S for DMG) | **P2** (DMG: **P3**) |
| F5 | **Lock / Unlock Pages, Numbers, Keynote** | Same sheet. Done by the iWork app itself through Apple Events, only if the app is installed and the user opts in (O-17). | System Apple Events. iWork's own scripting dictionary has `set password` / `remove password`. 0 MB | Dictionary confirmed in all three apps. Not run (GUI) | **S–M** | **P4** |
| F6 | **Unlock-then-convert** | Converting a locked Office file or ZIP asks for the password instead of failing. The decrypted copy lives only in the job's staging folder. | F1/F3 inside the probe stage | Follows from F1/F3 | **S** | **P2** (docs: P3) |
| F7 | **Edit restrictions** (Excel sheet/workbook protection, Word "restrict editing", "password to modify") | Remove only after the user types the matching password, which is verified against the stored hash. No blind stripping. | Own Swift (SHA-512 spin hash verify + XML edit) | Not prototyped | **S–M** | **P4** (owner decision) |
| — | **Shared**: password sheet, batch, naming, History, CLI, policy | One sheet for PDF, Office, ZIP, any file. No storing, no recovery. | SwiftUI `SecureField`, Security `SecCreateSharedWebCredentialPassword` (verified) | §3 | **M** | **P2** |

**Recommendation:** pull F1, F3, F4 and the shared sheet into **Phase 2**, next to libarchive (P2-19) and qpdf (P2-13),
and ask the PDF cluster to move PDF Protect/Unlock (B4-07) to P2 as well, so one "Lock" and one "Unlock" slice cover
every family at beta. Move AES-ZIP creation out of B4-12 (P4) into P2.

---

## 2. Policy decisions (explicit)

### 2.1 No password cracking, recovery or bypass

**Decision: Zivlet never recovers, guesses or bypasses a password it was not given.** That means:
- no brute-force, dictionary or "try a list of passwords" feature, and no GPU or hashcat hand-off;
- no known-plaintext attack on ZipCrypto (practical with public tools, and deliberately not offered);
- no stripping of Excel sheet protection, Word editing restrictions or PDF owner-password permissions without the
  matching password (F7 verifies the password first);
- no IRM/DRM removal (`DRMEncryptedDataSpace`, Azure RMS). That stays under NG5.

Why:
1. **Scope.** Zivlet is a converter. The owner's requirement is "a password the user knows".
2. **Ethics and law.** A one-drop "unlock anything" tool is mostly useful against other people's files. Bypassing access
   controls can breach computer-misuse law (for example India's IT Act 2000 s.43/66 or the US CFAA) and, for DRM,
   anti-circumvention law (DMCA §1201). A free, notarized GPL app should not carry that risk.
3. **Product.** Spin counts (100,000 × SHA-512) make guessing slow anyway, so a "recovery" feature would mostly fail.
   That is a support burden with no benefit.

User copy (Unlock sheet footer and wrong-password row): "Zivlet can't recover forgotten passwords. Try the password
again, or ask the person who sent the file."

### 2.2 Never store passwords by default
- No Keychain writes, ever by default, and no "remember" checkbox in 1.x. iWork's `set password` takes a `saving in
  keychain` flag; Zivlet always passes `false`.
- Optional later (owner call): "Use this password for the rest of this drop" applies within one batch and lives in
  memory only.
- Passwords never go into History, logs, crash reports, `UserDefaults`, argv or environment variables. Prototypes read
  them from env vars only as a spike shortcut. The app sends them inside the XPC message. The CLI reads them from the
  TTY or stdin (§3.6).
- Buffers: keep passwords as `[UInt8]` and zero them with `memset_s` after key derivation (best effort, since Swift
  `String` copies cannot be fully controlled). Derived keys are zeroed in `defer`.

### 2.3 No weak encryption by default
- Office: write **Agile AES-256 / SHA-512 / 100,000 spins** only. Never write Standard (AES-128, SHA-1) or RC4.
- ZIP: **AES-256 (WinZip AE-1/AE-2)** by default. ZipCrypto only behind a "Compatible with very old unzip tools (weak)"
  toggle with a warning. ZipCrypto passwords are limited to ASCII because legacy tools disagree on the code page.
- Legacy .doc/.xls/.ppt: unlock only. To protect one, users convert to .docx/.xlsx/.pptx first (P3 conversion) and then
  lock it.

---

## 3. Shared UX (all lock/unlock families, including PDF)

### 3.1 On the wheel
- Tools mode gets two slices for every family that supports them: **Lock…** (padlock) and **Unlock…** (open padlock).
  Both are "window tools" (PRD FR-63): drop, then a compact password sheet opens at the wheel location.
- The probe (`Engine.plan`, ≤ 30 ms header read) decides which slice is live. If **every** dropped file is already
  encrypted, the wheel shows **Unlock…** and **Change Password…**. If none is, it shows **Lock…**. A mixed drop shows
  both, with a "k of n" badge (OWN-2).
- Encryption signatures used by the probe: CFB magic + `EncryptionInfo` stream (OOXML); CFB + FIB `fEncrypted` bit in
  `WordDocument` (.doc); a `FILEPASS` record after BOF in `Workbook` (.xls); `CryptSession10Container` (.ppt); ZIP
  general-purpose flag bit 0 / method 99 (ZIP); `AEA1` magic; `encrcdsa` magic (DMG); `/Encrypt` (PDF, PDF cluster);
  the iWork `password protected` property (F5 only).

### 3.2 Password sheet
- **Lock:** Password + Confirm (both `SecureField`, an eye button reveals them), a strength hint (length plus character
  classes, computed locally), a **Suggest** button using `SecCreateSharedWebCredentialPassword()` (verified here:
  Apple-style `xxx-xxx-xxx-xxx`, 15 characters, about 71 bits) with a Copy button, and per-family notes. ZIP shows "File
  names stay visible. Use Disk Image (Mac only) to hide them." A big Office file shows "Recipients need Office 2010+,
  Pages/Numbers/Keynote, or LibreOffice."
- **Unlock:** one Password field. A wrong password shakes the sheet and keeps it open. There is no attempt limit (it is
  a local file) and no artificial delay.
- **Change Password:** Current + New + Confirm. One job: decrypt into memory, then encrypt.
- Unicode: use exactly what the user typed. If unlock fails, retry silently with the NFC and NFD forms (adds ≤ 2 × the
  spin time, about 30–80 ms each). This covers passwords typed with different input methods (e.g. Devanagari or
  accented Latin).
- Accessibility: labelled fields, VoiceOver announces "Wrong password", fully keyboard driven (Return = Lock).
  `SecureField` turns on macOS Secure Input. Zivlet's trigger polls only modifier flags, which still work
  (14-app-platform §2).

### 3.3 Batch
- One sheet per drop. "Use the same password for all *n* files" is on by default.
- Unlock batch: try the typed password on every file. Files that fail come back in a second sheet that lists them.
  Successes are not redone.
- Multi-file **Lock as ZIP** offers "One archive" (default, `n Files Locked.zip`) or "One archive per file".

### 3.4 Output, naming, Undo, History
- Never modify in place. Output goes beside the original: `Report Locked.docx`, `Report Unlocked.xlsx`,
  `data Locked.zip`, `Photos Locked.dmg`. It follows OWN-3 native suffixes and the §8.5 collision rule.
- Optional **Replace original** (off by default): the original moves to Trash, so Undo can restore it. The copy says
  "Moving to Trash is not secure deletion." On APFS SSDs no app can promise secure erase, and Zivlet must not claim it.
- History records the operation, family, input and output paths, and "password set/removed". It never records the
  password or a hash of it. Undo moves the output to Trash (02 §10).
- Unlocked plaintext exists only in the job's staging directory (0700, inside the volume's replacement directory), and
  only until atomic publish. Inputs ≤ 128 MB decrypt in memory, so no plaintext temp file is written.

### 3.5 Errors (02 §8.4 `passwordRequired` gains siblings)
`wrongPassword` → "That password didn't work."; `drmProtected` → "This file uses rights management (IRM) and can't be
unlocked."; `unsupportedEncryption` → "This file uses certificate-based or very old encryption Zivlet can't open.";
`integrityFailed` → "The file is damaged or was changed after it was locked."; `notEncrypted` → Unlock hidden, so it
should not occur.

### 3.6 CLI (`zivlet`, P3-31)
`zivlet lock <files…> [--as zip|dmg] [--zipcrypto]`, `zivlet unlock <files…>`, `zivlet passwd <file>`. The password
comes from the TTY with no echo (`readpassphrase(3)`), or from `--password-stdin` for scripts. There is **no
`--password` flag**, because argv shows up in `ps`. Exit code 5 = wrong password, 6 = unsupported encryption. JSON
output never contains the password.

---

## 4. F1 — Word, Excel, PowerPoint (OOXML) lock / unlock

### 4.1 Behaviour
- Inputs: .docx .docm .dotx .xlsx .xlsm .xltx .xlsb (the binary workbook is also a ZIP package and is encrypted the same
  way) .pptx .pptm .potx, plus Visio/Project OOXML if dropped. Output keeps the extension. The container becomes a CFB
  ("CDFV2 Encrypted") file, which is how Office stores every password-to-open document.
- Unlock reads **Agile** (Office 2010+, any hash or AES key size) and **Standard** (Office 2007, AES-128/SHA-1, read
  only). Certificate key encryptors and IRM DataSpaces are refused with `unsupportedEncryption` / `drmProtected`.
- Lock writes Agile: AES-256-CBC, SHA-512, 100,000 spins, random 16-byte salts, with the `dataIntegrity` HMAC and the
  full `\x06DataSpaces` storage. That matches what Office writes.
- Change password = unlock + lock in memory.

### 4.2 Engine choice
| Option | Licence | Size | Verdict |
|---|---|---|---|
| **Own Swift implementation from [MS-OFFCRYPTO]/[MS-CFB]** (CommonCrypto, Security) | GPL-3.0-or-later (ours). MS-OFFCRYPTO and MS-CFB are covered by the Microsoft Open Specification Promise | ≈ 150 KB `__text` for CFB + Agile (measured, includes the spike CLI) | **Chosen.** The spec is small (spike: 508 lines including CLI). No new vendor build. Runs inside `ZivletWorker` like other engines |
| Port msoffcrypto-tool (MIT → GPL is allowed with attribution) | MIT | similar | Not needed. A port would carry Python-shaped code and needs an attribution trail. Keep it as a dev-only **test oracle** (never shipped) |
| LibreOffice headless "save with password" | MPL-2.0 | 805 MB optional download | Not for lock/unlock (huge, slow, re-saves and changes the document). Fine as a fidelity fallback for *conversions* only |
| Apple Events to Word/Excel/PowerPoint | proprietary apps | 0 | Requires Office plus Automation permission, and drives a GUI. Rejected |
| Apache POI / .NET OpenMcdf | Apache-2.0 / MPL | JVM/.NET | Wrong runtime |

Placement: new pure-ish module **`EngineOfficeCrypto`** (CFB + crypto, no UI, fuzzable), used by `EngineDocs` (F6) and a
`LockTool` in the Tools catalog. It depends only on Foundation, CommonCrypto and Security.

### 4.3 Evidence (prototype `lock-swift.1LSg/`, run on this Mac)
Plaintext fixtures came from python-docx/openpyxl/python-pptx: 200-paragraph docx with Devanagari, 2,000-row xlsx,
5-slide pptx, and a 38 MB docx with 12 incompressible images. Password `Tr1cky pässwörd` (non-ASCII). The password is
passed by env var in the spike only.

```text
$ msoffcrypto-tool -e -p "$PW" plain.docx ref.docx      # reference oracle
$ inspect ref.docx → CFB v3 (512 B sectors): \x06DataSpaces/{Version 76, DataSpaceMap 112,
  DataSpaceInfo/StrongEncryptionDataSpace 64, TransformInfo/StrongEncryptionTransform/\x06Primary 200},
  EncryptedPackage 37992, EncryptionInfo 1441 (version 4.4, flags 0x40, XML: AES-256/SHA512/100000)

== 1. Swift unlocks reference-encrypted files
unlock ok in 83 ms   docx byte-identical to original
unlock ok in 60 ms   xlsx byte-identical to original
unlock ok in 42 ms   pptx byte-identical to original
== 2. wrong password → "error: wrong password" rc=1  (verifier check, before any package bytes are decrypted)
== 3. Swift locks; reference tool decrypts
docx/xlsx/pptx: reference tool decrypts Swift output byte-identically
reference tool, wrong password on Swift output → InvalidKeyError
== 4. Swift lock → Swift unlock: identical
== 5. msoffcrypto-tool --test: sw-locked.docx rc=0 (encrypted); sw-unlocked.docx "not encrypted"
== 6. \x06DataSpaces streams of Swift output vs reference: Version, DataSpaceMap,
      StrongEncryptionDataSpace, \x06Primary → all SAME (sha1)
== 7. flip one byte inside EncryptedPackage → "integrity (HMAC) check failed" rc=1
== 8. olefile opens Swift output (4096 B sectors, 6 streams); msoffcrypto verify_integrity=True;
      python-docx 201 paragraphs, openpyxl 2000 rows, python-pptx 5 slides
== 9. 38 MB docx: reference output is CFB v3 with 4 DIFAT sectors →
      Swift unlock 232 ms, byte-identical (exercises the DIFAT path);
      Swift lock 318 ms → reference decrypts byte-identically (reference tool itself: 1.17 s encrypt)
```
Static evidence that Apple apps read this format: `strings` on the Numbers binary shows `OCCEncryptionInfoReader`,
`EncryptedPackage`, `StrongEncryptionDataSpace`, `keyEncryptor/password`, `SHA512`, `spinCount`, plus `OCCRC4Cryptor`
and `OCCCryptoAPICryptoKey`. Pages and Keynote binaries contain the same markers. Pages/Numbers/Keynote export options
also carry `password` (`TSKExportOptionsPassphrase`), so iWork writes encrypted Office files too. The real-app open
test is manual QA M-1/M-2 (§14).

### 4.4 Risks
| Risk | Severity | Mitigation |
|---|---|---|
| Word or Excel rejects a structurally valid container the oracles accept (e.g. 4096-byte sectors, red-black colouring, missing CLSID) | High until M-1 passes | Writer follows MS-CFB strictly: sorted, valid red-black tree, DataSpaces identical to reference. M-1/M-2 on Word for Mac plus Excel/PowerPoint and Numbers/Pages/Keynote before beta. Fallback: write CFB v3 (512 B) for files < 6 MB |
| Overhead: v4 sectors pad small files (43.5 KB reference vs 61 KB ours for a 38 KB docx) | Low | Use v3 for small files (one size switch in the writer) |
| Hostile CFB input (loops, huge sizes, sector out of range) | High (untrusted input) | Reader already bounds-checks chains, DIFAT hops and sizes. Add a libFuzzer target (03b §9) and the 128 MB input cap. XML parsed with entities disabled and a 64 KB cap |
| Office variants not covered (Standard-encryption files from Office 2007, SHA-1/AES-128 Agile from 2010) | Medium | Read paths are small. Fixtures from Apache POI test-data (Apache-2.0) and Office-made files (M-3) |
| Swift type-checker blow-up: the spike took ≈ 6 min to compile under load (generic `digest` switch with closures) | Low | Split per-hash functions. Enable `-warn-long-expression-type-checking=200` in CI |
| Password Unicode form mismatch with Windows-made files | Low | NFC/NFD retry (§3.2) |
| 03b §9 currently *refuses* CFB `EncryptionInfo` in EngineDocs | — | Change the rule: an encrypted OOXML becomes `passwordRequired` and goes through F6. IRM stays refused |

### 4.5 Effort, dependencies, phase
**M** (about 1.5–2 weeks): productionise CFB + Agile (done in spike), add Standard read, v3/v4 writer switch, fuzz
target, fixture corpus, worker integration, Lock/Unlock catalog entries. Depends on P2-01 (worker), the shared sheet
(L-01) and the ZIP sniffing already in EngineDocs. **Phase 2.**

---

## 5. F2 — Legacy .doc / .xls / .ppt unlock

### 5.1 Behaviour
Unlock only. The output is the same legacy format with the encryption removed (FIB flag cleared and `FILEPASS` record
removed, streams decrypted), so it opens anywhere without a prompt. Lock is not offered for legacy files. The sheet says
"Convert to .docx first to protect this file" and offers that conversion (needs the P3 legacy readers or LibreOffice).

### 5.2 Engine
Own Swift on the F1 CFB reader (the writer needs in-place stream rewrite support). Algorithms from [MS-OFFCRYPTO] §2.3.6
(RC4, 40-bit MD5), §2.3.5 (RC4 CryptoAPI, SHA-1, 40–128-bit) and §2.3.7 (XOR obfuscation), plus the per-format rules in
[MS-DOC] (the `WordDocument` stream after the FIB header and the table streams), [MS-XLS] (per-record decryption that
leaves BOF/FILEPASS/INTERFACEHDR and some record headers in clear) and [MS-PPT] (`EncryptedSummary`, persist-object
decryption). The reference tool marks xls and ppt as "experimental"/"partial", which shows how fiddly this is.

### 5.3 Evidence
- Reference support matrix (installed msoffcrypto-tool 6.0.0 metadata): RC4 CryptoAPI for doc/xls/ppt, RC4 for doc/xls,
  XOR for xls. Word/Excel 95 encryption is not supported.
- Numbers ships `OCCRC4Cryptor`/`OCCCryptoAPICryptoKey`, so Apple apps open these files, which makes them a usable
  oracle.
- No fixture was generated: making one needs Word "Save as .doc with password" (GUI). That is manual task M-3.

### 5.4 Risks, effort, phase
Risks: xls record-level edge cases (continue records, stream offsets), ppt partial support, small user base. Sequence
**.doc → .xls → .ppt**, and ship each only when its fixture corpus passes. **L. Phase 3** (after F1). Depends on F1's
CFB reader, a CFB writer rewrite mode and fixtures M-3.

---

## 6. F3 — ZIP lock / unlock / change password

### 6.1 Behaviour
- **Lock ZIP** (unencrypted ZIP in): stream re-pack into AES-256 ZIP. Entries, folders, timestamps and permissions are
  kept. Symlinks are kept as entries, never followed.
- **Unlock ZIP**: stream re-pack into a plain ZIP. Per-entry passwords: the typed password is tried for every entry, and
  entries that fail are listed.
- **Change Password**: one pass with separate read and write passphrases.
- Extract of an encrypted ZIP (P2-41) uses the same sheet.
- Compression: **store** entries that are already compressed (docx/xlsx/pptx, jpg/heic/png/webp, mp4/mov/m4a, zip/7z,
  pdf), detected by UTI and a 64 KB compressibility sample. Otherwise use Deflate level 6 (§6.4 shows why).

### 6.2 Engine choice
| Option | Licence | Verdict |
|---|---|---|
| **libarchive 3.8.10** (planned P2-19; `archive_read_add_passphrase`, `archive_write_set_passphrase`, `zip:encryption=aes256`/`zipcrypt`) | BSD-2-Clause | **Chosen.** Already in the bundle budget (1.5–2 MB). On Apple it uses CommonCrypto for AES-CTR, HMAC-SHA1 and PBKDF2 (`ARCHIVE_CRYPTOR_USE_Apple_CommonCrypto`), so no OpenSSL is needed |
| minizip-ng | Zlib | Good AES support, but a second ZIP stack with the same job. Rejected |
| System `/usr/bin/bsdtar`/`zip`/`ditto` | Apple | bsdtar 3.7.4 cannot take a read passphrase in create mode, `zip` has no AES, `ditto` reports "Unknown compression type". Not usable |
| 7-Zip `7zz` (gated, 13 §6.5) | LGPL-2.1+ / BSD | Only for **7z AES** read/write with header encryption (hides names). Defer with the existing gate |

### 6.3 Evidence (prototype `lock-libarchive.N85h/`, `lock-zip.8FxE/`)
```text
# libarchive v3.8.10 (GitHub release, published 2026-10-14), static, --without-openssl/nettle/mbedtls/xml2
configure + make: OK; libarchive.a 1.17 MB (zlib/bz2 from SDK, no lzma/zstd/lz4 in this spike)
archive_cryptor_private.h: __APPLE__ → ARCHIVE_CRYPTOR_USE_Apple_CommonCrypto
zipcrypt (C, 112 lines, links libarchive.a): 380 KB binary, 250 KB __text

== wrap CSV + docx into AES-256 zip (non-ASCII password)
  report.csv: method=99 AE-1 vendor=AE strength=AES-256 method=8     pyzipper read 16407 bytes OK
  plain.docx: method=99 AE-1 strength=AES-256                         pyzipper read 37973 bytes OK
== unlock a pyzipper-made AES zip → "No errors detected" (Info-ZIP unzip -t)
== wrong password → "error: dir/ünïcode name.txt: Incorrect passphrase" rc=1
== encrypted input, no password → "…is encrypted; password required" rc=1
== change password in one pass (READ_PW old, WRITE_PW new) → pyzipper reads both entries with the new password
== ZipCrypto mode → system unzip 6.0 extracts with -P, cmp identical
== system bsdtar 3.7.4 (the libarchive Archive Utility links) extracts our AES zip, cmp identical
== system tools on AES zips: unzip 6.0 "unsupported compression method 99"; ditto "Unknown compression type"
== libarchive writes AE-1 (with CRC) for normal entries, AE-2 for tiny ones (12-byte note.txt), matching WinZip guidance
```
Archive Utility (macOS 27) links `/usr/lib/libarchive.2.dylib` and has a ZIP password sheet (`_zipPasswordSheet`,
"no password provided for encrypted PKZip archive"). A Mac recipient double-clicking an AES ZIP should therefore get a
password prompt. This is **INFERRED**: the GUI was not run (manual M-4).

### 6.4 Defects found (must be fixed before shipping)
1. **C locale breaks UTF-8 names.** Under the default C locale, `archive_read_next_header` returned ARCHIVE_WARN
   "Pathname cannot be converted from UTF-8 to current locale" and the re-pack aborted. Fix (verified): the worker calls
   `setlocale(LC_CTYPE, "UTF-8")` once at start, and the read loop accepts ARCHIVE_WARN.
2. **libarchive on Apple writes NFD names.** A pyzipper entry `dir/ünïcode name.txt` (NFC) came out as
   `u\xcc\x88ni\xcc\x88code` after re-pack. A direct wrap of `café.txt` also came out as `cafe\xcc\x81.txt`. Neither
   `archive_entry_set_pathname_utf8` with CFStringNormalize(NFC) nor `zip:hdrcharset=UTF-8` changed this. The cause is
   the deliberate `__APPLE__` NFD normalisation in `archive_string.c` (≈ lines 1269–1294). Windows and Linux recipients
   then see decomposed names. Search, sort and duplicates can break, and some tools render a stray accent. Fix: a
   ~10-line vendor patch (or an upstream option) that skips NFD when writing ZIP/7z headers, plus a test that ZIP names
   are NFC. **Effort S**, but it is a release blocker for F3/F4.
3. **Deflate on incompressible data is slow.** Wrapping the 38 MB docx took 9.93 s. Breakdown: deflate alone 7.22 s,
   AES alone (bsdtar `compression=store` + AES) 1.44 s (≈ 26 MB/s), AES on 40 MB of zeros 0.42 s, pyzipper store+AES
   1.97 s. Fix: the store heuristic in §6.1, plus progress reporting. AES throughput is acceptable (1 GB ≈ 40 s).

### 6.5 Risks
| Risk | Mitigation |
|---|---|
| Recipient tools: Windows Explorer has historically opened only ZipCrypto (newer Windows 11 builds use libarchive for some formats: **unverified**). 7-Zip, WinRAR, PeaZip, Bandizip, Keka, The Unarchiver and Archive Utility (inferred) read AES | Sheet note: "Windows users may need 7-Zip". ZipCrypto compatibility toggle with a weak-crypto warning. Manual M-5 on a Windows 11 VM if available |
| File names, sizes and dates are visible in any ZIP | Stated in the sheet. Offer Disk Image (F4) for hiding names. 7z with header encryption only if the 7zz gate opens |
| Password encoding for AES-ZIP is UTF-8 (WinZip/7-Zip). Non-ASCII ZipCrypto passwords are not interoperable | UTF-8 always. ZipCrypto passwords restricted to ASCII |
| ZipCrypto false "right password" (1-byte check) shows up later as a CRC error | Map a ZipCrypto CRC failure to `wrongPassword` |
| Bombs or hostile entries during unlock re-pack | Same limits as extraction (13 §6.3: ratio, entry count, total size). Re-pack never touches disk paths |

### 6.6 Effort, dependencies, phase
**M** on top of P2-19 (libarchive vendor build and EngineArchive): passphrase plumbing, change password, store
heuristic, NFC patch, locale init, fixture corpus (WinZip/7-Zip/pyzipper-made AE-1/AE-2, ZipCrypto, mixed per-entry
passwords). **Phase 2.**

---

## 7. F4 — Lock any file (CSV, TXT, images, folders)

### 7.1 Behaviour
Any family not covered by a native lock (CSV, TXT, JSON, images, audio, video, folders, mixed drops) offers **Lock…**,
which produces an AES-256 ZIP (F3 writer). An "As" picker in the sheet chooses:
- **ZIP (AES-256)**: default; any OS can open it with a modern unzip tool;
- **Disk Image (Mac only)**: encrypted DMG that hides names, opened by double-click and password on any Mac;
- for Office or PDF files, the picker also shows **Keep format** (native lock, F1 or the PDF cluster), which is the
  default for those families.
Zivlet's own container format: **rejected**. The recipient would need Zivlet, which defeats sharing.

### 7.2 Options evaluated (all on this Mac)
| Format | Result | Verdict |
|---|---|---|
| AES-256 ZIP (libarchive) | Works (§6.3). Cross-platform with common tools | **Default** |
| Encrypted DMG: `printf '%s' "$PW" \| hdiutil create -encryption AES-256 -stdinpass -srcfolder … -fs APFS -format UDZO` | 11.31 s for a 2-file folder (APFS create + convert, under load), 147 KB. `hdiutil attach -stdinpass` with the right password mounts and contents compare equal. Wrong password: "attach failed - Authentication error" rc=1. Note: `hdiutil attach -mountpoint` prints a deprecation warning pointing to `diskutil image attach` | **Option, Phase 3** (Mac-only, slow, but hides names). Password goes via stdin, never argv. Verification step mounts with `-nobrowse -readonly` |
| Apple Encrypted Archive (`aa` + `aea`, profile 5 scrypt) | Round trip OK (`AEA1` magic), wrong password → "Failed to unlock container". **Rejects passwords shorter than 20 characters** (16–19 rejected, 20 accepted), so even Apple's own 15-character generated passwords fail | **Rejected** for user passwords. macOS-only, unfamiliar to recipients |
| 7z AES with header encryption | Needs `7zz` (gated) | Defer to the 7zz gate |
| Own format | — | Rejected (needs Zivlet to open) |

### 7.3 Effort, dependencies, phase
ZIP path **S** after F3, **Phase 2**. DMG option **S** (system tool runner with stdin password, staging folder, cleanup
on cancel, 1 GB+ inputs sized with `-size` headroom), **Phase 3**.

---

## 8. F5 — Pages, Numbers, Keynote passwords

### 8.1 Feasibility
- The iWork encrypted package format is undocumented. A native implementation would mean reverse-engineering Apple's
  key derivation and package layout. **Rejected** (legal grey area, fragile, a clean-room violation risk).
- **Feasible through the apps themselves**: Pages.sdef, Numbers.sdef and Keynote.sdef (macOS 27 copies) each define
  `set password "<pw>" to <document> [hint "…"] [saving in keychain <bool>]` and `remove password "<current>" from
  <document>`, plus a read-only `password protected` property. Export options also take `password`/`password hint`, so
  iWork can produce password-protected docx/xlsx/pptx or PDF itself.
- Flow: `open` the file (hidden where the app allows) → `set password` / `remove password` → `save` → `close`, all from
  the worker's AppleScript runner, with Automation permission requested once (O-17 opt-in, off by default).
- Unknown (not run): whether scripting `open` on an already-protected document shows the app's GUI password prompt
  instead of failing. If it does, Unlock for iWork needs a visible step ("Pages will ask for the password").
  Manual M-6.

### 8.2 Risks, effort, phase
Risks: GUI windows flash on screen, Automation TCC prompt, app-version drift, slow first launch (several seconds).
**S–M. Phase 4**, with the other Apple Events features. Show the slices only when the app is installed and the opt-in
is on.

---

## 9. F6 — Unlock-then-convert
Any route whose input probe reports `passwordRequired` (encrypted OOXML, ZIP, PDF) shows the Unlock sheet before the job
runs. EngineOfficeCrypto or EngineArchive decrypts into memory or staging, and then the normal route runs. The output of
a conversion is **not** encrypted unless the user picks Lock afterwards. The sheet says "The converted file won't have a
password." **S** per family. **Phase 2** for ZIP (extract and re-pack routes) and **Phase 3** for documents. This
replaces 03b §9's blanket refusal of CFB `EncryptionInfo`.

## 10. F7 — Edit restrictions (owner decision)
Office "protection" that is not encryption: `<sheetProtection>`/`<workbookProtection>` (SHA-512 + salt + spinCount in
XML), Word `<w:documentProtection>` (restrict editing), and `<fileSharing … reservationPassword>` ("password to
modify"). These do not hide data; they are honour-system flags. Zivlet should **only remove one after verifying the
typed password against the stored hash** (same KDF family as Agile), in line with §2.1. **S–M. Phase 4**, if the owner
wants it at all. It was not prototyped.

## 11. Relationship to PDF lock/unlock (PDF cluster)
qpdf `--encrypt user owner 256` / `--decrypt` stays the PDF engine (13 §4). This cluster provides the shared pieces the
PDF cluster should reuse: the sheet (§3.2), batch rules (§3.3), naming (§3.4), errors (§3.5), CLI verbs (§3.6) and the
§2 policy. In particular, an owner-password-only PDF is not "unlocked" without the owner password.

---

## 12. Size and licence summary
| Component | Licence | Bundle impact | Notes |
|---|---|---|---|
| `EngineOfficeCrypto` (CFB + Agile/Standard + legacy RC4/XOR later) | GPL-3.0-or-later (ours) | ≈ 0.15–0.3 MB | From public MS specs under the Open Specification Promise |
| libarchive 3.8.10 AES-ZIP | BSD-2-Clause | 0 (already budgeted in §9 at 1.5–2 MB) | + NFC vendor patch (keep in `Vendor/patches/`, note in SPDX) |
| CommonCrypto, Security, hdiutil, Apple Events | system | 0 | |
| msoffcrypto-tool, pyzipper, python-docx/openpyxl/python-pptx | MIT / MIT / MIT | **0, dev/test only** | Test oracles in a CI venv. Never shipped |
| **Total** | | **< 0.3 MB** | Size budget unaffected (≤ 70 MB) |

## 13. Risk register (cluster)
| ID | Risk | Likelihood / impact | Mitigation | Owner step |
|---|---|---|---|---|
| LK-R1 | Office apps reject our CFB container | Low / High | DataSpaces byte-equal to reference, MS-CFB-valid tree. M-1/M-2 before beta. v3 fallback | Run M-1/M-2 |
| LK-R2 | libarchive NFD names in ZIPs | Certain / Medium | Vendor patch + NFC test (§6.4) | — |
| LK-R3 | Windows Explorer can't open AES-ZIP | Medium / Medium | Sheet note, ZipCrypto toggle, M-5 | Decide default copy |
| LK-R4 | Users expect "recover forgotten password" | Medium / Low | Clear copy (§2.1), FAQ entry | Approve policy |
| LK-R5 | Plaintext left behind (temp files, Replace original) | Low / High | In-memory ≤ 128 MB, staging 0700, cleanup on cancel/crash at next launch, Trash wording | — |
| LK-R6 | Password exposure via logs/argv/History/crash reports | Low / High | §2.2 rules, a unit test that scans log output for the test password, a CLI with no `--password` | — |
| LK-R7 | Hostile encrypted inputs (CFB loops, zip bombs) | Medium / High | Bounds checks, fuzzing, 13 §6.3 limits, worker isolation | — |
| LK-R8 | iWork scripting needs GUI or changes per app version | Medium / Low | Phase 4, opt-in, capability probe | — |

## 14. Manual QA the owner (or a QA pass) must run: not done here, to avoid driving GUI apps on a busy desktop
| ID | Check | Files (in `lock-ooxml.JO56/`, password `Tr1cky pässwörd`) | Pass |
|---|---|---|---|
| M-1 | Open `sw-locked.docx`, `sw-locked.xlsx`, `sw-locked.pptx` in Word/Excel/PowerPoint for Mac | Swift-locked | Password prompt; content intact; saving with the password still prompts on reopen |
| M-2 | Same three files in Pages, Numbers, Keynote (and LibreOffice if installed later) | Swift-locked | Password prompt; opens |
| M-3 | In Word: Save As `.doc` with a password, and Excel `.xls` with a password; Office-made `.docx` with a password | new fixtures | Become the F1 Office-made and F2 legacy fixtures |
| M-4 | Double-click `lock-zip.8FxE/wrapped.zip` in Finder (Archive Utility) | AES-256 ZIP | Password sheet, extracts |
| M-5 | Same ZIP on Windows 11 Explorer and 7-Zip | AES-256 ZIP | Record which ones work |
| M-6 | Script `set password` / `remove password` on a scratch Pages document; reopen a protected one by script | scratch doc | Note whether a GUI prompt appears |

## 15. Task list additions (for 05-task-list)
| ID | Task | Module | Deps | Effort | Phase |
|---|---|---|---|---|---|
| L-01 | Password sheet (Lock / Unlock / Change), Suggest, batch rules, NFC/NFD retry, error copy | ZivletUI, ZivletCore (ToolSpec) | P2-01 | M | P2 |
| L-02 | `EngineOfficeCrypto`: CFB reader/writer (v3+v4), Agile read/write, Standard read, fuzz target | new module | P2-01 | M | P2 |
| L-03 | Office Lock/Unlock/Change tools + probe signatures + catalog entries | EngineOfficeCrypto, ZivletCore | L-01, L-02 | S | P2 |
| L-04 | ZIP passphrase plumbing (read/write split), change password, store heuristic, locale init | EngineArchive | P2-19 | M | P2 |
| L-05 | libarchive NFC-on-write vendor patch + test | Vendor | P2-19 | S | P2 |
| L-06 | Lock any file → AES ZIP (single/multi/folder) | EngineArchive | L-04 | S | P2 |
| L-07 | Unlock-then-convert hook (`passwordRequired` → sheet) for ZIP, then docs | ZivletRuntime, EngineDocs | L-01, L-02, L-04 | S | P2/P3 |
| L-08 | Policy + privacy tests (no password in logs/History/argv; plaintext cleanup) | tests | L-01 | S | P2 |
| L-09 | Encrypted DMG option (hdiutil runner, stdin password, verify mount) | EngineArchive | L-06 | S | P3 |
| L-10 | Legacy unlock .doc → .xls → .ppt | EngineOfficeCrypto | L-02, M-3 | L | P3 |
| L-11 | CLI verbs `lock`/`unlock`/`passwd` (readpassphrase, `--password-stdin`) | zivlet-cli | P3-31, L-03, L-04 | S | P3 |
| L-12 | iWork lock/unlock via Apple Events (opt-in) | ZivletRuntime (AppleScript runner) | O-17 | S–M | P4 |
| L-13 | Edit-restriction removal with verified password (owner decision) | EngineOfficeCrypto | L-02 | S–M | P4 |
| (move) | B4-12 AES-ZIP creation → P2 (L-04/L-06). Ask the PDF cluster to move B4-07 PDF Protect/Unlock → P2 | — | — | — | — |

## 16. Prototype index (local prototypes, not published)
- `lock-swift.1LSg/` (local prototype, not published):
  `CFB.swift` (254 lines), `Agile.swift` (174), `main.swift` (80), built `officelock` (272 KB, `__text` 147 KB), and
  `gen.swift` (password generator check).
- `lock-libarchive.N85h/` (local prototype, not published):
  libarchive 3.8.10 source + static build (`prefix/`), `zipcrypt.c` (wrap/repack with split passphrases, UTF-8 locale,
  NFC attempt), configure/make logs.
- `lock-ooxml.JO56/` (local prototype, not published):
  plaintext fixtures, reference-locked (`ref.*`), Swift-locked (`sw-locked.*`), round-trip outputs, 38 MB `big.docx`.
- `lock-zip.8FxE/` (local prototype, not published):
  AES/ZipCrypto ZIPs (bsdtar, pyzipper, zipcrypt), encrypted DMG, AEA files.
- `lock-venv.KGCX/` (local prototype, not published):
  dev-only venv (msoffcrypto-tool 6.0.0, pyzipper 0.4.0, python-docx 1.2.0, openpyxl 3.1.5, python-pptx) and the
  checker scripts `inspect.py`, `check.py`, `zipcheck.py`, `mk_samples.py`, `big.py`.
