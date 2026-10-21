# 18 — Archives: every format, both directions

Status: design recommendation (engine track: archives). Date: 2026-10-21.
Scope: create (compress), extract (decompress), archive → archive conversion, peek inside, passwords and multi-part sets for every archive and single-stream compression format Zivlet can legally and safely handle.
Constraints (from `00-decisions.md`, 10 §2, §8.9, §9, §10): direct download, notarized Developer ID, **not sandboxed**, **macOS 26+**, arm64, GPL-3.0-or-later, every third-party parser runs in `ZivletWorker.xpc` or a signed helper, unRAR banned, size target ≤ 70 MB (NFR-24).
Owner request (2026-10-21): "every archive format possible, both directions; compress to any format, decompress any format, convert any → any; peek inside; passwords; multi-part."
Supersedes: 13 §6.4–6.5 (creation, encrypted 7z), 10 §4.14 archive row, and the archive rows P2-147/148/149, P3-105, P3-113 in the 17 roadmap task additions, now [05-task-list.md §9](../plan/05-task-list.md) (mapped in §9).

Evidence labels: **OBSERVED** = run on this machine (macOS 27.0 26A428, M2 Pro); **DOC** = vendor documentation, SDK header or licence text; **EST** = estimate a spike must confirm; **INFERRED** = reasoning, not legal advice.
Evidence references: **[A§n]** = probe A report (libarchive 3.8.10 built from the GPG-verified tarball); **[B§n]** = probe B report (7-Zip 26.04 built from source); **[C§n]** = probe C report (Apple Archive, DMG, RAR licence); **[X-n]** = experiments run for this document (§11). The probe reports and experiment folders are local prototypes and are not published. Every OBSERVED result was taken on macOS **27**; spike AR-S3 re-runs the 26-sensitive ones on a 26.x VM.

> [challenge] Adversarial review done 2026-10-21, details in [18-archives-challenge.md](18-archives-challenge.md). New evidence label **[CH-n]** = a check re-run by the challenge (local prototype folder, not published; 7zz rebuilt from a **pruned** source tree with no `CPP/7zip/Compress/Rar*`, minos 26.0). Corrections are marked `[challenge]` in place. The biggest ones: ZIP name decoding (§6.2, X-2 used a flawed fixture), split tar.\* sets don't open through `archive_read_open_filenames` (§1.2, AR-06), ISO via `makehybrid` loses symlink targets and nothing we ship reads Apple's UDF (§1.2), DMG peek needs a `-t` chain plus `-sns-` (§6.1), and the 7-Zip source we publish must be pruned of unRAR files (§7).

---

## 0. TL;DR

| Question | Answer |
|---|---|
| Primary engine | **libarchive 3.8.10** (LA), static, in the worker. It reads the 11 container formats and 10 stream filters we enable, writes ZIP (incl. AES-256), 7z, tar + 10 filters, cpio, XAR and single-stream files, and re-packs any → any by streaming with no temp extraction [A§1, §8]. |
| Second engine | **7-Zip `7zz` 26.04, built by us with `DISABLE_RAR_COMPRESS=1`** (7Z), a separate signed helper: 7z creation (2–5× faster, ~5 % smaller), **7z AES-256 with hidden names**, split volumes, Deflate64, UDF, WIM, ARJ, RPM, DMG/disk-image listing [B§0, §6]. The sibling challenge's blocker (password on argv, C11) is **resolved**: passwords go through stdin (OBSERVED, X-1; re-run on the pruned build, CH-1). Recommend opening gate OWN-ARC-2 in Phase 2C (+2.6 MB). [challenge] Two conditions: the published 7-Zip source must be **pruned** of `CPP/7zip/Compress/Rar*` (the full upstream tarball is unRAR source, which 10 §10.2 bans; the pruned tree builds the same 2,908,160-byte binary, CH-2), and notarization of a bundle containing the helper has **not** been tested (no Developer ID certificate here, AR-S1). |
| Apple engines (0 MB) | **AppleArchive** framework for `.aar` / `.aea` (Mac-only, full fidelity) [C§1]; **Compression** framework for `.br` (OBSERVED, X-4); **`diskutil image` / `hdiutil`** for DMG create and encrypted-DMG extract, `hdiutil makehybrid` for ISO create [C§2]. |
| RAR | **Read only** (LA: RAR4/RAR5, solid, multi-volume, SFX). **Never written**, in any form (OWN-ARC-1). Encrypted RAR stays unsupported: no unRAR code, no full 7-Zip build [C§4, B§2.2]. |
| Formats | **18 container targets** (9 on the wheel by default), **10 single-stream compressors**, **32 convertible sources**, ~45 readable extensions incl. "All formats" (WIM, ARJ, MSI, disk images) behind explicit actions. |
| Catalog | The 9 parity pairs stay as they are. Extras: **135 default-visible pairs + 414 advanced pairs** in `Catalog.extras` (§8), so the 275 parity count test is untouched. |
| Wheel | Actions gets **ZIP, 7Z, ARCHIVE…** (and LOCK); archive Tools are **EXTRACT, PEEK, LOCK · UNLOCK, CONVERT…, TEST**; the Convert wheel for any archive shows ≤ 9 targets. "More formats" live in the ARCHIVE…/CONVERT… sheets and Settings, never as a 13th slice (§2). |
| Security | The 03b §9 archive row grows into 16 controls: explicit reader allow-list, LA secure flags plus our own pre-check, symlink/hardlink containment, no device/FIFO nodes, case-collision handling, CP437/UTF-8 name rules, ratio prompt, 7zz confinement, DMG mount guard rails (§6). |
| Size | +0 MB without 7zz (LA measured 1.28–1.41 MB stripped against a 1.5–2 MB budget); **+2.6 MB installed / +1.2 MB DMG** with 7zz [A§11, B§1]. |

---

## 1. Format matrix

### 1.1 Legend

Engines: **LA** libarchive in the worker · **LA+S** LA output byte-split by EngineArchive into `.001…` (opens in 7-Zip and LA [A§7.4]) · **7Z** `7zz` helper · **AF** Apple frameworks (AppleArchive, Compression) in the worker · **HD** `diskutil image` (fallback `hdiutil`) child process · **—** none.
Convert-to: **W** default wheel target · **A** advanced target (sheet, Settings, CLI) · **in** input only · **1** one-file sources or the sheet's "Single file" section.
Evidence: **O** OBSERVED · **D** DOC · **E** EST. The probe/experiment reference follows.

### 1.2 Containers

> [challenge] **Not every cell below has a round trip on this Mac.** What actually ran: create + read-back by two readers for the LA write cells [A§2–§6]; 20 sources × 15 LA targets streamed and read back (300 cells, CH-3); AAR from 5 sources and back to ZIP via staging and the `aa` CLI (CH-4); DMG create (`diskutil image create from`) and 7zz extract (CH-5); WIM create and extract (CH-6); split 7z/zip/tar.gz/tar.xz/tar.zst (CH-7). **Untested cells** are marked "untested" below or carry E/D: ARJ and RPM (no sample), multi-cabinet CAB, encrypted-DMG convert, HFS+ DMG via 7zz, single-stream sources → containers (needs the `raw` path; bsdtar can't drive it), AEA → non-AAR targets (only AEA → folder ran), the LA ↔ AF in-process bridge, and every result on macOS 26.

| Format (extensions) | Create | Extract | Convert-to | Password create | Password extract | Multi-part create | Multi-part extract | Peek | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| **ZIP** `.zip` | LA Deflate, UTF-8 flag; store for already-compressed entries | LA | W | LA AES-256 (ZipCrypto only behind "compatible, weak") | LA (ZipCrypto, WinZip AES-128/256); PKWARE SES — | 7Z `-v` → `.zip.001`; LA+S fallback | LA `open_filenames` (`.zip.001`, `.z01…+.zip`); 7Z | LA (names visible even when encrypted) | O [A§2, §6.1–6.2, §7.4; B§3.4, §3.6] |
| ZIP variants (zipx, bzip2/lzma/xz/zstd/PPMd inside, **Deflate64**) | — (we only write Deflate/store) | LA; **7Z for Deflate64** (LA: "Unsupported ZIP compression method 9") | in | — | LA / 7Z | — | as ZIP | LA / 7Z | O [A§6.1, §7.2] |
| **7z** `.7z` | **7Z** `-mx5 -ms=64m -snl`; LA LZMA2 fallback (no AES) | LA; 7Z for AES and Deflate64 | W | **7Z AES-256 + header encryption** (names hidden) | 7Z (LA lists data-only-encrypted, can't decrypt) | 7Z `-v` → `.7z.001`; LA+S fallback | LA `open_filenames`; 7Z | LA; 7Z after password when headers are encrypted | O [A§6.3, §7.3, §9; B§3.3, §3.6, §4; X-1] |
| **RAR4 / RAR5** `.rar`, `.partN.rar`, `.r00` | **— never** | LA (solid, symlinks, filters, SFX) | in | — | **—** (encrypted RAR unsupported) | — | LA, all parts via `open_filenames` | LA; header-encrypted RAR5 names via 7Z with password | O [A§7.1, §7.3–7.4; B§3.5; C§4] |
| **TAR** `.tar` (pax default) | LA pax, xattrs filtered, owner names cleared | LA | W | — (format has none; sheet offers ZIP/7Z) | — | LA+S (`.tar.001`) | [challenge] **not** LA `open_filenames` (fails at the first part boundary, CH-7); our own concatenating read callback (E) or 7Z `-tsplit` (O, CH-7) | LA | O [A§2, §2.1, §4]; split create O (CH-7) |
| **tar.gz** `.tar.gz` `.tgz` (label **GZIP**) | LA | LA | W | — | — | LA+S | [challenge] concatenating callback (E) / 7Z (Split, O CH-7); LA `open_filenames` fails | LA (whole stream decoded to list) | O [A§4, §9; CH-3] |
| **tar.bz2** `.tar.bz2` `.tbz2` `.tbz` | LA | LA | W | — | — | LA+S | [challenge] as tar.gz (bz2 split untested) | LA | O [A§4; CH-3] |
| **tar.xz** `.tar.xz` `.txz` | LA `xz:threads=0` | LA | W | — | — | LA+S | [challenge] as tar.gz (O CH-7) | LA (≈ 25 s/GB to list) | O [A§4, §9; CH-3] |
| **tar.zst** `.tar.zst` `.tzst` | LA `zstd:threads=0` | LA | W | — | — | LA+S | [challenge] as tar.gz (O CH-7); 7Z reads the split set | LA | O [A§4; CH-3] |
| tar.lz4 · tar.lz (lzip) · tar.lzma `.tlz` · tar.Z `.taz` · tar.lzo | LA | LA | A | — | — | LA+S | [challenge] concatenating callback (E) | LA | O [A§2–§5; CH-3] (lzip/lzop: LA self-read only, no independent decoder) |
| **Apple Archive / Encrypted** `.aar` `.aea` | AF lzfse; lzma for Smallest; `lzraven` only on 27 and hidden | AF | W (`.aar`) | AF `.aea` (passphrase 20–256 bytes) | AF | — | — | AF (headers only) | O [C§1; X-5]; [challenge] any → AAR and AAR → ZIP via staging + `aa` CLI O (CH-4); the in-process bridge is E |
| **Disk image** `.dmg` | HD `create from` ULFO (ULMO Smallest) | HD attach read-only to a private mount, then copy | W | HD AES-256, password on stdin | HD `--stdinpass` | — | — | **7Z** (user space, no mount) [challenge] only with the chained type `-tapfs.dmg` / `-thfs.dmg`: plain `-tdmg` lists partitions (`4.disk image`), not files (CH-5) | O [C§2; B§3.1]; [challenge] 7Z extract of an unencrypted APFS ULFO image with `-tapfs.dmg -sns-` is byte-identical (content, symlink, +x; xattrs dropped). Without `-sns-` 7zz writes a junk `name:com.apple.provenance` file beside every file (CH-5). HFS+ and encrypted images untested in 7Z |
| **ISO 9660** `.iso` | HD `makehybrid -iso -joliet -udf`; LA only for shallow trees (bugs B-3). [challenge] **makehybrid breaks symlinks**: ISO9660/RR stores them with an empty target (LA and 7Z both see `link -> ""`), and in the UDF part the mounted link fails `readlink` with error 10000 (CH-8). Resolve links to file copies (reported) before makehybrid, or use LA's writer when the tree is shallow; drop `-udf` | LA (Joliet, Rock Ridge, zisofs); ~~7Z for UDF~~ [challenge] **neither engine reads Apple-made UDF**: 7zz 26.04 says "Unsupported feature", LA sees 0 entries (CH-8). UDF-only discs go to the H-4 "unsupported" path, or a mount path behind the DMG rules (AR-S5) | A | — | — | — | — | LA; [challenge] UDF: none | O [A§6.4, §7.1–7.2 H-4; C§2; CH-8] |
| cpio `.cpio` `.cpgz` | LA newc | LA | A | — | — | — | — | LA | O [A§2] |
| XAR `.xar` `.pkg` `.xip` | LA (needs the libxml2 build fix B-1) | LA; pkg `Payload` shown as an entry | A | — | — (signatures not checked) | — | — | LA | O [A§2, §10.2] |
| WIM `.wim` `.swm` `.esd` | 7Z (store + de-dup only) | 7Z | A | — | — | — | 7Z E | 7Z | O [B§3.7; CH-6, extracted with `-sns-`] |
| CAB `.cab` | — | LA (MSZIP, LZX) | in | — | — | — | 7Z E (LA: multi-cabinet unsupported) | LA | O [A§7.1, §7.4] |
| LHA / LZH `.lzh` `.lha` | — | LA (CP932 names) | in | — | — | — | — | LA | O [A§7.1] |
| ARJ `.arj` | — | 7Z | in | — | — | — | — | 7Z | D [B§3.1]; [challenge] untested (no sample); handler present in the pruned build (CH-2) |
| ar / Debian `.a` `.ar` `.deb` | — (flat-only writer, not exposed) | LA (members; inner `data.tar.*` not auto-extracted) | in | — | — | — | — | LA | O [A§6.5] |
| RPM `.rpm` | — | 7Z (LA rpm filter not probed) | in | — | — | — | — | 7Z | D [B§3.1]; LA E (AR-S7) |
| Self-extractors `.exe` (zip/7z/rar SFX) | **— never** | LA when the sniffer finds an SFX payload | in | — | as inner format | — | — | LA | O [A§7.1] |
| "All formats": MSI/CFB, CHM, NSIS, APFS/HFS/NTFS/FAT/ext/SquashFS images, VHD(X), VMDK, QCOW, VDI | — | 7Z, only via explicit **Open disk image / All formats** | in | — | — | — | — | 7Z | O [B§3.1, §5] |
| StuffIt `.sit` `.sitx`, ACE, ZPAQ, ARC, ZOO | — | **—** | — | — | — | — | — | — | neither engine; unar probe is backlog AR-B1 |
| shar, mtree, warc | — | **—** (readers disabled, H-7) | — | — | — | — | — | — | O [A§10.1] |

### 1.3 Single-stream compressors (one file in, one file out)

| Format | Compress | Decompress | Convert-to | Passwords, multi-part | Peek | Evidence |
|---|---|---|---|---|---|---|
| gzip `.gz` | LA `raw` + gzip | LA `raw` | 1 (wheel slot **GZIP** means tar.gz, parity) | — | one item, name from header or derived | O [A§5] |
| bzip2 `.bz2` · xz `.xz` · zstd `.zst` · lz4 `.lz4` | LA | LA | 1 | — | one item | O [A§5] |
| lzip `.lz` · lzma `.lzma` · compress `.Z` · lzop `.lzo` | LA | LA | 1 (advanced) | — | one item | O [A§5]; lzo needs lzo2 (GPL-2.0+) |
| **brotli** `.br` | **AF** (level 2 only) | **AF** (any level) | 1 (advanced) | — | one item | O [X-4]; LA silently passes `.br` through (H-4) |
| uuencode / base64 `.uu` `.b64` | — | LA | in | — | one item | O [A§5] |
| lrzip, grzip | — | **—** (LA would exec external programs, H-9) | — | — | — | O [A§2] |

### 1.4 What the matrix implies

- **Every cell marked LA works without 7zz.** If OWN-ARC-2 stays closed, the losses are: 7z AES, split-volume *creation* by 7-Zip (LA+S still splits), Deflate64, ~~UDF,~~ WIM, ARJ, RPM, disk-image peek and the "All formats" set. [challenge] Two more: reading split tar.\* sets needs either 7Z or our own concatenating read callback (LA's `open_filenames` fails on them, CH-7), and UDF isn't on the list because 7zz doesn't read Apple-made UDF either (CH-8).
- **Passwords exist only in ZIP, 7z, DMG and AEA.** Every other target disables the password field and offers ZIP or 7Z instead.
- **Names stay visible** in AES-ZIP and data-only 7z. Only 7z header encryption, DMG and AEA hide them [B§3.3, §3.4].

---

## 2. Wheel placement (12-slice cap, 03a §2.2, FR-90)

The wheel has no submenus and the "More…" overflow slice is off (OWN-APP-4). So "More formats" is reached three ways: the **ARCHIVE…** and **CONVERT…** sheets (format picker, §3), **Settings › Archives › Show in wheel** (per-format checkboxes; the FR-90 lint refuses a 13th slot), and custom wheels, App Intents and the CLI.

### 2.1 Multi-file drops and folders (Actions wheel, any items)

| Slot | Slice | Behaviour |
|---|---|---|
| 1–6 | AIRDROP, BOX, COPY, MOVE, COPY PATH, TERMINAL | unchanged (FR-93) |
| 7 | **ZIP** | instant; remembered defaults (Normal, one archive, junk stripped); `Archive.zip` / `Folder.zip` |
| 8 | **7Z** | instant; Normal; 7Z engine, LA fallback |
| 9 | **ARCHIVE…** | opens the options sheet with every create format (§3.1) |
| 10 | LOCK | AES-256 ZIP via the shared password sheet (FR-96, 17b-lock.md F4) |
| 11 | RENAME… | unchanged (FR-93) |
| 12 | free | reserved; a user can pin TAR.GZ, TAR.XZ, DMG etc. here from Settings |

This replaces 17 §8.2's extras column (7Z, TAR.GZ, TAR.XZ, TAR.ZST): one ARCHIVE… slice reaches all 28 create formats instead of four. Folders keep "Folders work with Actions only" on the Convert wheel (03a §2.6).

> [challenge] Cap check: Actions 11/12, archive Tools 5/12, Convert ≤ 9/12. All within FR-90 (verified against 17 §8.1–8.2). Two naming collisions to settle:
> - **LOCK means two things on one archive.** Actions LOCK on `data.zip` wraps the file and gives `data Locked.zip` (17b-lock.md F4). Tools LOCK · UNLOCK on the same file re-encrypts its entries and also gives `data Locked.zip`. Same name, different contents (a zip inside a zip versus an encrypted copy). Proposal: when the drop is one archive that Tools LOCK supports, Actions LOCK runs the Tools behaviour. **[OWNER]** OWN-ARC-9.
> - **"GZIP" versus "TAR.GZ".** The parity wheel label GZIP writes `.tar.gz` (03a §4.4), but the sheet (§3.1) and 17 §8.2 call the same target TAR.GZ, and the sheet's "Single file" group has a different GZ. On a single-stream source (`log.xz`), Convert → GZIP gives `log.tar.gz`, not the `log.gz` most people expect. Proposal: keep the GZIP wheel label (parity), call it "TAR.GZ (GZIP)" in the sheet, and for single-stream sources show the single-stream targets (GZ, ZST, XZ, BZ2) on the Convert wheel instead of the tar ones. **[OWNER]** OWN-ARC-10.

### 2.2 One archive dropped

| Wheel | Slices (catalog order) |
|---|---|
| **Convert** (⇧) | Parity first (03a §3.3): zip → TAR, GZIP; tar → ZIP, GZIP; gz → ZIP, TAR; rar → ZIP, TAR, GZIP. Every other source starts with ZIP, TAR, GZIP. Then the extras in this order, minus the source's own format: **7Z, TAR.XZ, TAR.ZST, TAR.BZ2, DMG, AAR**. At most 9 slices: rar, cab, lha, iso, aea and single-stream sources show 9; zip, tar, gz, 7z, tar.bz2/xz/zst, dmg and aar show 8. |
| **Tools** (⌘) | **EXTRACT**, **PEEK**, **LOCK · UNLOCK** (zip, 7z, dmg, aar/aea only; one slot, FR-92), **CONVERT…** (sheet: any of 18 targets plus options), **TEST** (integrity check, no output) |
| Actions (⌃) | §2.1 |

### 2.3 Other archive drops

| Drop | Convert | Tools | Hub label |
|---|---|---|---|
| Several archives, same format | as §2.2 (each converted separately) | EXTRACT (each to its own folder), PEEK (≤ 8 windows; more → disabled with "Peek one archive at a time"), LOCK · UNLOCK, CONVERT…, TEST | `3 ZIP FILES` |
| Mixed archive formats | intersection of targets (03a §2.6), so the extras usually survive | same | `MIXED` |
| **One volume set** (all parts, or any single part with siblings beside it) | as §2.2 for the set's format | as §2.2, acting on the whole set | `RAR · 6 PARTS` |
| A single-stream file (`log.xz`, `dump.sql.zst`, `x.br`) | ZIP, 7Z, TAR, GZIP… (the file becomes one entry, as 10 §4.12 does for plain `.gz`) | EXTRACT (decompress → `log`), CONVERT… (recompress to another single-stream format) | file name |
| One non-archive file | unchanged | unchanged (image COMPRESS etc. stays lossy media compression, owner note) | unchanged |
| Disk images (`.dmg`, `.iso`) | as §2.2 | EXTRACT (DMG: first-use note about private read-only mounting), PEEK | file name |

> [challenge] PEEK on a `.dmg` runs 7zz's APFS/HFS parsers, which are the CVE-heavy ones [B§5]. §6.1 says those are reachable "only via the explicit action". Rule to make the two consistent: tapping PEEK or EXTRACT on a sniffed DMG counts as the explicit action for that file. Hover, size previews, Quick Look, mixed drops and the "All formats" sniff never invoke them.

Settings › Archives also offers advanced targets as wheel slices (ISO, TAR.LZ4, TAR.LZ, TAR.LZMA, TAR.Z, CPIO, XAR, WIM). The lint counts them against the 12-slot cap per input.

---

## 3. Options UX

### 3.1 The ARCHIVE… / CONVERT… sheet

One SwiftUI sheet (P2-30 tool window shell), remembered per format. Rows top to bottom:

1. **Format** picker, grouped, each item with a one-line compatibility hint:

| Group | Formats | Hint shown |
|---|---|---|
| Recommended | ZIP · 7Z · TAR.GZ | ZIP "Opens everywhere"; 7Z "Smallest; opens with Archive Utility, 7-Zip, Keka" (Archive Utility declares a 7z viewer [C§3]; AES 7z by double-click is AR-S4) |
| Smaller | TAR.XZ · TAR.ZST · TAR.BZ2 | TAR.ZST "Fast; doesn't open by double-click on a Mac" (Archive Utility has no zst role [C§3]) |
| Mac | AAR · DMG | AAR "Mac-only; keeps every Mac detail"; DMG "Mac disk image; slower to make (≈ 3–5 s minimum)" [C§1.3, §2.2] |
| Unix and more | TAR · TAR.LZ4 · TAR.LZ · TAR.LZMA · TAR.Z · TAR.LZO · CPIO · XAR · ISO · WIM | per format; WIM "Windows imaging, no compression" |
| Single file (only when exactly one regular file) | GZ · BZ2 · XZ · ZST · LZ4 · LZ · LZMA · Z · BR · LZO | "One file only; no folder structure" |

2. **Level**: Fast / Normal (default) / Smallest, mapped per engine. The sheet shows speed as "about N MB/s" from the table, scaled by the machine's measured throughput:

| Format | Fast | Normal | Smallest | Evidence |
|---|---|---|---|---|
| ZIP (LA) | Deflate 1 | Deflate 6 (store for jpg/heic/mp4/zip/docx…, 64 KB sample) | Deflate 9 | O [A§4; 17b-lock.md §6.1] |
| 7z (7Z) | `-mx1` | `-mx5 -ms=64m` | `-mx7 -ms=64m` (not `-mx9`: ≈ 950 MB RSS) | O [B§4] |
| 7z (LA fallback) | LZMA2 1 | LZMA2 6 | LZMA2 9 | O [A§6.3] |
| tar.gz / .gz | 1 | 6 | 9 | O [A§4] |
| tar.xz / .xz | 1, threads 0 | 6, threads 0 | 9, threads 0 | O [A§4] |
| tar.zst / .zst | 1, threads 0 | 3, threads 0 | 19, threads 0 ("slow") | O [A§4] |
| tar.bz2 / .bz2 | 9 | 9 | 9 (levels barely differ) | O [A§4] |
| tar.lz4 / .lz4 | 1 | 1 | 9 | E |
| AAR | lz4 | lzfse | lzma, 256 KiB blocks (≈ 10× faster than 4 MiB, ≈ 4 % bigger) | O [C§1.1] |
| DMG | ULFO | ULFO | ULMO | O [C§2.2] |
| BR | 2 | 2 | 2 (the only level Apple encodes) | O [X-4]; D compression.h |

3. **Password** (the shared FR-96 sheet, P2-101). Rules per format:
   - **ZIP:** AES-256 by default. ZipCrypto only behind "Compatible with very old tools (weak)", ASCII passwords only. Note: "Names stay visible. Windows may need 7-Zip." ZIP passwords are written by LA, which accepts UTF-8; 7zz refuses non-ASCII ZIP passwords, so 7Z never writes password ZIPs [B§3.4].
   - **7Z:** AES-256, "Hide file names" on by default (`-mhe=on`). Unicode passwords work [B§3.3; X-1].
   - **DMG:** AES-256 only (no AES-128 in `diskutil image`) [C§2.1].
   - **AAR → AEA:** 20 to 256 UTF-8 bytes, enforced by the framework. A shorter password gets "Too short for a Mac locked archive" plus Suggest (`generatePassword()`), or "Use 7Z instead" [C§1.4].
   - Any other format: field disabled, with "TAR.GZ can't hold a password. Use ZIP or 7Z."
4. **Split into parts**: Off (default) / 25 MB (Gmail) / 100 MB (WhatsApp) / 4 GB (FAT32) / Custom. Enabled for 7Z, ZIP and tar.\*. Outputs `Name.7z.001…`, `Name.zip.001…`, `Name.tar.gz.001…`. Hint for ZIP: "Rejoin with Zivlet, 7-Zip or Keka; Archive Utility can't open split ZIPs" (ditto can't [B§3.6]; the GUI is AR-S4).
5. **One archive** (default) / **One per item**.
6. **Leave out Mac clutter** (default on): `.DS_Store`, `._*`, `__MACOSX/`, `.Spotlight-V100`, `.Trashes`, `.fseventsd`, `.TemporaryItems`, `Icon\r`, and the `com.apple.provenance`, `com.apple.quarantine`, `com.apple.macl` and `com.apple.lastuseddate#PS` xattrs (H-6). Never `ARCHIVE_READDISK_MAC_COPYFILE`, because it writes temp files into the user's folders (H-1).
7. **Keep Mac details** (default off; enabled only for TAR, XAR and AAR, where AAR always keeps them): user xattrs, Finder tags, resource forks. ZIP stays clean. The Finder-style `__MACOSX` ZIP via `ditto` (13 §6.4) is dropped: it writes no UTF-8 flag (Windows mojibake) and doubles the entry count on macOS 26/27 [C§3]. Point people to AAR instead.
8. **Advanced** (collapsed): keep owner names (default off: tar/cpio otherwise record the local account name and uid, a privacy leak); keep symlinks as links (default on; off = store the target's content); ZIP method (Deflate default; bzip2/xz/zstd marked "opens only in 7-Zip/Zivlet" [A§6.1]).

### 3.2 Extraction behaviour (Settings › Archives, and the EXTRACT sheet with ⌥)

| Setting | Default | Rule |
|---|---|---|
| **Smart folder** | on | One top-level folder `D/` (ignoring Mac clutter) → publish `D` beside the archive. One top-level file → publish the file. Otherwise → folder `<base> Extracted` (parity name, 03a §4.4). Turning it off always gives `<base> Extracted`. Deviation from parity → O-16 row **[OWNER]** OWN-ARC-3. |
| **Never overwrite** | always | Staging on the destination volume, then `renamex_np(RENAME_EXCL)` with `" 2"` candidates (03a §4.3). Not a setting. |
| Mac details from Finder ZIPs | restore | LA folds `__MACOSX/._X` into `X` on read; with `ARCHIVE_EXTRACT_MAC_METADATA` it restores tags and resource forks, then our filter removes provenance, quarantine and macl before Publisher applies the archive's quarantine. With the setting off, the AppleDouble data is dropped and no `__MACOSX` folder appears either way (OBSERVED, X-3). |
| After extracting | reveal in Finder | "Move archive to Trash" (off), "Open the folder" (off) |
| Batch | each archive to its own folder | "Extract all into one folder" option in the sheet |
| Name encoding | Automatic | §6.2 |

### 3.3 Naming (extends `OutputNamer`, 03a §4.4)

| Case | Output | Note |
|---|---|---|
| Create from one folder `Photos` | `Photos.zip` | Finder parity |
| Create from one file `report.pdf` | `report.pdf.zip` | Finder parity; the full name survives a round trip |
| Create from several items | `Archive.zip`, then `Archive 2.zip` | Finder parity |
| One per item | `<item>.<ext>` for each | |
| Lock (AES ZIP) | `<base> Locked.zip` | 17b-lock.md §3, unchanged |
| Convert archive → archive | `<base>.<ext>`: `backup.tar.gz` → `backup.zip`, `site.zip` → `site.tar.zst` | compound stripping below |
| Single-stream compress | `server.log` → `server.log.gz` | |
| Single-stream decompress | `server.log.gz` → `server.log`; gzip's stored name is used only when it sanitises to the same base | |
| Decompress-only of a tar stream (sheet option) | `x.tgz` → `x.tar` | |
| Split | `Name.7z.001`, `Name.zip.001`, `Name.tar.gz.001` | three-digit width, 7-Zip convention |
| Extract one entry from Peek | sanitised entry name in the chosen folder, `" 2"` on collision | |

**Compound extensions** stripped as one unit when computing `<base>` (extends the 03a §4.4 base-name rule): `.tar.gz .tgz .tar.bz2 .tbz2 .tbz .tar.xz .txz .tar.zst .tzst .tar.lz4 .tar.lz .tar.lzma .tlz .tar.Z .taz .tar.lzo .cpio.gz .cpgz`, plus the volume suffixes `.7z.NNN .zip.NNN .tar.*.NNN .partN.rar .rNN .zNN`.
[challenge] **The collision rule must use the same compound list.** 03a §4.4 writes `<name> 2.<ext>`. With only "the last extension" as `<ext>`, `backup.tar.gz` would collide into `backup.tar 2.gz`. It must be `backup 2.tar.gz`, and `Name 2.7z.001` for split sets. A split set is **one claim**: `NameReserver` reserves the base for every part, and the parts publish under it or all retry with the next candidate. Per-part `RENAME_EXCL` alone can produce `Name.7z.001` beside `Name 2.7z.002`. Truncation (≤ 255 bytes) also has to keep the compound suffix plus `.NNN` whole. AR-04 goldens cover these.
**Extension regex gap:** 03a requires `[a-z0-9]+(\.[a-z0-9]+)*` and lower case, but `compress` output is conventionally `.Z` (lower-case `.z` is the old `pack` format). Proposal: allow the single upper-case token `Z` as the last component (`.Z`, `.tar.Z`) **[OWNER]** OWN-ARC-6; otherwise write `.taz` and `.Z` stays decompress-only.

---

## 4. Peek inside

### 4.1 Window

A Quick Look-style floating panel (NSPanel, utility, 640 × 480 default, resizable), opened by the PEEK slice, by Space on an archive in Zivlet's History, or by `zivlet archive list`.

```
┌ backup.7z — 7z · LZMA2 · solid · 1,803 items · 28.4 MB → 6.6 MB (23 %) · 🔒 names hidden ┐
│ [Search…]                                        [Extract Selected] [Extract All] [Convert…] │
│ ▾ docs/                         —        —      2026-10-20                                   │
│     design.md               48 KB    11 KB      2026-10-20                                   │
│     ⚠ ../../evil.sh          1 KB      1 KB      — will be skipped: leaves the folder        │
│ ▸ src/                      12 MB     2 MB                                                   │
│ status: listed in 0.06 s · Space previews · drag items out to extract them                   │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

- **Columns:** name (outline), size, packed size (when the format has it), modified, kind, a lock badge per encrypted entry. Sorting by any column; ⌘F search with live filter.
- **Space** = Quick Look of the selected entry. The worker extracts that one entry into the job's 0700 staging folder under the full policy (§6), then the app shows it in `QLPreviewPanel`. Quick Look renders in its own extension processes, so the app still parses no archive bytes (10 §2.1 rule 1).
- **Extract Selected** (⌘E) writes the chosen entries, keeping relative paths under the selection's common parent, to beside the archive (default) or a chosen folder. **Drag out** uses `NSFilePromiseProvider`: the entry is extracted when the drop lands.
- **Nested archives** (a `.zip` inside a `.tar.gz`) show a disclosure badge. Opening one is an explicit double-click that extracts it to staging and opens a second Peek, max depth 3. Nothing nests automatically.
- **Warnings inline:** entries that would be skipped (traversal, absolute path, escaping symlink, device node, case collision, over-long name) are listed with the reason, so the user sees the policy before extracting.
- Keyboard: arrows, ⌘↓ open nested, Space, ⌘E, ⌘F, Esc closes. VoiceOver reads name, size and warning per row.

### 4.2 Engine behaviour

| Archive | Listing source | Cost | Evidence |
|---|---|---|---|
| zip, 7z, rar, iso, cab, xar | central directory / headers (LA) | 0.06–0.14 s for 1,800 entries | O [A§9] |
| tar.gz, tar.zst, tar.xz… | the whole stream must be decoded | tar.xz ≈ 25 s/GB; list progressively and cache by path + size + mtime | O [A§9] |
| solid 7z / solid RAR, one late entry | decode up to the entry | 0.56 s (LA) to 5.7 s (7Z) for a late entry; our own 7z uses `-ms=64m` blocks | O [A§9; B§3.8] |
| header-encrypted 7z, header-encrypted RAR5 | 7Z `l -slt` after the password sheet | 0.02 s for 1,619 entries | O [B§3.5, §3.8] |
| AES-ZIP, data-only 7z | LA lists without a password; the sheet appears on Quick Look/extract | — | O [A§7.3, §9] |
| aar / aea | AF `decodeStream` reading `TYP,PAT,DAT,SIZ,MTM` only | — | O [C§1.5] |
| dmg, disk images | 7Z listing in user space; never mounted for a peek. [challenge] Pass a chained type: `-tapfs.dmg`, falling back to `-thfs.dmg`. `-tdmg` alone lists only partitions, and the reversed chain `-tdmg.apfs` fails (CH-5) | — | O [B§3.1; C§2.4; CH-5] |

The worker streams `ArchiveListingEvent` batches (Codable, ≤ 500 entries per message) over XPC. The listing stops at 100,000 entries with "Showing the first 100,000 items" (the same cap as extraction). Displayed names are escaped: control characters show as `�`, and bidi overrides are shown as visible escapes (§6.1).

---

## 5. Archive → archive conversion

### 5.1 Method per engine pair

| Source read by | Target written by | Method | Extra disk | Evidence |
|---|---|---|---|---|
| LA | LA | **stream**: `archive_read_next_header` → `archive_write_header` + data loop; no extraction | none (LA's 7z and ISO writers buffer internally) | O [A§8]; [challenge] A§8 filled 51 of its 63 cells, not "all 9 × 7". CH-3 adds 20 sources (zip, 7z, tar, tar.gz/bz2/xz/zst/lz4/lz/lzma/Z/lzo, cpio, xar, hybrid ISO, RAR4, RAR5, RAR5 with links, CAB, LHA) × 15 targets (zip, 7z, pax, the 10 filtered tars, newc cpio, xar, ISO): every cell reads back identical through LA except cpio from RAR5-with-links and LHA (directories and links dropped, "Size required", **exit 0**) and the makehybrid ISO source (its symlinks are already broken). An independent reader (7zz, or the system decompressor + `/usr/bin/tar`) agreed on every zip, 7z, tar and filtered-tar cell except lzip/lzop, which have no decoder here. Independent readers disagree on the others in ways recipients will notice: 7zz reads LA's ISO through Joliet (symlinks become empty files, +x lost), shows xar names in base64 [A§2], and on newc cpio converted from zip/7z/CAB it gives a 0-byte entry another file's content (BSD `pax` reads the same cpio correctly) |
| LA | AF (aar) | stream bridge: LA entry → `ArchiveStream.encodeStream` (`writeHeader` + `writeBlob`) | none | D [C§1.3] (≈ 200 lines of glue, E); [challenge] the staging route (LA extract → `aa archive` → `aa extract`) is O for 5 sources (CH-4); the bridge itself is untested |
| AF (aar/aea) | LA | stream bridge: `decodeStream` → LA writer | none | D [C§1.3]; [challenge] AAR → ZIP via staging O (CH-4) |
| LA / AF | 7Z (7z, wim, split, 7z AES) | extract under the full policy into 0700 staging → `7zz a` | 1 × uncompressed | ~~O [B§6]~~ [challenge] B§6 is a plan. Staging → `7zz a -twim`/`-t7z` is O for a folder (CH-1, CH-6), not per source; NFR-21 allows 0700 staging |
| 7Z (encrypted 7z, Deflate64, ~~UDF,~~ WIM, ARJ, RPM) | LA / AF | `7zz x` into staging (watchdog) → LA/AF create from disk | 1 × uncompressed | ~~O [B§5]~~ [challenge] B§5 is the security section. `7zz x` → staging is O for 7z AES, WIM and APFS DMG (CH-1, CH-5, CH-6); ARJ and RPM untested |
| HD (encrypted DMG) | any | attach read-only → read the mount with `archive_read_disk` (physical, no traversal) → writer | none | O [C§2.3] |
| any | HD (dmg) / HD (iso) | staging → `diskutil image create from` / `hdiutil makehybrid` | 1 × + image | O [C§2.2] |

Preflight: free space ≥ 1.5 × estimate + 512 MB (03b §9 disk row), using declared sizes where the format has them.

### 5.2 What is preserved

| Property | Rule |
|---|---|
| Content, folder structure, empty folders | always (O [A§8]) |
| Modification time | always; birth time where both ends carry it (pax, aar) |
| Permission bits | rwx kept; setuid, setgid and sticky cleared and reported |
| Owner (uid/gid/names) | dropped unless "Keep owner names" |
| Symlinks | kept as links when the target supports them (zip, 7z, tar, cpio, xar, aar, ISO Rock Ridge); links that escape the archive root are dropped and reported |
| Hardlinks | kept in tar/cpio/xar/aar; turned into copies for zip/7z (zip drops the second link otherwise [A§2.1]) |
| Xattrs, resource forks | pax ↔ xar ↔ aar only with "Keep Mac details"; provenance, quarantine and macl never |
| Names | NFC on write (vendor patch, 17b-lock.md §6.4); converted to UTF-8 from the source's encoding (§6.2) |
| Per-entry failures | every `archive_write_header()` result is checked (H-3). Default **fail closed**: "3 items can't be stored in ISO (path too long)", with Details and "Convert without them". [challenge] Seen in CH-3: the cpio writer refuses directories and symlinks that arrive without a size (LHA, RAR5) with "Size required", and bsdtar still exits 0. Fix in the converter: set size 0 for directories and the target length for symlinks before `write_header` |

### 5.3 Encrypted sources

| Source | Behaviour |
|---|---|
| AES/ZipCrypto ZIP | password sheet first; LA decrypts in memory while streaming |
| 7z AES | 7Z path, plaintext only in 0700 staging, removed on success, cancel or next-launch reaper (NFR-21) |
| AEA, encrypted DMG | AF decryption stream / HD attach with stdin password |
| Encrypted RAR | `unsupportedEncryption`: "Encrypted RAR files can't be opened by Zivlet. The Unarchiver or Keka can." |
| **Target protection** | When the source is encrypted, the target **keeps a password by default** (same password pre-filled). If the target format can't hold one (tar.\*, iso…), the sheet says "The new file will **not** be password-protected" and needs an explicit confirm. No silent decryption. |

Quarantine from the source archive is copied onto the output (Publisher, 03b §9). The bomb limits of §6 apply to the bytes streamed through the converter as well as to staging.

---

## 6. Security hardening (aligned with 03b §9)

### 6.1 Controls (new or changed rows for 03b §9; columns as there)

| Threat | Control | Where | Test | Source |
|---|---|---|---|---|
| Unexpected parsers reachable from a drop | LA readers enabled one by one: `zip_seekable, 7zip, rar, rar5, tar, cpio, iso9660, xar, cab, lha, ar`; filters `gzip, bzip2, xz, lzma, lzip, zstd, lz4, lzop, compress, uu`. Never `_all`, never mtree, warc or shar; `raw` only on the single-stream path. No program filters (lrzip/grzip) | EngineArchive | an `#mtree` text file and a `.br` renamed `.gz` are refused | [A§10.1 H-7, H-9] |
| Silent "success" on unsupported input | Non-empty input with 0 entries, or a raw pass-through of an unknown stream, is `unsupportedInput` (UDF misread as an empty tar, `.br` pass-through) | EngineArchive | UDF ISO and `.br` fixtures | [A§10.1 H-4] |
| Path traversal | `ARCHIVE_EXTRACT_SECURE_NODOTDOT` + `SECURE_SYMLINKS` + `SECURE_NOABSOLUTEPATHS` (off by default in the library), **plus** our pre-check per entry: no `..` component, no leading `/`, no drive letter (`C:`), `\` treated as a separator for DOS-made ZIPs, no NUL or Cc characters, component ≤ 255 UTF-8 bytes, full destination path ≤ 1,024 bytes; failures skip the entry and are reported | `ArchivePolicy` (pure), EngineArchive | zip-slip, absolute, drive-letter, backslash, mid-path `a/../../x` | [A§10.1 H-2; B§5] |
| Symlink escape | Relative links whose resolved target stays inside the extraction root are created; absolute or escaping links are dropped and reported; no write ever goes through a link (LA `SECURE_SYMLINKS`); AppleArchive needs the same policy because it creates absolute links [C§1.6] | ArchivePolicy | link-then-write-through, chained links, absolute link in aar | [A§10.1; C§1.6]; [challenge] **this relaxes 03b §9**, whose archive row reads "No `..`, symlinks, absolute paths". Keeping in-root relative links is right for parity (Archive Utility keeps them, and app bundles and source trees need them), but the 03b row must be reworded to "no escaping symlinks", and the hostile corpus needs a link that points at a link that leaves the root |
| Hardlink escape | Hardlinks only to an already-extracted entry inside the root | ArchivePolicy | hardlink to `/etc/hosts` | new; [challenge] O (CH-9): with the secure flags LA strips `/` from the hardlink target (then "target does not exist") and refuses `..` targets. The pre-check stays as a second layer |
| Device files, FIFOs, sockets | Never created (`AE_IFCHR/IFBLK/IFIFO/IFSOCK` skipped and reported); owner never applied (no `EXTRACT_OWNER`); setuid/setgid/sticky cleared; ACLs not applied | ArchivePolicy | FIFO and device fixtures in tar and cpio | [13 §6.3] + new; [challenge] needed: LA (bsdtar 3.8.10 defaults) **creates the FIFO** (CH-9); setuid was cleared because we're not root |
| Case and normalisation collisions | APFS is case- and normalisation-insensitive, so `A.txt` and `a.txt` (or NFC/NFD twins) collide; with `EXTRACT_UNLINK` the later entry would silently replace the earlier one. Second occurrence gets `" 2"` and a report line; the key is case-folded NFC | ArchivePolicy | colliding-names fixture | new; [challenge] O (CH-9): even **without** `EXTRACT_UNLINK`, LA's defaults silently keep only the second entry for both `A.txt`/`a.txt` and `Café` NFC/NFD, and still exit 0 |
| Spoofed names | Bidi controls (U+202A–202E, U+2066–2069) and Cc characters in entry names become `-` on disk (extends the 03a §4.4 safety rule) and are shown escaped in Peek | ArchivePolicy, Peek | `invoice‮fdp.exe` fixture | new |
| Bombs | Total ≤ min(20 × archive + 1 GB, free − 2 GB); ≤ 100,000 entries (unchanged). Ratio: when an entry passes 100 MB written at more than 1,000 × its compressed size (or, for solid and stream formats, the running total passes 100 MB at more than 1,000 × the bytes consumed) the job pauses with "This archive expands unusually (possible archive bomb)" and **Stop** / **Continue** (Continue raises the limits 10× once). Declared sizes are pre-checked but never trusted. 7Z: `l -slt` pre-check plus a staging watchdog that kills the process group at the cap | EngineArchive, SevenZipRunner | 42.zip, overlapping-entry zip, RAR4 fixture 190 KB → 241 MB (must prompt, then complete) | [10 §8.9; B§3.6, §5]; [challenge] fixture size confirmed: 189,201 B of parts (CH-1). Two caveats. (1) Deflate tops out near 1,032:1, so the 1,000× trigger barely fires for ZIP bombs; the absolute cap (min(20 × archive + 1 GB, …)) is what stops a deflate or overlapping-entry bomb, and the per-entry ratio mostly catches bzip2/xz/zstd/LZMA streams. Keep both, and make the test assert the cap, not the prompt, for the overlapping zip. (2) **Memory bombs are uncovered**: an LZMA/xz header can declare a dictionary of up to 4 GB, and neither LA's memlimit nor 7zz's limit was probed. Add a crafted-dictionary fixture and rely on the worker watchdog (and a 7zz RSS kill) until a spike shows the limits |
| Nested archives | Never auto-extracted; Peek nesting only on explicit action, depth ≤ 3 | EngineArchive | zip-in-tar-in-zip | [10 §8.9] |
| Name encoding | §6.2; the worker calls `setlocale(LC_CTYPE, "UTF-8")` at start, because under the C locale LA reports names as unconvertible and escapes them | EngineArchive | CP437, CP932, UTF-8-unflagged fixtures | [17b-lock.md §6.4; X-2]; [challenge] X-2's fixture was flawed (§6.2). Also: when a `hdrcharset` is set and one entry can't be converted, bsdtar **skips that entry** ("empty or unreadable filename"). The worker must fall back to the raw bytes and never drop the entry (CH-10) |
| Quarantine laundering | Copy the archive's `com.apple.quarantine` verbatim onto every extracted item (Archive Utility does this; neither LA nor 7zz does) | Publisher | 9 parity pairs + extract + peek-extract assert the xattr | [C§3; B§5] |
| Source modified on create | Never `ARCHIVE_READDISK_MAC_COPYFILE`; `archive_read_disk` physical mode (links stored, not followed); `NO_TRAVERSE_MOUNTS`; sockets and devices in the source skipped | EngineArchive | source folder mtime and contents unchanged after create | [A§10.1 H-1] |
| Silent entry loss on create | Check every `archive_write_header()`; tar default pax (ustar/v7tar never offered) | EngineArchive | 150-character name and 284-character path round-trip | [A§10.1 H-3] |
| 7zz helper misuse | Always `-t<type>` after our own sniff (no auto-detection, so NTFS/UDF/SquashFS/WIM parsers are unreachable from an ordinary drop); `-snl` on create; `-bsp1 -bso0 -bse1 -sccUTF-8`; exit code **and** "Missing volume" / "Wrong password" text parsed (`t` exits 0 with a missing volume); zero-length partials deleted; disk images only via the explicit action; CVE bump within 7 days of an upstream security release. [challenge] Add: DMG pinned as a **chain** (`-tapfs.dmg`, then `-thfs.dmg`; plain `-tdmg` only lists partitions); **`-sns-` on every extract** (otherwise APFS/HFS/WIM/NTFS xattrs become extra `name:attr` files); keep the default dangerous-link check (no `-snld`), since our list-first policy decides on links anyway | SevenZipRunner | missing-part, wrong-type, crafted-traversal fixtures, [challenge] DMG listing golden | [B§5; CH-5] |
| Passwords | Never in argv, env, logs or History (NFR-21). LA: `archive_read_add_passphrase` / a callback that gives up after the sheet's attempt; the library never prompts (bsdtar loops forever without a tty). **7Z: create = `-p` with no value plus one stdin line; list/test/extract = no `-p` at all plus one stdin line** (`x -p` means an empty password). HD: `--stdinpass` with no trailing newline. AF: in-process API | EngineArchive, SevenZipRunner | `ps` snapshot during a job shows no password; policy suite P2-102 | [A§6.2 H-8; B§5; C§2.2; X-1] |
| DMG mounting | Only on explicit Extract/Convert; `isencrypted` first, then always stdin password (otherwise a GUI dialog hangs the worker); `-readonly -nobrowse -noautoopen -noautofsck -mountrandom` under a 0700 mount root; reject `http(s)://` and `ram://`; attach 60 s, detach 3 tries then `-force`, kill the process group on timeout; launch sweep detaches anything under our mount root; peek never mounts | DMGEngine | encrypted, corrupt, multi-volume, SLA images | [C§2.4] |
| AEA / 7zz partial outputs | Both leave a 0-byte file on a wrong password; output is always staged and published only on success | Runtime | wrong-password fixtures | [C§1.4; B§3.5] |

### 6.2 Entry-name encoding

| Archive situation | Decoding | Evidence |
|---|---|---|
| ZIP with the UTF-8 flag (bit 11), 7z, RAR5, pax, xar, aar | UTF-8 | O [A§6.1] |
| ZIP without the flag, bytes are valid UTF-8 (every `ditto`/Finder ZIP) | UTF-8 | O [X-2] |
| ZIP without the flag, bytes are not UTF-8 | ~~CP437 (LA default; correct for Western DOS/Windows ZIPs: `Äpfel-ü.txt`)~~ [challenge] **LA does not default to CP437.** Under a UTF-8 locale it passes the raw bytes through (bsdtar prints `\216pfel-\201.txt`). The worker must decode them itself: CP437 for Western DOS ZIPs, otherwise the detector | ~~O [X-2]~~ O [CH-10] |
| ZIP from Japanese, Chinese, Korean or Cyrillic Windows (CP932, CP936, CP949, CP866…) | ~~LA's default gives CP437 mojibake (`テスト` → `âeâXâg`). Neither `zip:hdrcharset=CP932` through bsdtar nor 7zz `-mcp=932` changed it~~ [challenge] **X-2's fixture was wrong.** Python's `zipfile` sets the UTF-8 flag (0x800) on every non-ASCII name, so all three X-2 entries were UTF-8-flagged and the "mojibake" was in the file itself. With a real unflagged ZIP (CH-10): `hdrcharset=CP932` **decodes `テスト.txt` correctly** and `zip:hdrcharset=GBK` decodes `中文测试.txt`; entries in any other code page then fail to convert and get skipped. 7zz mangles unflagged non-ASCII names (drops the high bytes), with or without `-mcp=932`, so 7Z must never list or extract unflagged ZIPs | O [CH-10] |
| LHA (CP932), old tar/cpio | LA charset handling; CP932 LHA names decoded | O [A§7.1] |

Design: **Automatic** = the rows above, plus a detector (spike AR-S2) that scores the raw name bytes of unflagged non-UTF-8 ZIPs against CP932, CP936, CP949, Big5, CP866 and CP1251 and picks a clear winner. Peek shows a **Name encoding** menu (Automatic / Western (DOS) / Japanese / Chinese Simplified / Chinese Traditional / Korean / Cyrillic) that re-lists instantly, and EXTRACT uses the choice. Output names are always UTF-8 NFC (NFD on disk is fine, since APFS is normalisation-insensitive [A§10.1 H-5]). Archives *we* write always set the UTF-8 flag and store NFC.
[challenge] Simplest robust design, and AR-S2's first question: read the **raw** name bytes for unflagged entries (no `hdrcharset`), then decode them per entry in Swift (`String(data:encoding:)` with CFStringEncodings for CP437/932/936/949/950/866/1251) using the detector's choice. This avoids LA's per-archive option and its skip-on-failure behaviour (CH-10).

---

## 7. Size and licence impact

| Engine | Version | Licence (SPDX) | Installed | DMG | Status | Evidence |
|---|---|---|---|---|---|---|
| libarchive + xz + zstd + lz4 (+ lzo2) | 3.8.10, 5.8.4, 1.5.7, 1.10.0, 2.10 | BSD-2-Clause; 0BSD; BSD-3-Clause; BSD-2-Clause; **GPL-2.0-or-later** (lzo2, compatible with GPL-3.0-or-later) | **1.28–1.41 MB** stripped, all readers + writers + disk I/O | ≈ 0.6 (E) | budgeted in 10 §9 (1.5–2 MB): **0 delta**. Dropping lzo saves 60–80 KB | O [A§11] |
| libxml2 for XAR | system 2.9.13 | MIT (system) | 0 | 0 | or bundle expat (MIT, ≈ 0.2 MB, E) if the system copy goes away | O [A§0, §10.2] |
| **7zz** (no RAR codecs) | 26.04 | LGPL-2.1-or-later AND BSD-3-Clause AND BSD-2-Clause | **2.61 MB** stripped | **1.23 MB** | **new**; gate OWN-ARC-2 + size gate OWN-SIZE-1 (NFR-24 is already at ≈ 70.2–71.6 MB) | O [B§1, §2] |
| AppleArchive, Compression | macOS 26 SDK | system | 0 | 0 | — | O [C§1; X-4] |
| `diskutil image`, `hdiutil`, `ditto` | system | system | 0 | 0 | — | O [C§2] |
| EngineArchive + Peek UI + policy (Swift) | ours | GPL-3.0-or-later | 0.3–0.6 MB (E) | — | inside 10 §9's Swift row | E |
| **Total delta** | | | **+0** (no 7zz) / **+2.6 MB** | **+0 / +1.2 MB** | | |

> [challenge] Size arithmetic checked. The 1.28–1.41 MB LA figure is a whole executable with xz/zstd/lz4/lzo linked statically (`otool -L` shows only system dylibs), so the 10 §9 row (1.5 / 1.8 / 2 MB) holds with ≈ 0.1–0.2 MB to spare. Swift glue and Peek UI are E. With 7zz the expected app is ≈ **72.8–74.2 MB** (NFR-24's 70.2–71.6 + 2.6). That's above the 70 MB target and below the 85 MB hard gate, and JPEG XL (+2.5–3.3) competes for the same headroom. So OWN-ARC-2 and OWN-SIZE-1 are one decision. The 7zz figure is `strip -x`, before signing (≈ +20–40 KB for the code signature, E).

Obligations for 7zz (LGPL-2.1 §4): host `7z2604-src.tar.xz` (sha256 `9691944c…34f6`) plus our build script and flags in the GPL source bundle (10 §10.3); ship 7-Zip's `License.txt` in `Resources/Licenses/7-Zip.txt` and About; SBOM entry; credit "7-Zip by Igor Pavlov" without branding features "7-Zip"; CI asserts `7zz i` lists no `Rar1/2/3/5` codec and the build log has `DISABLE_RAR_COMPRESS=1` [B§2.2–2.3]. libarchive: BSD notices in Acknowledgements.

> [challenge] Licence corrections (INFERRED, not legal advice; the facts are OBSERVED in CH-2):
> - **Don't publish the unmodified upstream tarball.** It contains `CPP/7zip/Compress/Rar*` and `DOC/unRarLicense.txt`, which is exactly the unRAR source that 10 §10.2 bans ("unRAR source or binary"). LGPL §4 only requires the source of what we ship. Publish a **pruned** tarball (Debian `+dfsg` style: `Files-Excluded: CPP/7zip/Compress/Rar*`), with the upstream hash, the exclusion list and our build script. The pruned tree builds with `DISABLE_RAR_COMPRESS=1` (rc 0) into a 2,908,160-byte arm64 binary with minos 26.0, the same size as probe B's build, which proves it is the complete corresponding source.
> - **What stays in the binary is plain LGPL.** The link line has `RarHandler.o`, `Rar5Handler.o` (`Archive/Rar`) and `Rar20Crypto/RarAes/Rar5Aes.o` (`Crypto`). `License.txt` restricts only `CPP/7zip/Compress/Rar*`, and none of those objects are linked. The binary lists RAR, refuses to decode it ("Unsupported Method"), and can't create it (`E_NOTIMPL` for `-trar` and `-trar5`).
> - **The CI check as written can't work.** make doesn't echo `DISABLE_RAR_COMPRESS=1`, so the log never contains it (0 hits in `build-norarcomp-26.log`). Assert instead: (1) the source tree has no `CPP/7zip/Compress/Rar*`; (2) the final link line has no `Rar[1-5]Decoder.o`, `Rar3Vm.o` or `RarCodecsRegister.o`; (3) the Codecs section of `7zz i` has no `Rar` line.
> - **Aggregation reasoning holds.** The helper is exec'd with argv/stdin and its text output is parsed, so it's a separate program (GPLv3 §5, FSF FAQ). Even if it were treated as one work, LGPL-2.1+ upgrades to GPL. Notarization doesn't affect licences. It has **not** been tested with this helper (AR-S1); Keka shipping 7-Zip notarized is precedent, not proof.
> - **New licence row for 10 §10.** lzo2 2.10 is **GPL-2.0-or-later**, linked statically into ZivletEngines. It is compatible, but it's a new dependency that 10 §9/§10 doesn't list (only libarchive + xz/zstd/lz4). It costs 60–80 KB, and `.lzo` is rare on Macs. Recommendation: drop lzo (no `tar.lzo`/`.lzo` create or read) unless the owner wants it (**OWN-ARC-11**).
> - XAR depends on the **system** `libxml2.2.dylib` (verified with `otool -L`). That's fine on 26/27; the expat fallback stays the plan if Apple removes it.
**Banned (CI fails):** unRAR source or binary, the official full `7zz` (it contains unRAR-restricted code), RARLAB `rar`, and the `rars` crate (its writer was built with help from disassembled RAR binaries, HIGH risk [C§4.3]).

---

## 8. Catalog changes and the RAR decision

### 8.1 Against the 9 parity pairs

The parity table (10 §4.12: zip → tar, gz; tar → zip, gz; gz → zip, tar; rar → zip, tar, gz) is unchanged: same order, the `gz` id keeps covering `.tar.gz`, `.tgz` and plain `.gz`, the label stays **GZIP** and the target still writes `.tar.gz`. Everything new goes into `Catalog.extras` (10 §4.14), so `count == 275` keeps passing.

New `FormatID`s (role in brackets): `sevenZ`, `tbz2`, `txz`, `tzst`, `tlz4`, `tlz`, `tlzma`, `taz`, `tlzo`, `cpio`, `xar`, `iso`, `wim`, `aar`, `dmg` (both); `cab`, `lha`, `arj`, `aea` (input; AEA is produced through AAR + password); single-stream `bz2`, `xz`, `zst`, `lz4`, `lzip`, `lzma`, `compressZ`, `br`, `lzo` (both, via the sheet). The sniffer gains the standard signatures: 7z `37 7A BC AF 27 1C`, xz `FD 37 7A 58 5A 00`, bzip2 `BZh`, zstd `28 B5 2F FD`, lz4 `04 22 4D 18`, lzip `LZIP`, compress `1F 9D`, lzop `89 4C 5A 4F`, cpio `070701/070707`/`C7 71`, xar `xar!`, ISO `CD001` at 0x8001, CAB `MSCF`, LHA `-lh?-` at 2, ARJ `60 EA`, WIM `MSWIM`, RAR5 `Rar!\x1A\x07\x01\x00`, encrypted DMG `encrcdsa`, UDIF `koly` 512 bytes from the end, AAR `AA01` raw or `pbz[e x 4 z]` compressed, AEA `AEA1` (OBSERVED for the Apple ones, X-5). Brotli has no signature: `.br` is accepted by extension and must decode, or it is refused.

| Set | Sources | Targets | Pairs | New vs the parity pairs |
|---|---|---|---|---|
| **Default visible** | 17: zip, tar, gz, rar, 7z, tbz2, txz, tzst, iso, cab, lha, aar, aea, dmg + single bz2, xz, zst | 9: zip, tar, gz (GZIP), 7z, txz, tzst, tbz2, dmg, aar | 17 × 9 − 9 = **144** | **135** |
| **Advanced** (sheet, Settings, CLI, App Intents) | + 15: tlz4, tlz, tlzma, taz, tlzo, cpio, xar, arj, wim + single lz4, lzip, lzma, compressZ, br, lzo | + 9: iso, tlz4, tlz, tlzma, taz, tlzo, cpio, xar, wim | 32 × 18 − 18 = 558 total, of which **414** advanced | 414 |
| **Operations that are not pairs** | create from any selection into 18 container formats; compress one file into 10 single-stream formats; extract every readable kind (~45 extensions incl. "All formats"); peek; test; lock/unlock (zip, 7z, dmg, aar → aea); split; rejoin | | | 6 operations |

The 17 roadmap's P2-149 target list (zip, 7z, tar, tar.gz, tar.xz, tar.zst, tar.bz2) is the default set minus DMG and AAR. Adding those two is OWN-ARC-4; without them the default set is 17 × 7 − 7 = 112 pairs (103 new).

CI: `@Test(arguments: Catalog.extras)` requires every extra to resolve an engine on a clean macOS 26 VM, or to be marked `requiresOptionalEngine(.sevenZip)` (7z AES, WIM, ARJ, RPM, ~~UDF,~~ disk images).

> [challenge] Pair arithmetic checked: 17 × 9 − 9 = 144 (135 new) and 32 × 18 − 18 = 558 (414 advanced) are right. "Resolves an engine" isn't evidence, though. Of the 144 default pairs, the ones with a streamed or staged round trip on this Mac are the 11 LA sources (zip, tar, gz, 7z, tbz2, txz, tzst, rar, cab, lha, iso) × the 7 LA targets (CH-3), any → AAR for 5 sources, and folder → DMG (CH-4, CH-5). **Untested default pairs:** the single-stream sources bz2/xz/zst → anything (the `raw` path), aea → anything except a folder, dmg → anything (7Z extract was only checked against a folder), and dmg/aar as targets from most sources. AR-24 must run every pair, not every format. If OWN-ARC-11 drops lzo, the advanced set becomes 30 × 17 − 17 = 493 total (349 advanced).

### 8.2 RAR creation: decision and risk

**Decision: no RAR creation in any form (OWN-ARC-1, confirm).** RAR stays a source in every table; the format sheet row says: "RAR: open and convert from. Creating RAR files needs WinRAR's paid tool, so Zivlet makes 7z (smaller) or ZIP (opens everywhere) instead." "Ask in plain words: make a rar" maps to 7Z with that sentence [C§4.4].

| Option | Legal risk | Product risk | Verdict |
|---|---|---|---|
| A. Read-only RAR via LA (current) | none | low | **ship** |
| B. "Use my own RAR": detect a user-installed, user-licensed `rar` CLI and run it as a separate process; never bundled or downloaded by us (BetterZip model) | low | medium (trial nags, support, version drift) | defer to 1.x, only if the owner asks (AR-B2) |
| C. Clean-room store-only RAR5 writer from the public technote | low to medium (anyone who has read unRAR source is bound by "cannot be used to develop a RAR compatible archiver"; trademark; takedown letters) | high: no size gain at all ("I made a RAR and nothing got smaller"), conformance matrix, format drift | reject |
| D. Writer with RAR compression or encryption | medium to high (the technote omits the key derivation and algorithms; they live only in unRAR) | high | reject |
| E. Adopt `rars` or anything unRAR-derived | **high** | high | reject; do not read its writer code |

[challenge] Re-confirmed on the pruned build: `7zz a -trar` and `-trar5` give `E_NOTIMPL`, and RAR5 data gives "Unsupported Method" (CH-2). The risk ranking stands. One correction to option C's wording: the unRAR licence restricts *using the unRAR source*, not people who have read it. The real exposure is proving a clean room, plus the trademark and takedown cost, so C stays rejected on product grounds (a stored RAR is bigger than its input) more than legal ones. Parity note: if the reference app publicly offers RAR creation, leaving it out is a parity deviation and needs its own O-16 row.

Encrypted RAR **extraction** is a separate question with no shippable answer today: unRAR is banned (10 §10.2); the RAR-less 7zz lists header-encrypted RAR5 with a password but extracts only stored entries [B§3.5]. Clean paths, all backlog AR-B1 **[OWNER]**: a `unar`/XADMaster probe (LGPL-2.1, Debian main; provenance unverified), or adding RAR5/RAR3 AES decryption to libarchive's BSD readers from the public spec and upstreaming it (high effort, best long-term).

---

## 9. Phase placement and tasks

### 9.1 Waves (aligned with 17's release plan)

| Wave | Release | Archive scope |
|---|---|---|
| 2A | beta 0.5 | LA vendor build v2, ArchivePolicy, extract every LA format (incl. single-stream, multi-part, smart folder, encodings), hostile corpus. ZIP lock/unlock stays P2-110/111 (17b-lock.md). |
| 2C | beta 0.7 | 7zz helper (if OWN-ARC-2), creation in all formats with the sheet, wheel slices, Peek, conversion, extras catalog, AAR/AEA, DMG, Brotli, split, 7z AES, TEST, nightly matrix |
| 3 | 1.0 | ISO creation via makehybrid, "All formats" readers behind consent, CLI verbs |
| Backlog | 1.x | encrypted RAR path, "use my own rar", merge/re-pack, Finder Quick Look listing |

### 9.2 Task rows (05-task-list format; sizes are ESTIMATES)

| ID | Title | Area | Deps | Size | Acceptance | Satisfies |
|---|---|---|---|---|---|---|
| AR-S1 | 7zz helper spike | Spike | P0-37 | S | RAR-less 26.04 build, minos 26.0, hardened runtime, Team ID; notarytool submission of a bundle containing it passes; stdin password harness (X-1 rules) runs on a 26.x VM; `ps` shows no password | FR-131, C11 **[OWNER][HW]** |
| AR-S2 | ZIP name-encoding spike | Spike | AR-01 | S | [challenge] `hdrcharset` works per archive (CH-10), so the open question is only raw-bytes-per-entry versus a per-archive option. Prefer raw bytes plus Swift decoding. Decide how to get raw name bytes through the LA API (`zip:hdrcharset` via `archive_read_set_options`, or raw bytes); the fixture generator must write unflagged names byte by byte (Python `zipfile` sets the UTF-8 flag). Detector picks the right code page on ≥ 95 % of a 200-file CP932/936/949/866/1251 corpus with 0 false positives on CP437 | FR-19 |
| AR-S3 | macOS 26.0 re-run | Spike | P0-34 | S | On a 26.0 VM: `diskutil image create from` exists (else hdiutil path), Compression Brotli encode works, AppleArchive lzfse/lzma round trip, LA NFC patch, X-1…X-5 reproduce | G-0 **[HW]** |
| AR-S4 | Recipient compatibility | Spike | AR-12 | S | Archive Utility GUI on AES-ZIP, `.zip.001`, AES 7z, `.aea`, `.tar.zst`; Windows 11 Explorer on UTF-8 ZIP, AES-ZIP, 7z, tar.gz; results feed the §3.1 hints | FR-127 **[QA][HW]** |
| AR-S5 | DMG in user space | Spike | AR-10 | S | 7zz extracts APFS and HFS+ DMGs with content, modes, symlinks and xattrs equal to attach + `ditto`; if equal, DMG extract of unencrypted images moves off mounting. [challenge] APFS ULFO already passes for content, symlink and +x with `-tapfs.dmg -sns-`; xattrs are lost (CH-5). Remaining: HFS+, multi-partition, SLA images; decide whether losing xattrs is acceptable; UDF-only ISOs (no reader, CH-8) | — |
| AR-01 | libarchive vendor build v2 | Vendor | P2-19 | M | Static arm64/26.0 build with xz, zstd, lz4, lzo; reader allow-list compiled in; xar on (B-1 fix: build gate checks `libxml2/` in the version string plus a xar round trip); NFC-write patch for zip/7z headers (= P2-113); `setlocale(LC_CTYPE,"UTF-8")` in worker start; ≤ 1.6 MB stripped | FR-07, FR-19 |
| AR-02 | ArchivePolicy pure core [TDD] | Core | P0-02 | M | Pure `decide(entry, root, budget) -> EntryDecision` covering §6.1 (traversal, drive letters, backslash, Cc/bidi, component and path length, symlink and hardlink containment, node types, mode mask, xattr filter, case-folded NFC collisions, budget and ratio); property tests with ≥ 10,000 generated entries; 100 % branch coverage | FR-19 |
| AR-03 | Archive formats and sniffer | Core | P0-10, P0-11 | M | §8.1 `FormatID`s, compound and volume names, signatures (UDIF tail read), `.br` by extension; every new format has a byte fixture; parity ids and labels unchanged | FR-07 |
| AR-04 | OutputNamer archive cases | Core | P0-16, OWN-ARC-6 | S | §3.3 table as goldens: create (folder, file, many, per item), convert, single-stream both ways, split, peek; compound stripping list; `.Z` rule per the owner decision | FR-11 |
| AR-05 | Hardened extract for every LA format | EngineArchive | AR-01, AR-02, P2-41 | L | Staging + RENAME_EXCL; LA secure flags + ArchivePolicy; `__MACOSX` folding with filtered MAC_METADATA (X-3); smart folder; single-stream raw path; H-4 zero-entry rule; password callback (never prompts); quarantine copied; progress and cancel; every positive LA fixture in [A§7.1] extracts identically | FR-128, FR-12, FR-19 |
| AR-06 | Multi-part read | EngineArchive | AR-05 | M | [challenge] `.tar.*.001` sets do **not** open through `archive_read_open_filenames` (tar, tar.gz, tar.xz and tar.zst all fail at the first boundary, at any split size, CH-7). Use our own `archive_read_open2` callback that streams the parts in order, or 7Z `-tsplit`; zip/7z/RAR keep `open_filenames`. Any part of `.partN.rar`, `.rar/.r00`, `.7z.001`, `.zip.001`, `.z01+.zip`, `.tar.*.001` opens the whole set; siblings gathered only from the same folder by exact pattern and listed on the card; missing part → `missingVolume("…part04.rar")`; all [A§7.4] sets pass | FR-128 |
| AR-07 | Name encoding | EngineArchive, UI | AR-S2, AR-05 | M | §6.2 rules; Peek menu re-lists in ≤ 200 ms for 10,000 entries; extracted names UTF-8; fixtures for every row of §6.2 | FR-19 |
| AR-08 | Hostile archive corpus v2 | QA | AR-05 | M | Extends I-A1/S-A1 with every §6.1 test column (incl. FIFO, device, hardlink escape, case collision, bidi names, 200,000 entries, 42.zip, overlapping zip, RAR4 241 MB prompt, mtree text, UDF, `.br` junk, truncated volumes): all contained, nothing written outside staging, worker never crashes the app | FR-19, I-A1 |
| AR-10 | 7zz helper vendor | Vendor | AR-S1, OWN-ARC-2 | M | [challenge] Build from a **pruned** source tarball (no `CPP/7zip/Compress/Rar*`, no `DOC/unRarLicense.txt`), which is the tarball we publish; CI checks per §7 [challenge]. Reproducible build script and pinned source hash; `Contents/Helpers/7zz` signed individually; helper integrity check (10 §8.9); CI asserts no RAR codecs; licence text, source bundle and SBOM entries; size ≤ 2.7 MB | FR-131, FR-23 **[OWNER]** |
| AR-11 | SevenZipRunner | EngineArchive | AR-10, P2-01 | M | Pure argv builder [TDD] (`-t`, `-snl`, progress flags, `-ms=64m`, memory caps) with goldens; stdin passwords only; `-slt` parser; exit-code + message mapping (wrongPassword, missingVolume, unsupportedMethod); staging watchdog kills the process group at the byte cap; zero-length partials removed | FR-131, NFR-21 |
| AR-12 | Archive creation engine | EngineArchive | AR-01, AR-02, AR-11 | L | All §1.2/§1.3 create cells with their engines and the §3.1 level map; read_disk physical, no MAC_COPYFILE, no mount traversal; clutter and xattr filter; owner names cleared; NFC names; hardlinks resolved for zip/7z; write_header checked; store heuristic; one per item; every output read back by an independent reader in CI (7zz, unzip, ditto, Python, `aa`, hdiutil) | FR-127 |
| AR-13 | ARCHIVE… / CONVERT… sheet | UI | P2-30, P2-101, AR-12 | M | §3.1 rows with per-format enabling and hints; level speed estimate; password rules (ZIP AES/ZipCrypto, 7z hide names, DMG, AEA 20-byte rule); split presets; remembered per format; XCUITest for each format group | FR-127, FR-96 |
| AR-14 | Wheel slices and Settings | WheelCore, Core, UI | AR-03, P2-100 | M | §2 tables as data; Actions ZIP/7Z/ARCHIVE…; archive Tools EXTRACT/PEEK/LOCK · UNLOCK/CONVERT…/TEST; Convert ≤ 9 default targets; Settings › Archives "Show in wheel" with the FR-90 lint; volume-set hub label; frame-1 slot set stable (FR-18) | FR-90, FR-93, FR-07 |
| AR-15 | Peek window | UI, EngineArchive | AR-05, AR-11 | L | §4: streamed listing, outline, search, sort, Space Quick Look via staging, Extract Selected, drag-out promises, nested open (depth 3), inline policy warnings, password-first for header-encrypted, 100,000 cap, VoiceOver; list 1,800-entry zip ≤ 0.3 s end to end | FR-129 |
| AR-16 | Archive → archive conversion | EngineArchive | AR-12 | L | §5.1 methods; §5.2 preservation (tests per property); §5.3 encrypted-source rules incl. "keep password" default and the unprotected-target confirm; fail-closed per-entry report; limits on streamed bytes; quarantine copied | FR-130 |
| AR-17 | Catalog extras | Core | AR-03, AR-16 | M | 144 default + 414 advanced extras in `Catalog.extras`; 275 parity test untouched; every extra resolves on a clean 26 VM or is `requiresOptionalEngine(.sevenZip)` | FR-07, FR-08 |
| AR-18 | Split volumes and rejoin | EngineArchive | AR-11, AR-12 | S | 7Z `-v` and LA+S for zip/7z/tar.\*; sizes exact; `7zz t` and LA `open_filenames` both pass; "rejoin" = Convert on the set | FR-127 |
| AR-19 | 7z AES and hidden names | EngineArchive | AR-11, P2-101 | S | Create with `-mhe=on`; extract/peek encrypted 7z; Unicode password round trip; wrong password → sheet shake; names not findable in the raw file | FR-131 |
| AR-20 | Apple Archive and AEA | EngineArchive | AR-02 | M | AF create/extract/peek; lzfse default, lzma Smallest with 256 KiB blocks; lzraven hidden and only `#available(macOS 27)`; AEA passphrase rule with Suggest and "use 7Z"; absolute-symlink policy; LA ↔ AF streaming bridge | FR-127, FR-130 |
| AR-21 | Disk images | EngineArchive | AR-02, AR-11 | M | Create ULFO/ULMO and AES-256 via `diskutil image` with hdiutil fallback; extract with the §6.1 mount rules incl. the launch sweep; peek via 7Z; replaces 17 P3-105 | FR-100, FR-127 |
| AR-22 | Single-stream formats and Brotli | EngineArchive | AR-05 | S | Compress and decompress all ten §1.3 formats; Brotli via Compression (X-4); derived names; `.br` that doesn't decode → refused | FR-127, FR-128 |
| AR-23 | TEST (integrity) | EngineArchive | AR-05, AR-11 | S | Reads all data with CRC/BLAKE2 checks, writes nothing; card "OK, 1,803 items" or the first bad entry; truncated fixtures fail | FR-09 |
| AR-24 | Archive matrix nightly | QA | AR-12…AR-23 | M | Every cell of §1.2/§1.3 runs on a clean 26.x VM; outputs checked by an independent reader; results published as a table in the release notes | FR-07 **[HW]** |
| AR-30 | ISO creation | EngineArchive | AR-12 | S | `hdiutil makehybrid -iso -joliet ~~-udf~~` from staging; depth/path pre-check; LA path only for shallow trees, never `!limit-depth` (B-3 segfault). [challenge] makehybrid stores symlinks with empty targets and its UDF links are unreadable (CH-8): resolve links to copies with a report line, drop `-udf`, and add a symlink round-trip test | FR-127 |
| AR-31 | "All formats" readers | EngineArchive, UI | AR-11 | M | WIM, ARJ, RPM, MSI/CHM/NSIS and disk images via 7Z, only after the explicit "Open disk image / All formats" action with a one-time note; `-t` pinned per sniffed type | FR-128, FR-19 |
| AR-32 | CLI archive verbs | zivlet CLI | P3-108, AR-16 | S | `zivlet archive` `create`/`extract`/`list`/`convert`/`test` with `--format --level --split --password-stdin`; exit codes per P3-108 | FR-136 |
| AR-B1 | Encrypted RAR path | Spike | — | M | unar/XADMaster probe (licence provenance, RAR5 AES, size) or a libarchive RAR AES upstream plan; owner decides | **[OWNER]** |
| AR-B2 | "Use my own rar" | EngineArchive | AR-12 | M | Only if the owner asks: detect a user-installed `rar`, never bundle or download it | OWN-ARC-1 **[OWNER]** |
| AR-B3 | Merge archives; re-pack same format | EngineArchive | AR-16 | S | Several archives → one; zip → zip Smallest | — |
| AR-B4 | Finder Quick Look listing | App | AR-15 | M | QL preview extension listing archive contents in Finder | — |

Mapping to 17's rows: AR-05 extends P2-41; AR-12/13/14 replace P2-147; AR-15 replaces P2-148; AR-16/17 replace P2-149; AR-10/11/19 replace P3-113 (moved from P3 to 2C because C11 is resolved); AR-21 replaces P3-105; AR-01 absorbs P2-113.

---

## 10. Owner decisions and risks

| ID | Decision | Recommendation |
|---|---|---|
| OWN-ARC-1 | RAR creation | **No** (option A); B only on request |
| OWN-ARC-2 | Ship the RAR-less 7zz helper (+2.6 MB / +1.2 MB DMG) | **Yes, in 2C.** The argv objection is resolved (X-1). Needs OWN-SIZE-1 because NFR-24 is already at the 70 MB line |
| OWN-ARC-3 | Smart folder on extract (deviates from the `<base> Extracted` parity name) | Yes, default on, toggle in Settings |
| OWN-ARC-4 | DMG and AAR on the default Convert wheel | Yes (≤ 9 slices) |
| OWN-ARC-5 | Actions wheel at 11 (ZIP, 7Z, ARCHIVE… added; 17 had 9 + four extras) | Yes |
| OWN-ARC-6 | Allow `.Z` / `.tar.Z` despite the lower-case extension rule | Yes |
| OWN-ARC-7 | Encrypted RAR | Stay unsupported; fund AR-B1 only on demand |
| OWN-ARC-8 [challenge] | Keep in-root relative symlinks on extract (rewords 03b §9 "no symlinks" to "no escaping symlinks") | Yes, for parity with Archive Utility; the corpus gains link-to-escaping-link tests |
| OWN-ARC-9 [challenge] | Actions LOCK on a single supported archive: wrap it (`data Locked.zip` containing `data.zip`) or re-encrypt it like Tools LOCK (same output name today) | Re-encrypt, so one name means one thing |
| OWN-ARC-10 [challenge] | Labels: wheel GZIP (parity) versus sheet TAR.GZ; single-stream sources get single-stream Convert targets | Keep GZIP on the wheel, "TAR.GZ (GZIP)" in the sheet; GZ/ZST/XZ/BZ2 on the wheel for single-stream sources |
| OWN-ARC-11 [challenge] | Keep `.lzo` (adds lzo2, GPL-2.0-or-later, a dependency 10 §10 doesn't list, 60–80 KB) | Drop it (rare on Macs; YAGNI) |

| Risk | Likelihood | Mitigation |
|---|---|---|
| A parser CVE in LA or 7zz | medium | worker/helper isolation, reader allow-list, `-t` pinning, 7-day bump policy, nightly hostile corpus |
| AES-ZIP recipients can't open it (Windows Explorer, `unzip`, `ditto` fail) [A§6.2; B§3.4] | high | sheet note, ZipCrypto toggle, 7Z suggestion, AR-S4 results in copy |
| Brotli encoder or `diskutil image` missing on 26.0 | low | AR-S3; hide `.br` creation / use hdiutil |
| CJK ZIP names mis-decoded | medium | AR-S2 detector + manual menu |
| Size over 70 MB with 7zz | high | OWN-SIZE-1; 7zz is optional at build time and every 7Z cell has an LA fallback or is marked optional |
| DMG attach hangs or leaks mounts | low | §6.1 rules, stdin always, launch sweep |
| LA writer bugs (ISO segfault B-3, shardump B-2, xar build B-1) | known | ISO via makehybrid, shar never offered, build gate; report upstream |
| [challenge] makehybrid breaks symlinks; UDF unreadable by both engines | known (CH-8) | resolve links before makehybrid; UDF → unsupported or mount path |
| [challenge] LA `open_filenames` fails on split tar.\* sets | known (CH-7) | own concatenating callback; report upstream with the CH-7 repro |
| [challenge] Memory bombs (declared LZMA/xz dictionary) | unknown | crafted fixture in AR-08; worker and helper RSS watchdog |

---

## 11. Experiments run for this document (macOS 27.0; local prototype folders, not published)

- **X-1 7zz passwords via stdin** (`exp.lZCI/`, RAR-less build `tools/bin/7zz-norarcomp-min26`). `printf 'pässwörd\n' | 7zz a -t7z -mhe=on -p …` created `LZMA2:12 7zAES:19` with a Unicode password and no prompt echo; one stdin line is enough when stdin is not a tty. `7zz t`/`x` with **no `-p`** and the password on stdin: "Everything is Ok", content identical. `7zz x -p` (empty value) with stdin → "Can't open as archive", because `-p` alone sets an empty password. Wrong password → exit 2, "Cannot open encrypted archive. Wrong password?". No stdin → "Break signaled", exit 255. So passwords never need argv.
- **X-2 ZIP name encodings** (`exp.0k0K/`, bsdtar 3.8.10 under `LC_ALL=en_US.UTF-8`). Python-written ZIP without the UTF-8 flag: `Äpfel-ü.txt` (CP437 bytes) listed correctly; CP932 bytes for `テスト.txt` listed as `âeâXâg.txt`; a flagged `Δ-utf8.txt` correct. `--options hdrcharset=CP932`, `zip:hdrcharset=CP932` and `zip:hdrcharset=SHIFT_JIS` (bsdtar CLI) and 7zz `-mcp=932` all left the CP932 name unchanged. A `ditto` ZIP (unflagged UTF-8 `テスト-café.txt`) listed correctly under a UTF-8 locale and as octal escapes under `LC_ALL=C`. [challenge] **Invalid as evidence for CP437/CP932:** `exp.0k0K/names.zip` has flag 0x800 on all three entries (Python `zipfile` flags every non-ASCII name), so nothing unflagged was tested. CH-10 repeats it with byte-patched unflagged names: LA passes raw bytes by default, `hdrcharset=CP932`/`GBK` decode correctly, and 7zz mangles the names. The `ditto` result stands.
- **X-3 `__MACOSX` folding** (`exp.0k0K/`). A `ditto -c -k --sequesterRsrc` ZIP (`f/tagged.txt` + `__MACOSX/f/._tagged.txt`, xattr `com.example.tag`) lists in bsdtar 3.8.10 as two entries with no `__MACOSX`. Extract with `--mac-metadata` restored the xattr; with `--xattrs` or `--no-mac-metadata` the xattr was dropped; no `__MACOSX` folder in any case. `--options zip:mac-ext` is rejected by the CLI.
- **X-4 Brotli via Compression** (`exp.trLf/`, Swift stream API, built with `-target arm64-apple-macos26.0`). Decoding `brotli -q 11` output of the 8,052,861-byte C corpus: byte-identical. Encoding: 1,337,657 B (0.166; `brotli -q 11` makes 895,634 B, 0.111), decoded by Homebrew `brotli` byte-identically. compression.h: "We implement Brotli level 2 encoder only… decoder supports any compression level"; `COMPRESSION_BROTLI` "available starting macOS 12.0".
- **X-5 Apple magic bytes** (`exp.trLf/`). `aa archive` default output starts `pbze` (lzfse block stream; `pbzx` is the lzma variant also used by `.pkg` payloads), `-a raw` starts `AA01`, an `.aea` from probe C starts `AEA1`.

---

## 12. RECOMMENDATION

**Choice.**
1. **libarchive 3.8.10 stays the single in-process engine** for reading every legitimate archive and stream format we list, for writing ZIP (AES-256), tar + all filters, cpio, XAR and single-stream files, and for streaming any → any conversion, wrapped in a pure `ArchivePolicy` that enforces the §6 controls on top of the library's opt-in safety flags.
2. **Ship 7-Zip 26.04 built without RAR codecs as a signed helper in Phase 2C** (OWN-ARC-2), for 7z creation, 7z AES with hidden names, split volumes, Deflate64/UDF and the "All formats" readers. Passwords go through stdin (X-1), which closes the only policy objection. Every 7Z cell has an LA fallback or is marked optional, so the app degrades cleanly if the gate stays shut.
3. **Use Apple's own engines where they are the only or the best answer:** AppleArchive for `.aar`/`.aea`, Compression for `.br`, `diskutil image`/`hdiutil` for DMG and ISO creation and encrypted-DMG extraction. All cost 0 MB.
4. **Never write RAR; never ship unRAR.** Encrypted RAR stays unsupported, with honest copy.
5. **UX:** ZIP, 7Z and ARCHIVE… on the Actions wheel; EXTRACT, PEEK, LOCK · UNLOCK, CONVERT…, TEST for archives; ≤ 9 Convert targets; every other format one tap away in the sheet, never a 13th slice. Smart extraction, never overwrite, Mac clutter stripped, Finder-compatible names.

**Rationale.** The three probes show that libarchive alone already covers most of the matrix (every LA cell in §1) with no temp files, and the measured 1.3–1.4 MB fits the existing budget. 7-Zip fills exactly the gaps users notice (password-protected 7z, split files, odd Windows formats) for 2.6 MB under licences compatible with GPL-3.0. Apple's frameworks cover the Mac-only formats for free. The result goes well beyond the 9 parity pairs on breadth (≈ 550 extra pairs), safety (policy layer, bomb prompt, encoding handling) and honesty (no RAR, no unRAR).

**Risks.** Parser CVEs (isolation, allow-lists, bump policy); AES-ZIP interoperability (copy and a 7Z suggestion); size pressure from 7zz (OWN-SIZE-1); CJK names (AR-S2); results taken on macOS 27 (AR-S3).

[challenge] **The recommendation stands, with these amendments:** (1) publish a pruned 7-Zip source and build from it; (2) read split tar.\* sets with our own callback; (3) pin DMG listings as a chain with `-sns-`; (4) ISO creation resolves symlinks, and UDF is not claimed as readable; (5) ZIP names are decoded from raw bytes in Swift; (6) AR-24 tests pairs, not formats, and the untested cells in §1.2 and §8.1 stay labelled until it does. New owner rows: OWN-ARC-8…11.

**Fallback.** If 7zz is not approved: LA writes 7z without encryption, LA+S splits, LOCK stays AES-ZIP and AEA/DMG, and Deflate64/UDF/WIM/ARJ/RPM/disk images show "needs an engine that isn't installed" (03a §2.6). If AppleArchive or Brotli behave differently on 26.0, those cells are hidden by the capability gate (03a §3.5). If libarchive's NFC patch can't be maintained, upstream an option to skip Apple's NFD conversion.

## Sources

Probes: probe reports A (libarchive), B (7-Zip) and C (Apple Archive, DMG, RAR), local and not published (sources listed there: libarchive 3.8.10 release and GPG key, 7-Zip 26.04 release and `DOC/License.txt`, Debian `7zip` copyright, Homebrew `sevenzip.rb`, rarlab.com licence and technote, BetterZip RAR docs, hdiutil man page on 27.0, AppleArchive swiftinterface, AEAContext.h). Repo: 10 §2.1, §4.12, §4.14, §8.9, §9, §10; 13 §6; 03a §2.2, §2.6, §3, §4.3–4.4; 03b §9; 05 §1; [17-feature-roadmap.md](17-feature-roadmap.md) and its cluster reports, [17b-lock.md](17b-lock.md). SDK: `MacOSX27.0.sdk/usr/include/compression.h`.
