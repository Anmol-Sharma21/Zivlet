# 10g — M4 stream E: fixtures, pair matrix, hostile corpus, hardening, diagnostics, performance

Part of [10-implementation-plan-m4](10-implementation-plan-m4.md). Conventions: index §6. E1–E3 need the vendored
media stage (A3/A4) so fixture hashes and matrix results describe the binary Zivlet ships; with any other ffmpeg
they run but skip hash checks and say so.

---

## Task E1 — Fixture generator (P1-60, D-M4-15)

| Field | Value |
|---|---|
| Goal | `Fixtures/generate.sh [--set small|full] [--out build/fixtures]` deterministically makes **media** with the bundled `ffmpeg` (lavfi `testsrc2`/`sine`, `-fflags +bitexact -flags:v +bitexact -flags:a +bitexact`, fixed `-metadata creation_time=2026-01-01T00:00:00Z`): SDR H.264 MP4/MOV, HDR10 HEVC MOV (VideoToolbox main10 + `hevc_metadata` tags, B5), HLG HEVC, rotated MOV (`-display_rotation 90`), odd 853 × 479, 5.1 FLAC, 24-bit WAV, mono Opus, MP3 with cover (PNG attached pic), MKV with SRT + ASS subtitles and chapters, AVI with PCM, WMV, VP9+Opus WebM, VP9-alpha WebM, GIF with transparency, Ogg Vorbis (libvorbis), audio-only MP4, video without audio; and **images** with a Swift executable target `zivlet-fixtures` (ImageIO + Core Graphics): 8-bit sRGB JPEG/PNG/HEIC/TIFF/AVIF/BMP/WebP(read-only input, made with CWebP), 16-bit P3 PNG/TIFF, alpha PNG/HEIC, APNG (4 frames), HEICS (3 frames), 3-page TIFF, CMYK JPEG, all 8 EXIF orientations, SVG + SVGZ (text written by the script). Writes `build/fixtures/<set>/manifest.sha256`; `--check` compares with the committed `Fixtures/manifest-<set>.sha256` and fails on drift when the vendored `ffmpeg` (by SHA-256 in `Vendor/out/KEY`) is used. Nothing binary is committed; no Git LFS (`git-lfs` is not installed and is not needed when generation is deterministic) |
| 05 rows | P1-60 |
| Sources | 11 §14 item 3 list, 05 P1-60 |

**Files:** create `Fixtures/generate.sh`, `Fixtures/media-recipes.txt` (one recipe per line: name, args),
`Fixtures/manifest-small.sha256`, `Fixtures/manifest-full.sha256`, `Packages/ZivletKit/Sources/zivlet-fixtures/main.swift`
(+ `ImageRecipes.swift`), `Fixtures/tests/test-generate.sh`; modify `Package.swift` (executable target, not gated),
`Makefile` (`fixtures`, `fixtures-check`).

### E1.1 Failing test first

`Fixtures/tests/test-generate.sh`: runs `generate.sh --set small --out <tmp>/a` twice into two directories and
asserts identical manifests (determinism); asserts every recipe in `media-recipes.txt` produced a file that `ffprobe`
opens; asserts `--check` fails after a fixture is modified; asserts that without the vendored ffmpeg `--check` prints
"hash check skipped: not the vendored ffmpeg" and exits 0.

### E1.2–E1.5

RED: script missing. GREEN: `make fixtures-check` → `fixtures OK: small 46 files`. Commit `test(fixtures):
deterministic media and image fixture generator`.

---

## Task E2 — Pair matrix: 153 Phase 1 pairs + 8 SVG pairs (P1-61)

| Field | Value |
|---|---|
| Goal | New test target `ZivletMatrixTests` (depends on `ZivletRuntime`, opt-in via `ZIVLET_MATRIX=subset|full`, default off in `make test`) runs every pair through the real `JobPipeline` (probe → plan → execute → verify → publish into a temp folder) using E1 fixtures, and checks properties: output decodes; dimensions (raster/video), colour space (P3 kept unless Web sRGB), alpha kept where the target supports it, frame count (animated targets), duration within max(0.25 s, 1 %) (D-M3-16), codecs (WebM = VP9 + Opus; AVI = MPEG-4 + MP3; MP4/MOV `AVURLAsset.load(.isPlayable)` true), channel count/sample rate rules (11 §10.1). `subset` = one pair per source format and one per target format (≈ 40 pairs, < 60 s on the dev Mac) for PRs; `full` = all 161 for nightly. A test fails if any catalog pair in the Phase 1 set is `routeUnavailable` with the vendored build (no silent gate passes — the prototype added exactly this assertion and found none) |
| 05 rows | P1-61, M4 exit "153 pairs green" |
| Prototype evidence | With the prototype build: the existing 104 media pairs + 15 smoke cases all green with 0 known issues after the B5 fixture changes; 43 raster pairs already pass in `ImageEngine on real files` |

**Files:** create `Tests/ZivletMatrixTests/MatrixPairs.swift` (pair list from `ConversionCatalog` filtered to the
Phase 1 + SVG set, asserted to be 161 and to contain exactly 49 raster, 8 svg, 56 audio, 42 video, 6 gif),
`MatrixTests.swift`, `PropertyChecks.swift`; modify `Package.swift`, `Makefile` (`matrix`, `matrix-subset`).

### E2.1 Failing test first

```swift
@Suite("Phase 1 pair set (P1-61)")
struct MatrixPairsTests {
    @Test func countsMatchThePhaseOneScopePlusSVG() {
        let pairs = MatrixPairs.all
        #expect(pairs.count == 161)
        #expect(MatrixPairs.count(.raster) == 49 && MatrixPairs.count(.svg) == 8)
        #expect(MatrixPairs.count(.audio) == 56 && MatrixPairs.count(.video) == 42 && MatrixPairs.count(.gif) == 6)
    }
}

@Suite("Pair matrix (opt-in: ZIVLET_MATRIX)", .enabled(if: MatrixEnvironment.isEnabled))
struct MatrixTests {
    @Test(arguments: MatrixEnvironment.pairs)
    func convertsAndHasTheRightProperties(pair: ConversionPair) async throws {
        let rig = try await MatrixRig.shared()
        #expect(await rig.availability(pair) == .available, "\(pair) gated off with the vendored build")
        let output = try await rig.convert(pair)
        try await PropertyChecks.verify(output, pair: pair, source: rig.fixtureInfo(pair.source))
    }
}
```

### E2.2–E2.5

RED: `MatrixPairs` missing; then, with B2/B3 not yet merged, the webp/svg pairs fail `availability` — the expected
RED for the full run. GREEN: `ZIVLET_MATRIX=full make matrix` → `161 test cases passed`. Commit `test(matrix): 161-pair
matrix with property checks (PR subset, nightly full)`.

---

## Task E3 — Hostile media corpus and content sniffing (P1-62, G-8)

| Field | Value |
|---|---|
| Goal | `Fixtures/hostile/generate.sh` makes: HLS playlist named `.mp4` (pointing at `file:///etc/passwd` and at a canary file), ffconcat list named `.mkv` (canary), a lavfi graph string saved as `.mp4`, truncated MP4 (first 4 KB), PNG with a 60,000 × 60,000 IHDR, ZIP renamed `.tiff`, TIFF with 5,000 tiny pages, SVG with an external `href` to the canary and a billion-laughs entity block, SVGZ gzip bomb (80 MB of spaces), WebP declaring 16,383 × 16,383, a symlink named `.png` pointing at the canary, a FIFO named `.wav`. **Content sniffing at admission** (03a §3.2): `ContentSniffer.sniff(first 4 KB)` → `FormatID?` from magic bytes; the sniffed type wins over the extension (card note "This file is really a PNG; converted as PNG." — *new*), unknown or mismatching-and-unsupported content → `unsupportedInput(.contentMismatch)` before any engine opens the file; symlinks and FIFOs are refused by `JobRequestFactory` (`lstat`: regular files only — already required for inputs; add the test). Every corpus file is either refused with user copy or converted safely; for each output, assert the canary's random 32-byte token does not occur in it |
| 05 rows | P1-62, G-8, M4 exit "hostile corpus crash-free" |
| Sources | 05 P1-62, 03a §3.2, 10 §8.9 |

**Files:** create `Fixtures/hostile/generate.sh`, `Sources/ZivletCore/Formats/ContentSniffer.swift` (pure, table of
signatures for every Phase 1 input type + ZIP/HLS/ffconcat/PDF to name refusals), `Tests/ZivletCoreTests/ContentSnifferTests.swift`,
`Tests/ZivletMatrixTests/HostileCorpusTests.swift`; modify `Sources/ZivletRuntime/JobRequestFactory.swift` (sniff),
`Sources/ZivletRuntime/BatchPresentation.swift` (note), `Sources/ZivletCore/Jobs/JobRequest.swift` (`PlanNote.sniffed`).

### E3.1 Failing tests first

```swift
@Suite("Content sniffing (G-8, 03a §3.2)")
struct ContentSnifferTests {
    @Test(arguments: [
        ([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], FormatID.png),
        ([0xFF, 0xD8, 0xFF, 0xE0], .jpg),
        (Array("RIFF\0\0\0\0WEBPVP8 ".utf8), .webp),
        (Array("RIFF\0\0\0\0WAVEfmt ".utf8), .wav),
        ([0, 0, 0, 0x18] + Array("ftypheic".utf8), .heic),
        ([0, 0, 0, 0x1C] + Array("ftypavif".utf8), .avif),
        (Array("fLaC".utf8), .flac),
        (Array("OggS".utf8), .ogg),
        ([0x1A, 0x45, 0xDF, 0xA3], .mkv),
    ] as [([UInt8], FormatID)])
    func knownMagicBytes(bytes: [UInt8], format: FormatID) {
        #expect(ContentSniffer.sniff(Data(bytes + Array(repeating: 0, count: 32))) == format)
    }

    @Test(arguments: ["#EXTM3U\n#EXT-X-VERSION:3\n", "ffconcat version 1.0\nfile 'a.mp4'\n", "PK\u{3}\u{4}"])
    func playlistsAndArchivesAreNamedSoTheyCanBeRefused(text: String) {
        #expect(ContentSniffer.classify(Data(text.utf8)) == .refusable)
    }

    @Test func oggOpusIsToldApartFromOggVorbis() {
        let opus = Data(Array("OggS".utf8) + Array(repeating: 0, count: 24) + Array("OpusHead".utf8))
        #expect(ContentSniffer.sniff(opus) == .opus)
    }
}
```

`HostileCorpusTests` (opt-in with the matrix): one test per corpus file asserting the outcome table (refused with a
specific `JobError` / converted) and the canary check; the whole suite must finish without a crash of the test
process or a helper killed by a signal other than our SIGINT/SIGKILL.

### E3.2–E3.5

RED: `cannot find 'ContentSniffer'`. GREEN: `swift test --filter ContentSnifferTests`; `ZIVLET_MATRIX=full make
matrix` includes the corpus. Commits `feat(core): content sniffing; the sniffed type wins`, `test(hostile): hostile
media corpus with canary checks`.

---

## Task E4 — Hardening gaps from M3 review (G-11, G-15, G-16, G-18)

| Gap | Change | Failing test first |
|---|---|---|
| G-16 | Staging moves into a private directory: `mkdir(".zivlet-<job>", 0700)` in the destination (fails on `EEXIST`), then `lstat` must show a directory owned by this user with mode 0700 and one link before anything is written; the staged file lives inside it; publish = `renamex_np(dir/file, dest/name, RENAME_EXCL)`; the directory is removed after. Another user cannot create or swap entries in a 0700 directory we own, which closes the check-then-open window of D-M3-26. Reaper removes `.zivlet-*` directories as well as files | `PublisherTests`: a second user cannot be simulated, so assert the invariants: directory mode 0700, owner = `getuid()`; a pre-existing `.zivlet-<job>` symlink makes the claim fail; publish leaves no `.zivlet-*` entry; crash simulation leaves only the directory, which the reaper deletes |
| G-11 | Job records store the helper's start time (`proc_pidinfo(PROC_PIDTBSDINFO).pbi_start_tvsec/usec`); the reaper kills only when PID, path and start time all match; `Proxies/` is not used in Phase 1 (nothing to trim — record "not applicable until P2 previews") | `OrphanReaperTests`: a record whose PID now belongs to a different process (spawn `sleep`, record a wrong start time) is not killed; a matching one is |
| G-15 | Process-wide `DecodeBudget` actor: in-flight decoded megapixels across all ImageIO jobs ≤ 1,500 MP (≈ 6 GB RGBA); a job waits for budget before decoding; a single frame over the per-job cap is still refused at plan time | `DecodeBudgetTests`: three 600 MP reservations — the third waits until one is released; cancellation while waiting leaks no budget |
| G-18 | At launch, raise `RLIMIT_NOFILE` soft limit to `min(hard, 4096)`; log the old and new values | `ResourceLimitsTests`: after `raise(to: 4096)` the soft limit is ≥ min(hard, 4096); lowering never happens |

**Files:** `Sources/ZivletRuntime/Publisher.swift`, `OrphanReaper.swift`, `JobRecordStore.swift`,
`Sources/EngineImage/DecodeBudget.swift` (new), `Sources/ZivletRuntime/ResourceLimits.swift` (new), matching tests.
Commits, one per gap: `fix(runtime): stage inside a private 0700 directory`, `fix(runtime): reaper checks the helper's
start time`, `feat(image): process-wide decode budget`, `feat(app): raise the open-file limit at launch`.

---

## Task E5 — Diagnostics and logging (P1-48)

| Field | Value |
|---|---|
| Goal | Logger categories per 10 §8.7 (`app`, `trigger`, `wheel`, `scheduler`, `media`, `image`, `actions`, `settings`, `hud`, `updates`), paths always `.private` (the M3 lint `check-log-privacy.sh` extended to the new modules). `OSSignposter` intervals: `trigger→frame` (tap detected → first wheel frame), `drop→admit`, and one per job stage (`probe`, `plan`, `execute`, `verify`, `publish`). **Copy Diagnostics** (Settings › Advanced) builds a text report: app version/build, macOS build, Mac model, helper SHA-256s and versions, capability cache contents, settings JSON (no folder paths: the fallback folder is shown as `~/…` with the last component only), the last 200 log lines of this process from `OSLogStore(scope: .currentProcessIdentifier)` with every absolute path reduced to `…/<last component>` (so no folder names, including those under the home folder, survive), the last trigger trace (TriggerMachine transitions ring buffer, 50 entries); copied to the pasteboard; no network ever |
| 05 rows | P1-48 |

**Files:** create `Sources/ZivletRuntime/Diagnostics.swift`, `DiagnosticsRedaction.swift`, `Sources/ZivletTrigger/TriggerTrace.swift`,
`Tests/ZivletRuntimeTests/DiagnosticsTests.swift`; modify `Scripts/check-log-privacy.sh`.

### E5.1 Failing tests first

```swift
@Suite("Diagnostics report (P1-48)")
struct DiagnosticsTests {
    @Test func noUnredactedHomePathSurvives() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let report = DiagnosticsRedaction.redact("""
            opened \(home)/Desktop/secret plan.mov
            wrote /Volumes/Card/DCIM/IMG_0001.HEIC
            """, home: home)
        #expect(!report.contains(home) && !report.contains("Desktop") && !report.contains("DCIM"))
        #expect(report.contains("…/secret plan.mov") && report.contains("…/IMG_0001.HEIC"))
    }

    @Test func reportHasEverySectionAndNoNetworkFields() async throws {
        let report = try await Diagnostics.build(.fake)
        for section in ["Zivlet", "macOS", "Helpers", "Capabilities", "Settings", "Recent log", "Trigger trace"] {
            #expect(report.contains("## \(section)"))
        }
        #expect(!report.contains("http"))
    }
}
```

### E5.2–E5.5

RED: missing types. GREEN: `swift test --filter DiagnosticsTests`; `make lint` (privacy check over new modules).
Commit `feat(runtime): diagnostics report with redaction, signposts and a trigger trace`.

---

## Task E6 — Performance signposts and the bench (P1-63, P1-24 signpost, G-9)

| Field | Value |
|---|---|
| Goal | `make bench` runs `Scripts/bench.sh`: (1) HEIC 12 MP → JPEG through `ImageEngine` (budget ≤ 150 ms on M1, 10 §8.11), (2) 1-minute 1080p MOV → MP4 through the bundled ffmpeg with VideoToolbox (≤ 10 s), (3) drop → admit and drop → HUD (≤ 50 ms) from the signposts via `xctrace record --template 'Logging'` or `log stream --signpost` parsing, (4) idle wake-ups: launch the Release app, wait 10 s, `top -l 3 -stats pid,cpu,idlew -pid <pid>` → 0 wake-ups and 0.0 % CPU, (5) tap → wheel p95 from the `trigger→frame` interval over 50 DEBUG demo shows (`-ZivletDemoWheel`, which does not include real event latency — the real-drag p95 at 120 Hz is owner hardware, O-6). Results go to `build/bench/<date>.json`; `Scripts/bench-compare.sh` fails when a metric regresses > 10 % against `docs/plan/perf/baseline-<model>.json` (first run writes the baseline for this Mac, tagged with the Mac model and "27-only" per 05 §8) |
| 05 rows | P1-63 **[HW]**, P1-24 (signpost), G-9 |

**Files:** create `Scripts/bench.sh`, `Scripts/bench-compare.sh`, `Scripts/tests/test-bench-compare.sh` (baseline 100
ms, run 111 ms → fail; 109 ms → pass; missing metric → fail), `docs/plan/perf/README.md`.

Commit `test(perf): bench with signposts and a 10 % regression gate`.

---

## Task E7 — Watch the unreproduced wheel-test failure (G-12)

Nightly job (F1) runs `swift test --filter ZivletWheelTests` 20 times and appends pass/fail counts to the job summary;
any failure uploads the full log. No code change unless it reproduces; if it does, the fix follows the M3 §5.1 pattern
(failing test first). Commit with F1.
