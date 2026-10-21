# 18 — Challenge: adversarial review of `18-archives.md`

Date: 2026-10-21. Machine: M2 Pro, macOS 27.0 (26A428). Reviewer scope: every matrix cell against probe evidence, the 7zz licence, RAR creation, security limits, the wheel cap and naming, and size.
Corrections are applied in place in `18-archives.md` with `[challenge]` marks. This file records the evidence and the verdicts.
Work folder: `chal.XrX7/` (local prototype, not published; scripts in `bin/`, never inside the untrusted folders). Python ran only as `python3 -I`. Nothing in the repo was modified, nothing was installed, and nothing was deleted.

Labels: **OBSERVED** (run here), **DOC**, **INFERRED** (not legal advice).

---

## 1. Verdict

The design holds: libarchive as the primary engine, a RAR-less 7zz helper as an option, Apple engines for AAR/AEA/DMG, and no RAR writing. **Six factual errors** would have shipped bugs or a licence problem, plus four product collisions that need owner calls.

| # | Severity | Finding | Evidence | Fix applied |
|---|---|---|---|---|
| 1 | **High (licence)** | §7 says to publish the unmodified `7z2604-src.tar.xz`. That tarball contains `CPP/7zip/Compress/Rar*` and `DOC/unRarLicense.txt`, which is unRAR source, banned by 10 §10.2 | CH-2 | Publish a pruned tarball (Debian `+dfsg` style). The pruned tree builds the identical-size binary |
| 2 | **High (correctness)** | §6.2 and X-2: "LA defaults to CP437" and "hdrcharset=CP932 doesn't work" are both false. X-2's fixture had the UTF-8 flag on every entry | CH-10 | §6.2 rows rewritten. Design: decode raw bytes per entry in Swift |
| 3 | **High (correctness)** | §1.2 and AR-06: split `.tar.*.001` sets "open via LA `open_filenames`". They don't. tar, tar.gz, tar.xz and tar.zst all fail at the first part boundary, at any split size | CH-7 | Our own concatenating `archive_read_open2` callback, or 7Z `-tsplit` (works) |
| 4 | **Medium** | ISO create via `makehybrid -iso -joliet -udf`: symlinks are stored with **empty targets** (LA and 7zz agree), and the UDF part's links fail `readlink` (error 10000) when mounted | CH-8 | Resolve links before makehybrid, drop `-udf`, add a round-trip test |
| 5 | **Medium** | "7Z for UDF": 7zz 26.04 can't open Apple-made UDF ("Unsupported feature"). LA sees 0 entries. Nothing we ship reads UDF-only discs | CH-8 | UDF claims struck. H-4 "unsupported", or a mount path under the DMG rules |
| 6 | **Medium** | DMG peek "7Z with `-t` pinning": `-tdmg` lists partitions only. Files need the chain `-tapfs.dmg` (or `-thfs.dmg`). 7zz extract without `-sns-` writes a junk `name:com.apple.provenance` file beside every file | CH-5 | §4.2, §6.1 SevenZipRunner flags |
| 7 | Medium | §5.1 says "all 9 × 7 pairs tested" (A§8 filled 51/63), and cites B§6 and B§5 as OBSERVED (they are a plan and the security section) | A§8; CH-3 | Evidence corrected. CH-3 adds 300 LA → LA cells |
| 8 | Medium | The CI check "build log has `DISABLE_RAR_COMPRESS=1`" can never pass: make doesn't echo the variable (0 hits in the log) | CH-2 | Replaced with tree, link-line and `7zz i` codec checks |
| 9 | Medium | The matrix implies every cell round-tripped. Single-stream sources, AEA/DMG as sources, ARJ, RPM, multi-cabinet CAB, HFS+ DMG, the LA ↔ AF bridge and all of macOS 26 are untested | §1.2 note | "Untested" labels; AR-24 must test pairs |
| 10 | Low | lzo2 (GPL-2.0-or-later) is a new static dependency not in 10 §9/§10 | A§11 | OWN-ARC-11 (recommend dropping `.lzo`) |

## 2. Checks re-run (CH-n)

All paths are relative to that local work folder. 7zz = the **pruned** build `pruned/CPP/7zip/Bundles/Alone2/b/m_arm64/7zz` (minos 26.0, arm64, 2,908,160 B). LA = a local bsdtar 3.8.10 build (xar-enabled build B).

- **CH-1 Passwords over stdin (re-run of X-1).** `printf 'pässwörd 🙂\n' | 7zz a -t7z -mhe=on -p` → `LZMA2:12 7zAES:19`. Listing with no stdin gives "Break signaled". Listing and extracting with the password on stdin (no `-p`) works, and `diff -r` is identical. Wrong password: exit 2. `grep -a` finds 0 hits for the file name or the content in the raw `.7z`. The RAR4 multi-volume fixture is 189,201 B, which confirms §6.1's "190 KB → 241 MB".
- **CH-2 7zz licence surface.** `DOC/License.txt`: only `CPP/7zip/Compress/Rar*` carries the unRAR restriction. `Arc_gcc.mak`: `DISABLE_RAR_COMPRESS` drops `Rar1/2/3/5Decoder.o`, `Rar3Vm.o` and `RarCodecsRegister.o`, and keeps `RarHandler.o`, `Rar5Handler.o` and `Crypto/Rar*`. The link line of `build-norarcomp-26.log` has 0 restricted objects. `7zz i` Codecs: 0 `Rar` lines. A **pruned** copy of the source (rsync excluding `CPP/7zip/Compress/Rar*` and `DOC/unRarLicense.txt`) builds with `MACOSX_DEPLOYMENT_TARGET=26.0 make -f ../../cmpl_mac_arm64.mak DISABLE_RAR_COMPRESS=1`, rc 0, 2,908,160 B. `-trar` and `-trar5` give `E_NOTIMPL`; RAR5 data gives "Unsupported Method". Signature: ad hoc, linker-signed (must be re-signed, as probe B said).
- **CH-3 Conversion matrix (LA → LA).** `bin/conv.zsh`. 20 sources: our zip, 7z (7zz), pax tar + gzip/bzip2/xz/zstd/lz4/lzip/lzma/compress/lzop, newc cpio, xar, `makehybrid` ISO, and libarchive fixtures RAR4, RAR5, RAR5 with links, CAB, LHA lh6. 15 targets: zip, 7z, pax, 10 filtered paxes, newc, xar, iso9660. Each output was extracted by LA and compared with LA's extraction of the source (sha256, link targets, +x, empty dirs, NFC names: `bin/cmp.py`). **Result: 300 cells, all identical except** (a) → cpio from RAR5-with-links and LHA: directories and symlinks dropped with "Size required", **bsdtar rc 0**; (b) the makehybrid ISO source, whose symlinks are already broken (CH-8). Independent read (7zz for zip/7z/tar/cpio/iso/xar; system gzip/bzip2/xz/zstd/lz4/uncompress + `/usr/bin/tar` for filtered tars): all zip/7z/tar/filtered-tar cells agree (lzip/lzop: no decoder). 7zz disagrees on LA ISO (reads Joliet: symlink becomes an empty file, +x lost), xar (base64 names, known) and cpio made from zip/7z/CAB (a 0-byte entry gets another file's content; `/bin/pax` reads the same file correctly). Raw output: `conv-results.txt`.
- **CH-4 AAR/AEA via staging.** LA extraction of zip, 7z, RAR5-with-links, tar.xz and LHA → `aa archive -a lzfse` → `aa extract`: identical for all 5. AAR → ZIP (LA) → extract: identical. AEA (`-password` file, 28-char passphrase): identical. Magic bytes: `AEA1`, `pbze`. The in-process `ArchiveStream` bridge was **not** exercised.
- **CH-5 DMG.** `diskutil image create from --format ULFO` of the test tree: 1.2 s, rc 0 (C§2.2's "3–5 s minimum" is pessimistic for tiny folders). 7zz listing: `-tdmg` shows 8 partition items; `-tapfs.dmg` shows the files; `-tdmg.apfs` and the `gpt` chains fail; auto-detect works but is banned by the pinning rule. `7zz x` (auto) wrote a `file:com.apple.provenance` side file for **every** file. `7zz x -tapfs.dmg -snld -sns-`: identical content, symlink and +x (xattrs dropped).
- **CH-6 WIM.** `7zz a -twim -snl` then `x -twim -sns-`: identical.
- **CH-7 Split volumes.** Byte-split (`split -b`) at 100,000 / 102,400 / 100,352 / 65,536 B. `archive_read_open_filenames` (probe A's `scripts/mvread`): zip and 7z OK. tar, tar.gz, tar.xz and tar.zst **fail** at the first entry that crosses a part boundary ("Truncated tar archive", 6 of 11 entries), at every size. A single unsplit part reads fine, so the harness is not the cause. `7zz t x.001` passes all five sets (`Volumes = 4`). A 7zz-made `-v100k` zip set reads via LA `open_filenames`.
- **CH-8 ISO/UDF.** `makehybrid -iso -joliet`: the symlink is listed `lrwxr-xr-x … link-a` with no target in LA, and "Symbolic Link = (empty)" in 7zz; LA extracts it as an empty file. `makehybrid -iso -joliet -udf`, mounted read-only (`-nobrowse -mountrandom`, detached afterwards): `ls` on the link gives "Unknown error: 10000". UDF-only image: LA lists 0 entries with rc 0 (H-4), and 7zz `-tudf` says "Unsupported feature". The hybrid image is read by LA through ISO9660 (12 entries).
- **CH-9 Extraction policy (LA defaults, i.e. bsdtar's secure flags).** Tar with `A.txt` + `a.txt` and NFC + NFD `Café.txt`: one file of each pair survives (the second's content), with no message. Hardlink to `/etc/hosts`: `/` stripped, "Hard-link target 'etc/hosts' does not exist". Hardlink with `../../…`: "Path contains '..'". FIFO: **created**. setuid 4755: cleared (non-root).
- **CH-10 ZIP name encodings.** `names.zip` from X-2: flag 0x800 on all entries. New `enc/raw.zip` (`bin/mkcp.py` byte-patches unflagged names: CP932 `テスト.txt`, CP437 `Äpfel-ü.txt`, GBK `中文测试.txt`; flag 0x0). LA default under `en_US.UTF-8`: raw bytes (`\203e\203X\203g.txt`, `\216pfel-\201.txt`). `--options hdrcharset=CP932`: `テスト.txt` correct, and the other two either fail ("cannot be converted… skipping") or decode as the wrong script. `zip:hdrcharset=GBK`: `中文测试.txt` correct. 7zz, with or without `-mcp=932`: names mangled (`eXg.txt`, `pfel-.txt`).

## 3. Topic verdicts

### 3.1 Matrix coverage
After CH-3 to CH-8, the following has a real round trip on this Mac: every LA create cell, LA → LA conversion for 20 sources × 15 targets, any → AAR (5 sources), folder → DMG → 7zz, WIM, split zip/7z/tar.\*, and 7z AES. **Still untested:** ARJ, RPM, multi-cabinet CAB, HFS+/encrypted DMG via 7zz, AEA → non-folder, DMG → archive as a pair, single-stream sources → containers (the `raw` path), the LA ↔ AF in-process bridge, Brotli beyond X-4, and **everything on macOS 26** (AR-S3). These are labelled in §1.2/§8.1.

### 3.2 Licence of bundling 7zz in a GPL-3.0-or-later app
- **Aggregation:** sound. The helper is a separate program (exec, argv/stdin, text output; GPLv3 §5, FSF FAQ). Even merged, LGPL-2.1+ → GPL-2+ → GPL-3 (INFERRED).
- **unRAR restriction:** correctly kept out of the **binary** (CH-2), but the plan to publish the **full** upstream source would redistribute unRAR source. **Fixed:** publish a pruned tarball. It is the complete corresponding source (proven by building from it) and matches Debian's treatment.
- **Notarization:** prerequisites are met (hardened runtime, no entitlements, system dylibs only). Real `notarytool` is still untested (no Developer ID); AR-S1 owns it. Notarization has no licence effect.
- **Obligations:** `License.txt`, SBOM, credit, no "7-Zip" branding: correct. The CI check is replaced (finding 8).

### 3.3 RAR creation risk
The analysis is right and re-confirmed: 7zz can't write RAR (`E_NOTIMPL`), nobody mainstream ships a writer, and `rars` is tainted. One wording fix: the unRAR licence restricts use of the source, not readers of it. One parity note: if the reference app publicly offers RAR creation, leaving it out is a parity deviation and needs an O-16 row.

### 3.4 Security limits
- Confirmed by experiment: case/NFC collisions are silent (control needed), FIFOs get created (control needed), and hardlink escapes are blocked by LA's secure flags (keep our pre-check as a second layer).
- Symlink policy relaxes 03b §9's "No … symlinks" → OWN-ARC-8 (reword to "no escaping symlinks").
- Ratio prompt: deflate maxes out near 1,032:1, so 1,000× barely fires for ZIP bombs. The absolute cap does the work for deflate and overlapping-entry bombs, so test the cap there.
- **Gap:** memory bombs (declared LZMA/xz dictionary up to 4 GB) are not covered by any row. Added to risks and to AR-08.
- 7zz flags: chained DMG type, `-sns-`, keep the default dangerous-link check.
- PEEK on a DMG reaches 7zz's APFS/HFS parsers. A rule was added: PEEK or EXTRACT on a sniffed DMG is the explicit action; nothing implicit invokes them.

### 3.5 Wheel cap and naming
- Caps verified: Actions 11/12, archive Tools 5/12, Convert ≤ 9. Pair counts 144 / 558 / 414 are arithmetically right.
- Collisions: LOCK on one archive gives `data Locked.zip` from two different operations (OWN-ARC-9). GZIP versus TAR.GZ labels, and single-stream Convert → GZIP producing `.tar.gz` (OWN-ARC-10).
- Naming engine: the collision rule must use the compound list (`backup 2.tar.gz`), and split sets need one `NameReserver` claim for all parts (otherwise `Name.7z.001` can sit beside `Name 2.7z.002`).

### 3.6 Size budget
LA's 1.28–1.41 MB includes static xz/zstd/lz4/lzo (verified with `otool -L`), so it fits the 10 §9 row (1.5–2 MB). 7zz adds 2.61 MB stripped (+ signature) → app ≈ 72.8–74.2 MB versus the 70 MB target (85 MB hard gate). OWN-ARC-2 and OWN-SIZE-1 are effectively one decision, and they compete with JPEG XL.

## 4. Owner decisions (ranked)

1. **OWN-ARC-2 + OWN-SIZE-1** — ship the RAR-less 7zz (+2.6 MB, ≈ 73–74 MB app), built and published from a **pruned** source. Recommend yes, as one decision.
2. **OWN-ARC-1** — no RAR creation (confirm). If the reference app publicly offers RAR creation, sign the O-16 deviation.
3. **OWN-ARC-8** — keep in-root relative symlinks (rewords 03b §9). Recommend yes.
4. **OWN-ARC-9** — Actions LOCK on a single archive behaves like Tools LOCK (re-encrypt). Recommend yes.
5. **OWN-ARC-10** — GZIP label kept on the wheel; single-stream sources get single-stream Convert targets. Recommend yes.
6. **OWN-ARC-11** — drop `.lzo` / `tar.lzo` (removes a GPL-2.0+ dependency). Recommend drop.
7. Existing OWN-ARC-3 to 7 unchanged.
