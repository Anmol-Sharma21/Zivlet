# 09 — M3 record: first end-to-end conversions

Date: 2026-10-21. Status: **M3 code complete on `main`**, review findings addressed (§5.4), gates green; owner QA (§8)
outstanding. Milestone: **M3** of
[05 §2](05-task-list.md) ("First conversions end-to-end via Homebrew ffmpeg + ImageIO"; tasks P1-01…P1-15, P1-20…P1-24,
P1-30, P1-31, P1-33).

This is a record, not a plan. The M3 planning session ended (the Mac slept) before it wrote a plan. Its prototype, 17
commits on top of `44326ad`, was cherry-picked onto `main` unchanged and then audited, debugged and completed. This file
says what M3 contains, which decisions it made (the "index D-M3-n" cited in code comments is defined in §4), where it
departs from [03a](03a-system-design-interaction.md) / [03b](03b-system-design-engines.md) and why, the gate numbers,
the known gaps for M4, and the owner QA steps.

Inputs: [02-architecture](02-architecture.md), [03a](03a-system-design-interaction.md) §3–§4,
[03b](03b-system-design-engines.md) §5–§6, [05-task-list](05-task-list.md) (M3 rows),
[design/10](../design/10-tech-strategy.md) §7.3 and §8, [design/11](../design/11-media-engine.md),
[design/13](../design/13-image-pdf-engine.md).

Clean-room rule: unchanged from M1/M2. No code, assets or UI strings from the reference app or from Open-Tangerine. Every user-facing
sentence in `JobErrorCopy`, `BatchPresentation` and `UndoResult` is Zivlet's own wording.

---

## 1. What M3 contains

A drop on a conversion petal now converts: the dropped URLs become validated `JobRequest`s, the scheduler runs each one
through probe → plan → admit → execute → verify → publish, the output appears beside the original under its
collision-free name, Finder reveals the batch, and a glass HUD shows progress, Cancel, Undo and Reveal. Media goes
through a located ffmpeg (Homebrew in Debug builds); rasters and images → PDF go through ImageIO and Quartz in-process.

### 1.1 Modules (SwiftPM targets in `Packages/ZivletKit`)

| Target | New or changed in M3 | Role |
|---|---|---|
| `ZivletCore` | changed | Job values: `JobRequest`, `InputItem`, `JobID`/`BatchID`, `JobState`, `JobProgress`, `PublishedOutput`, the `JobError` taxonomy, `QualityTier` |
| `ZivletEngineKit` | filled (held only `Lane` before) | `Engine` protocol, `ExecutionPlan`/`Stage`, `JobWorkspace`, `ExecutionContext` (with the output byte limit), `ProgressSink`, `SubprocessRunner`, `EngineLocator`, `CapabilityProbe`, `SharedLoad`, `BlockingWork`, `ImagePipelineSpec`, `StagedFile`, `Lane` |
| `EngineMedia` | changed (M1 planners and `MediaInfo` kept) | `MediaProbe` (ffprobe JSON → `MediaInfo`), `FFmpegProgressParser`, `StallWatch`/`StallMonitor`, `MediaRouteGate`, `MediaEngine`, `MediaVerifier` |
| `EngineImage` | new target | `ImagePlanner` (pure), `ImageRoutes`, `ImagePipeline` (ImageIO), `ImagePDFWriter` and `PDFPageGeometry` (Quartz), `PixelLimits`/`PixelBudget`, `ImageWriteFailure`, `ImageEngine`, `ImageVerifier` |
| `ZivletRuntime` | new target | `JobScheduler`, `JobPipeline`, `AsyncSemaphore`, `LaneWidths`/`LaneGates`/`LaneLimits`, `SystemLoadMonitor`, `Publisher`, `DiskPreflight`, `JobRecordStore`/`OrphanReaper`, `JobRequestFactory`, `BatchSnapshot`, `BatchPresentation`, `HUDBoard`, `JobErrorCopy`, `UndoLog`/`UndoStore`/`UndoHistory`, `ConversionService`, `DemoConversion` |
| `ZivletWheel` | small change | `WheelController.capabilities`: petals for targets no engine can produce here are left off (FR-08) |
| `App` | changed | `AppDelegate` wires `ConversionService`, `UndoHistory`, the orphan reaper and the DEBUG demo; new `ResultHUD` |
| `EngineTestSupport` (test helper) | new | `FakeRunner` (scripted `ProcessRunning`, optional delay) |

Module dependencies follow [02 §6](02-architecture.md): Core ← EngineKit ← EngineMedia / EngineImage ← Runtime.
`ZivletWheel` does not depend on Runtime (its capability input is the `ZivletWheelCore` value `CapabilitySnapshot`);
only the App composition root imports Runtime, through `ConversionService`, `UndoHistory`, `OrphanReaper` and values.

### 1.2 Key types and flows

| Flow | Path through the code |
|---|---|
| Drop → batch | `WheelControllerDelegate.didSelect` → `AppDelegate.handle` → `ConversionService.convert(urls, to:)` → `JobRequestFactory.requests` (regular file, known extension, catalog pair, quarantine read, destination beside the original or `~/Downloads` when the folder is not writable) → `JobScheduler.submit` |
| One job | `JobPipeline.run`: select engine → `availability` gate → `DiskPreflight` → `Publisher.claimStaging` (hidden `.zivlet-<job>.<ext>`, `O_EXCL`) → `JobRecord` written → preparation permit (4 at once) → `engine.prepare` (probe + pure plan) → lane permit → `engine.execute` (progress drained in order; output byte limit = free space − 512 MB) → `engine.verify` → scheduler accepts `.publishing` unless already cancelled → `Publisher.publish` (`StagedFile.check`, quarantine copied, `renamex_np(RENAME_EXCL)` over `name`, `name 2`, …) |
| Events → HUD | `JobScheduler.events` (`submitted`, `changed`, `noted`, `finished`) → `BatchSnapshot.applying` (pure reducer) → `ConversionService.snapshots` → `HUDBoard` (which batch is on screen) → `BatchPresentation.make` → `ResultHUD` |
| Cancel | HUD Cancel → `ConversionService.cancel(batch)` → state `.cancelled` at once → task cancelled → `SubprocessRunner` SIGINT to the process group, SIGKILL at +1 s → staging unlinked, record removed (kept for the reaper when the unlink fails). A job already publishing ignores cancel and succeeds (D-M3-20) |
| Quit | `applicationShouldTerminate` → `.terminateLater` → `shutdown(within: 2 s)` → reply |
| Crash recovery | launch → `OrphanReaper.reap`: for each record whose owner PID is gone, `killpg` the helper if `proc_pidpath` still matches, unlink the hidden staged file, remove the record |
| Undo | finished batch → `UndoHistory.record` → `undo.json`; HUD Undo → `UndoHistory.undo(batch)` → `UndoPlanner.plan` (inode, size, mtime) → Trash; skipped files listed with a reason; files the Trash refused stay in the entry and Undo is offered again |
| Capability gate | `ConversionService.unavailableTargets` asks every engine's `availability` per catalog pair → `CapabilitySnapshot` → `WheelController.capabilities` |
| System load | `SystemLoadMonitor` (memory pressure source + power state) → `JobScheduler.apply` → `LaneLimits` → `AsyncSemaphore.setLimit` |

---

## 2. Task list mapped to 05 rows and commits

All commits are on `main` after `44326ad`, signed off, no co-author trailers. The first 17 are the cherry-picked
prototype (same messages and authorship; new hashes).

| # | Commit | Subject | 05 rows |
|---|---|---|---|
| 1 | `7c32acd` | feat(core): job request, input, error taxonomy and job state values | P1-01 (Core side), P1-33 |
| 2 | `31eb491` | feat(engine): execution plans, workspace, progress sink, `Engine` | P1-01 |
| 3 | `70c836b` | feat(engine): process-group subprocess runner, SIGINT then SIGKILL | P1-20 |
| 4 | `2d48252` | feat(engine): media tool locator and cached ffmpeg capability probe | P1-11, P1-21, P1-22 |
| 5 | `f90ae54` | feat(media): ffprobe JSON → `MediaInfo` with plausibility bounds | P1-02, P1-03 |
| 6 | `5ca3c1c` | feat(media): ffmpeg `-progress` blocks → fractions | P1-07 |
| 7 | `17a3e14` | feat(media): planned conversions through ffmpeg, capability gates, verification | P1-11, P1-23 |
| 8 | `e9ac980` | test(media): all 104 media pairs with a real ffmpeg; H.264 re-encoded for AVI | P1-23, P1-05 |
| 9 | `23b4a65` | feat(image): image pipeline stage and pure raster/PDF plan builder | P1-08, P1-10 |
| 10 | `8ca8479` | feat(image): rasters and images → PDF with ImageIO and Quartz off the pool | P1-24 |
| 11 | `efa9f01` | feat(runtime): cancellation-aware semaphore and lane widths | P1-12 |
| 12 | `fb13d15` | feat(runtime): hidden staging, exclusive-rename publish, collision names | P1-30, P1-14 |
| 13 | `77e9e21` | feat(runtime): job records and the launch orphan reaper | P1-20 (`job.json`), 03a §4.8 |
| 14 | `1f34a4f` | feat(runtime): job scheduler, lanes, ordered progress, immediate cancel | P1-31 |
| 15 | `ad24214` | feat(runtime): drops → requests, error copy, batch snapshots, undo | P1-33, P1-13 (location), P1-15 (first cut) |
| 16 | `2d22cca` | feat(runtime): conversion service, DEBUG demo arguments, real-engine runs | P1-33 |
| 17 | `f8182c6` | feat(app): convert on drop, result HUD, reveal, undo, DEBUG demo | P1-33 |
| 18 | `f2b2889` | test(trigger): bracket live pointer/key/button reads | gate fix (§5.1) |
| 19 | `56275d4` | test(media): share in-flight fixture synthesis | gate fix (§5.1) |
| 20 | `f5ad522` | fix(engine): one capability probe for concurrent first jobs | P1-22 (§5.2) |
| 21 | `c3a9c96` | feat(runtime): undo history on disk, undo only unchanged outputs | P1-15 |
| 22 | `7918981` | feat(runtime): disk preflight before staging | P1-13 |
| 23 | `a00747f` | feat(media): stall watchdog for ffmpeg | P1-07 |
| 24 | `410a75b` | feat(runtime): lane limits under memory pressure and Low Power | P1-12 |
| 25 | `5c74e96` | feat(image): verify the frame count of raster outputs | P1-24 |
| 26 | `124eab9` | test: `make release-check` for Homebrew paths in the Release app | P1-21 |
| 27 | `91cdb20` | fix(runtime): developer tool folders named only in Debug copy | P1-21 |
| 28 | `f380659` | fix(engine): each subprocess wait on its own thread | P1-20 (§5.2) |
| 29 | `37531a8` | fix(engine): a cancelled job stops waiting on a shared probe | P1-20, P1-22 (§5.2) |
| 30 | `b1d1b78` | test(engine): wait for ESRCH when checking a torn-down process group | gate fix (§5.1) |
| 31 | `a183e8e` | docs: M3 record | — |
| 32–50 | `6950efe` … `11c4e6f` | review findings (§5.4) | P1-07, P1-10, P1-13, P1-15, P1-20…P1-24, P1-30, P1-31, P1-33, NFR-6 |
| 51 | (this change) | docs: record the review fixes | — |

### 2.1 Row status

| Row | Status | Notes |
|---|---|---|
| P1-01 EngineKit contracts | done, adapted | `Engine`, `ExecutionPlan`, `Stage` (`.ffmpeg`, `.image`), `Lane` are `Codable`/`Sendable`/`Equatable`; weights must sum to 1 (throwing init and decoder). No separate `OutputSpec`/`VerificationSpec`/`InputProbe` values (D-M3-4) |
| P1-02 MediaInfo parser | done | 15 test functions; fixtures are built in code (`ProbeJSON`), not committed JSON files; hostile input (size, depth, stream count, mutation) covered |
| P1-03 Input confinement | done (M1 + M3) | probe argv has `-protocol_whitelist file -format_whitelist …`; run argv forces `-f <demuxer>`; probed container must match the extension (`contentMismatch`) |
| P1-04…P1-06 planners | done in M1 | M3 changed only AVI: H.264 is re-encoded (D-M3-9) |
| P1-07 progress parser | done except ETA | fraction from `out_time_us`, multi-pass weights via `overallFraction`, stall after 60 s flat `out_time` (injected clock); a `palettegen` pass gets the input's duration on top before its first `out_time` (D-M3-23). ETA from `speed=` is parsed but not surfaced (gap G-3) |
| P1-08 image plan builder | partial | destination type, quality ladder, alpha → JPEG/BMP flatten + note, orientation once (tag kept for JPEG/HEIC/TIFF, baked into the pixels elsewhere, D-M3-29), ICC/EXIF/XMP carried, 16-bit kept where ImageIO allows, 200 MP cap, CMYK converted for targets without it. Animation is flattened to the first frame (+ note) instead of carried (gap G-5); no "Web (sRGB)" preset, no HDR gain-map handling, no AVIF ffmpeg fallback (G-6) |
| P1-09 WebP plan builder | not in M3 | WebP output needs libwebp, not shipped yet; the route is typed unavailable and hidden (D-M3-8) |
| P1-10 images → PDF | done inside `EngineImage` | RGB/grey JPEG bytes embedded unchanged (DCT), other frames decoded once; page = displayed image at its DPI (72 if absent), orientation applied by the page transform (D-M3-25); multi-page TIFF → one page per frame (cap 1,000); no separate `EnginePDF` target yet (D-M3-11) |
| P1-11 capability parsers and route filter | done | `-encoders`/`-filters` parser, `CGImageDestinationCopyTypeIdentifiers`, per-pair `RouteAvailability` with missing names, wheel snapshot. `-muxers` is not parsed yet (every muxer M3 uses is a core ffmpeg muxer) |
| P1-12 semaphore and lanes | done | FIFO, cancellation-safe, width respected under 100 waiters; `.warning` halves, `.critical` pauses, Low Power halves `cpu` |
| P1-13 preflight and location | done | 1.5 × estimate + 512 MB (estimate = source size, D-M3-13); FAT32/exFAT free space read from `volumeAvailableCapacity` when the important-usage key says 0; ffmpeg capped with `-fs` at free space − 512 MB; read-only folder → `~/Downloads` |
| P1-14 NameReserver | superseded | collisions are resolved by the kernel (`RENAME_EXCL`), not an actor (D-M3-2); tests: 50 concurrent publishes and a 200-job batch for one name all get distinct names |
| P1-15 UndoLog | done for conversions | immutable entries, newest first, JSON persistence, pure revert plan, missing/changed/Trash-refused files listed; Trash-refused files stay undoable. Move entries wait for the Move action (G-7). History is 20 batches / 24 h per 03a §4.7, not 50 (D-M3-15) |
| P1-20 SubprocessRunner | done | fixed env (`PATH=/usr/bin:/bin`, `LC_ALL=C`, `TMPDIR`), own process group, SIGINT → SIGKILL at +1 s, 64 KB stderr tail, stdout line stream, PID into the job record; a failed wait is `waitFailed`, never a status. Own `posix_spawn` runner (D-M3-1) |
| P1-21 EngineLocator | done | bundled `Contents/Helpers` → Debug only: `ZIVLET_FFMPEG_DIR`, then Homebrew (D-M3-19); `make release-check` builds Release from scratch, fails on a failed build, and proves the app holds no Homebrew path |
| P1-22 capability probe runner | done | cache `Caches/app.zivlet.Zivlet/Capabilities/<sha256>-<osBuild>.json`; second launch spawns nothing; concurrent first callers share one probe |
| P1-23 MediaEngine + verifier | done, adapted | container, expected stream kind, WebM codecs, duration within max(0.25 s, 1 %) (03b §5.9 rather than 05's "1 frame / 50 ms", D-M3-16). Stream-count check and AVFoundation `isPlayable` in the engine are gaps (G-4); `isPlayable` is asserted in the real-ffmpeg pair tests |
| P1-24 ImageEngine | done except perf signpost | thumbnail-capped decode, 200 MP cap per frame and 1,000 MP per job checked on the decoded source (D-M3-24), TIFF always LZW, GCD off-pool (D-M3-10), verifier: type, displayed size, alpha, frame/page count. HEIC 12 MP ≤ 150 ms nightly signpost not set up (G-9) |
| P1-30 workspace + publisher | done, adapted | staging location differs from 03a (D-M3-2); staged file must still be this user's regular, singly linked file before a writer opens it and before publish (D-M3-26); quarantine copied (`XATTR_NOFOLLOW`); source never replaced; staging removed on failure/cancel; reaper removes it after a crash |
| P1-31 JobScheduler | done | in-process actor; per-plan lane; preparation gate (D-M3-21); per-file failure isolation; cancel visible at once and decided against publish on the actor (D-M3-20); quit returns at 2 s even when a job ignores cancel; 200-file batch test |
| P1-33 drop → job wiring | done | see §1.2; one Finder reveal per batch (default on, `-ZivletRevealResults NO` turns it off) |

---

## 3. Scope list check (M3 brief)

| Item | Where |
|---|---|
| Engine kit | `ZivletEngineKit` (§1.1) |
| Subprocess runner | `SubprocessRunner`, `SubprocessSpawn` |
| ffprobe / progress parsing | `MediaProbe`, `FFmpegProgressParser` |
| Media execution with capability gates | `MediaEngine`, `MediaRouteGate`, `FFmpegRequirements` |
| ImageIO image engine | `EngineImage` |
| Runtime scheduler with lanes | `JobScheduler`, `JobPipeline`, `LaneGates`, `LaneLimits` |
| Staging + `renamex_np(RENAME_EXCL)` publish | `Publisher` |
| Orphan reaper | `OrphanReaper`, `JobRecordStore` |
| Undo | `UndoLog`, `UndoStore`, `UndoHistory`, HUD button |
| Conversion service | `ConversionService` |
| Result HUD | `App/ResultHUD.swift` |
| DEBUG `-ZivletDemoConvert <path> <format>` | `DemoConversion`, `AppDelegate.runDemo`, `Scripts/demo-convert.sh`, `make convert-demo` |

---

## 4. Decision index (D-M3-n)

Code comments cite these numbers.

| ID | Decision | Why |
|---|---|---|
| D-M3-1 | Own `posix_spawn` runner instead of swift-subprocess | swift-subprocess 1.0.2 stops its teardown once the group leader exits, leaving SIGINT-ignoring grandchildren alive. Ours signals the whole group and SIGKILLs any member left after the leader exits. Blocking waits use dedicated threads, not the global queues (§5.2) |
| D-M3-2 | Staging is a hidden `.zivlet-<job>.<ext>` file in the destination folder, claimed with `O_EXCL`; collisions are resolved by `renamex_np(RENAME_EXCL)` stepping through `name`, `name 2`, … (cap 9,999) | Same volume as the result by construction (one rename), works on SMB/FAT where `itemReplacementDirectory` fails, and the kernel decides collisions atomically, including case-insensitive ones, so a `NameReserver` actor (P1-14) adds nothing. The reaper only deletes names with the staging prefix |
| D-M3-3 | Scheduler in-process, one lane per plan (the first stage's) | Phase 1 per 05 P1-31 (XPC is P2-01). Every M3 plan uses one lane for all its passes, so per-stage lane hand-off is not needed yet |
| D-M3-4 | Trimmed contracts: `JobState` has `preparing` for probe + plan; `JobProgress` carries only `fraction`; verification is the engine's `verify` method rather than a `VerificationSpec` value | Each engine verifies what only it can read back (ffprobe vs ImageIO); stage, ETA and bytes are not shown by the M3 HUD |
| D-M3-5 | The wheel's capability gate is a set of unavailable targets (`CapabilitySnapshot`), computed once at launch from every engine's `availability` | Petal lists stay pure in `ZivletWheelCore`; per-file gating (no audio track → hide MP3) waits for hover probes (03a §3.4 step 5) |
| D-M3-6 | Homebrew ffmpeg 8.1.2 lacks `libvorbis` and `zscale`: OGG output and HDR → SDR tone-mapping routes are typed unavailable (OGG petal hidden; HDR sources to 8-bit targets fail with "Missing: zscale") | Never fall back to the experimental native Vorbis encoder (03b §5.4); the bundled helper build (P1-50s) will include both |
| D-M3-7 | SVG input routes are unavailable in M3 | resvg is not integrated yet (03b §6.4) |
| D-M3-8 | WebP output is unavailable in M3; WebP input works through ImageIO | libwebp is not integrated yet (03b §6.2); P1-33's png → webp demo row moves to M4 |
| D-M3-9 | AVI never stream-copies H.264; it re-encodes to MPEG-4 Part 2 | Found by the real-ffmpeg sweep: AVCC needs `h264_mp4toannexb` and B-frame timestamps stretch the duration |
| D-M3-10 | Blocking ImageIO/Quartz work runs on GCD via `BlockingWork`, never on the cooperative pool | Concurrent AVIF encodes on the cooperative pool deadlock on macOS 27; cancellation is a flag polled between frames |
| D-M3-11 | Images → PDF lives in `EngineImage` (Quartz), not a new `EnginePDF` target | Only raster → PDF exists in M3; the target split comes with the PDF engine (P2) |
| D-M3-12 | `JobErrorCopy` (user sentences) lives in `ZivletRuntime` | Until the `ZivletUI` module and its string catalog exist |
| D-M3-13 | Disk preflight estimates the output at the source size; ffmpeg gets `-fs` at free space − 512 MB, and an output that reaches it fails as `diskFull` | Plans carry no size estimate yet; the 512 MB reserve absorbs growth such as MP3 → WAV, and the `-fs` cap stops a compressible hostile input from filling the volume. Unknown free space does not block and sets no cap |
| D-M3-14 | DEBUG launch arguments `-ZivletDemoConvert /abs/path <format> [-ZivletDemoCancelAfter <ms>]` run the drop path without a drag | End-to-end checks without Accessibility permission; compiled out of Release |
| D-M3-15 | Undo history: 20 batches, 24 h, `~/Library/Application Support/Zivlet/undo.json`; identity = inode + size + mtime at publish | 03a §4.7 is newer than 05 P1-15 ("history of 50") |
| D-M3-16 | Media duration tolerance max(0.25 s, 1 %) | 03b §5.9 and 11 §8.4; 05's "1 frame / 50 ms" is stricter than encoders guarantee for VFR sources |
| D-M3-17 | Stall = `out_time` not advancing for 60 s → new `JobError.stalled` | 03a §4.6 watchdog; a typed case gives its own sentence instead of a misleading exit status |
| D-M3-18 | Lane limits under load: `.warning` halves every lane, `.critical` sets every limit to 0 (pause), Low Power halves `cpu`; lowering a limit never preempts a running job | 03a §4.2; preempting would waste finished work |
| D-M3-19 | `ZIVLET_FFMPEG_DIR` is honoured in Debug builds only, after bundled helpers (revised after review; first version: every build) | In Release, anything that can set the launch environment (launchctl setenv, a LaunchAgent, `open --env`) could make the signed, hardened app run an arbitrary ffmpeg with Zivlet's file-access grants. Release trusts only `Contents/Helpers` |
| D-M3-20 | Cancel and publish are decided on the scheduler actor: the pipeline asks to begin publishing and discards its output if the job was cancelled first; a job in `.publishing` ignores cancel | Publishing is one rename (milliseconds). Without one decision point the HUD could say "Cancelled" while the result sat on disk with no undo entry |
| D-M3-21 | `engine.prepare` runs under a preparation gate of 4 permits | It spawns ffprobe before the lane is known; a big drop started one per file and ran out of descriptors (GUI soft limit 256) |
| D-M3-22 | `JobError.helperFailed(errno:)` and `JobError.writeFailed(String)`; `engineMissing` only for ENOENT, ENOTDIR, EACCES, ENOEXEC, EBADARCH, EBADEXEC | EMFILE, EAGAIN or a lost child (ECHILD, now `SubprocessError.waitFailed`) said "engine wasn't found", and an encoder failure said "file may be damaged" |
| D-M3-23 | A pass with `palettegen` (video → GIF) gets 60 s + the input's duration before its first `out_time`; every other pass starts on 60 s | The palette graph writes nothing until it has decoded the whole input; long clips were killed as stalled |
| D-M3-24 | Image decode caps enforced in the pipeline on the source it decodes: 200 MP per frame, 1,000 MP per job | The probe only saw frame 0, and execute reopened the file, so later TIFF pages or a swapped file bypassed the cap |
| D-M3-25 | Image → PDF embeds RGB/grey JPEG bytes unchanged, decodes other frames (CMYK JPEG included) without orientation, applies the EXIF orientation through the page transform, and sizes the page from the frame's DPI | 03b §6.2; a 1.6 MB JPEG had become a 14 MB Flate PDF. CMYK JPEGs are decoded because Adobe-inverted CMYK is not safe to pass through |
| D-M3-26 | Before ffmpeg or Quartz open the staged path, and before publish, it must name a regular file owned by this user with one link (a missing file is allowed before writing) | Someone who can write in the destination folder could swap in a symlink (ffmpeg `-y` and Quartz follow it) or their own file. ImageIO replaces its output by rename, so it does not follow a symlink. A check-then-open window remains (G-16) |
| D-M3-27 | One HUD, many batches: `HUDBoard` shows unseen finished failures first (oldest first, until closed), then the newest batch converting, then the newest finished one; buttons and the success linger act on the batch on screen | A newer batch's progress overwrote a failure the user had not seen, and Cancel/Undo/Reveal acted on whichever batch reported last |
| D-M3-28 | Logs: `JobError.logDescription` (case, numbers, formats; no folder, stderr or free text) is public, full descriptions are private; `make lint` runs `Scripts/check-log-privacy.sh` | 01 NFR-6: paths private. The stderr tail and the denied folder hold paths |
| D-M3-29 | The EXIF orientation tag is kept, with the pixels copied unturned, only for JPEG, HEIC/HEIF and TIFF targets; every other raster type (PNG, BMP, GIF, AVIF, WebP, anything new) gets a turned or flipped frame decoded upright once and written with orientation 1 (also in the TIFF dictionary), other metadata carried | Many viewers ignore PNG `eXIf`, BMP and GIF have no orientation field, and ImageIO's AVIF encoder writes no `irot`/`imir` (macOS 27: jpg o6 → avif came out sideways and failed verification; o2–o4 lost the flip silently). PDF already applies it through the page transform (D-M3-25) |

---

## 5. Integration, debugging and fixes after the cherry-pick

### 5.1 The two failing tests reported for the prototype

Six full `make test` runs on `main` right after the cherry-pick: all nine bundles always ran to the end (the "may stop
early" report was not reproduced). Two tests failed intermittently.

| Test (bundle) | Root cause | Verdict | Fix |
|---|---|---|---|
| `readerReportsMonotonicUptimeAndTheInjectedWheelFlag` (TriggerHost, 27 tests) | The reader and the expectation each read `NSEvent.mouseLocation` separately; moving the mouse during the run made them differ (failed in 4 of 6 runs while the Mac was in use) | test wrong | `f2b2889`: a reader value counts only when the OS reports the same value just before and after it |
| `convertsVerifiesAndPlays(webm → mp3)` (EngineMedia) | `FixtureFactory` is an actor that awaited ffmpeg before recording the fixture; actors are reentrant, so a second pair test for the same source started another `-y` synthesis that truncated the file under the first ("unreadable") | test wrong | `56275d4`: one in-flight synthesis task per source format |
| `cancellingARunningEncodeStopsFFmpegQuickly` (EngineMedia), found while re-running gates | Two real bugs (`f380659`, `37531a8`, §5.2) plus a test that cancelled during the capability probe instead of during ffmpeg | code and test wrong | see §5.2 |
| `cancellingKillsTheWholeGroupWithinOneSecond` (EngineKit), found in the final runs | Right after teardown the SIGKILLed background `sleep` is a zombie until launchd reaps it; `killpg(group, 0)` then fails with EPERM, not ESRCH (13 of 30 trials in a Python probe) | test wrong | `b1d1b78`: poll for ESRCH up to 500 ms |

The prototype's other report (one issue in the 65-test `ZivletWheelTests` bundle) did not reproduce in 6 full runs
plus 12 runs of the Wheel and TriggerHost bundles under 10 CPU-saturating processes. Every wheel test injects its
screens, so display changes cannot explain it; it is listed as G-12 to watch.

### 5.2 Product bugs found by the audit (each with a failing test first)

| Commit | Bug | Test that failed first |
|---|---|---|
| `f5ad522` | `CapabilityProbe` and `MediaToolbox` checked their cache, then awaited the probe: every job of a batch dropped at first launch hashed ffmpeg and spawned `-encoders`/`-filters` again | 8 concurrent callers: 2 launches expected, more seen |
| `f380659` | Each child held three global-queue threads (two pipe reads, the exit wait). That pool is capped, so with many children a cancelled child's SIGKILL timer and reap waited for unrelated children | 80 sleeping children + cancel a SIGINT-ignoring child: 3.2 s, bound 1.5 s |
| `37531a8` | After `f5ad522` the probe ran in an unstructured task and waiters ignored their own cancellation: a job cancelled during a slow first probe waited for it, then spawned ffmpeg only to kill it after 1 s. Also: the runner spawned even for an already cancelled task | cancelled waiter returned after 1 s with a value; already-cancelled run spawned a child |
| `91cdb20` | The Release binary contained `/opt/homebrew/bin` (in the media-engine error detail), failing P1-21 | `make release-check` (`124eab9`) |

The ffmpeg cancel integration test was also corrected in `37531a8`: it now resolves the tools first and cancels only
once ffmpeg runs, so it times the helper teardown rather than a capability probe.

### 5.3 Missing pieces implemented (TDD)

`c3a9c96` persistent undo (P1-15), `7918981` disk preflight (P1-13), `a00747f` stall watchdog (P1-07), `410a75b` lane
limits under memory pressure and Low Power (P1-12), `5c74e96` raster frame-count verification (P1-24),
`124eab9` Release path check (P1-21).

### 5.4 Review findings (second pass, `6950efe` … `11c4e6f`)

Twenty-three findings from a swift, quality, security and silent-failure review. Each was checked against the code
first; where behaviour changed, a test failed before the fix. None was skipped; four are fixed in part, with the rest
recorded as gaps.

| # | Finding (severity) | Verified | Commit | Test that failed first / note |
|---|---|---|---|---|
| 1 | `shutdown(within:)` waited for jobs that ignore cancel (HIGH) | yes: 3.3 s for a 200 ms limit | `6950efe` | job ignoring cancel for 3 s: shutdown must return false in < 1 s |
| 2, 6, 17 | Cancel during publish: HUD "Cancelled", file on disk, no undo (MEDIUM ×3) | yes | `bbd7f60` | 60 jobs cancelled on their `.publishing` event: disk and states disagreed. Fix per D-M3-20; a file that cannot be stamped after the rename is removed |
| 3 | `blockUntilExit` turned a failed wait into `exited(0)` (MEDIUM) | yes | `2594222` | child reaped in `onSpawn`: `SubprocessError.waitFailed(ECHILD)` expected |
| 4 | FAT32/exFAT: every job `diskFull` (HIGH) | yes: important-usage key 0, available 104 MB on a FAT image | `76a136d` | pure fallback cases plus a FAT disk image; a 1.5 GB FAT32 image converts end to end |
| 5 | `prepare` before the permit: EMFILE on big drops (HIGH) | yes (code path) | `ccb8656` | 40 jobs: concurrent `prepare` must peak at 4. Error mapping in #19 |
| 7 | Stall watchdog killed long GIF palette passes (MEDIUM) | yes (logic) | `1358987` | startup-limit watch and monitor tests, `startupLimit` per argv. The 60 s clip warning of 03b §5.6 is a gap (G-17) |
| 8 | TIFF not LZW for some sources (MEDIUM) | partly: a plain JPEG gave LZW here; a HEIC source (tile sizes in its TIFF dictionary) gave `Compression: 1` | `4df775b` | jpg, png, heic → tiff must read compression 5 |
| 9 | Image → PDF re-encoded JPEGs and ignored DPI (MEDIUM) | yes | `6644e7d` | `/DCTDecode` and the JPEG's own bytes in the PDF; 288 DPI page = 10 × 5 pt; all 8 orientations match ImageIO's rendering. A 564 KB JPEG now gives a 568 KB PDF |
| 10, 13 | Paths in public logs (MEDIUM ×2) | yes | `c69b326` | `logDescription` cases; `Scripts/check-log-privacy.sh` fails on the old code |
| 11 | Decode cap checked on frame 0 only (HIGH) | yes | `9a03c4a` | TIFF with a small page 0 and a larger page 1, small injected limits, raster and PDF. A process-wide decode budget is a gap (G-15) |
| 12 | No output size cap: hostile input fills the volume (MEDIUM) | yes | `fe223f8` | argv must carry `-fs`; an output at the cap is `diskFull`; the pipeline passes free − 512 MB. Plan-based estimates stay G-13 |
| 14 | `ZIVLET_FFMPEG_DIR` honoured in Release (MEDIUM) | yes | `662b4f1` | `honoursOverride` false in Release; D-M3-19 revised |
| 15 | Staged file reopened by path: symlink or swap (MEDIUM) | yes for ffmpeg and Quartz (same inode, follow symlinks); ImageIO writes a new inode by rename | `c46bc27` | symlink and hard link at the staged path refused at publish (victim untouched) and before ffmpeg runs. Fixed in part: private staging directory or descriptor-passing writers are G-16 |
| 16 | Failed staging unlink dropped the record the reaper needs (MEDIUM) | yes | `c577db6` | unwritable folder: the record must remain |
| 18 | Empty or truncated ffmpeg capability list cached as valid (MEDIUM) | yes | `761a9fa` | garbage and truncated lists must throw and leave no cache; an empty cached file is re-probed |
| 19 | Every runner error became "engine wasn't found" (MEDIUM) | yes | `4528cff` | errno mapping table, EMFILE in `CapabilityProbe` and `MediaEngine` (D-M3-22) |
| 20 | `Finalize` failure blamed the input; PDF writes unchecked (MEDIUM) | yes | `6644e7d` | write into a missing folder: `writeFailed`, raster and PDF; nearly full volume → `diskFull` |
| 21 | Undo dropped Trash-refused files; misleading copy (MEDIUM) | yes | `f2c87b7` | refused file undone on the second try; one sentence per outcome |
| 22 | One HUD snapshot for all batches (MEDIUM) | yes | `11c4e6f` | `HUDBoardTests` (D-M3-27) |
| 23 | `make release-check` passed on a failed build (MEDIUM) | yes | `6c677ff` | script now removes old products and checks the xcodebuild status; passes on a real build |

### 5.5 Orientation baked for targets that ignore the tag (after the review)

| Bug | Commit | Test that failed first |
|---|---|---|
| Frames copied with `AddImageFromSource` kept the EXIF orientation tag for every target: PNG outputs were stored sideways with an `eXIf` tag many viewers ignore, GIF outputs (pipeline level; GIF is a media-engine target) had turned pixels yet still read back with the source orientation, so readers that honour it turned them twice, and ImageIO's AVIF encoder dropped it (o5–o8 failed verification, o2–o4 lost the flip silently). Fixed per D-M3-29 (`OrientationPolicy`) | `4c5c82d` | `ImageOrientationTests`: all 8 orientations × png, bmp, avif (engine) and gif (pipeline) must read back upright with orientation 1; jpg (from TIFF), heic, tiff must keep the tag and the stored pixels; a baked PNG keeps its EXIF date with orientation 1 in the TIFF dictionary. BMP already passed (ImageIO's BMP writer turns the pixels itself) |

---

## 6. Gates (2026-10-21, `main` at `11c4e6f`, macOS 27.0 26A428, Xcode 27, Homebrew ffmpeg 8.1.2)

All gates ran at `11c4e6f` (the docs change after it touches no code). The first M3 run, at `b1d1b78`, had 472 tests.

| Gate | Result |
|---|---|
| `make test` | exit 0; nine `✔ Test run with …` lines, **511 tests**, no failures: Wheel 65, WheelCore 55, Trigger 31, TriggerHost 27, Runtime 94, EngineKit 57, Core 59, EngineMedia 83 (includes the 104 real-ffmpeg pair cases as one parameterised test), EngineImage 40 |
| `make lint` | exit 0, no findings (swift-format and the new log-privacy check) |
| `make coverage` (80 % per module, nine modules) | exit 0: ZivletCore 97 % (470/480), ZivletTrigger 100 % (226/226), ZivletWheelCore 99 % (373/374), ZivletEngineKit 99 % (664/666), EngineMedia 98 % (1066/1087), EngineImage 95 % (367/383), ZivletRuntime 96 % (1117/1162), ZivletTriggerHost 92 % (283/307), ZivletWheel 97 % (872/896) |
| `make app` | `** BUILD SUCCEEDED **` (Debug) |
| `ZIVLET_FFMPEG_DIR=/opt/homebrew/bin make smoke` | exit 0; 15 planned argvs, 13 run and match their expected streams, 2 recorded as known issues because this ffmpeg lacks `libvorbis` (m4a → ogg) and `zscale` (HDR mov → webm), D-M3-6 |
| `make release-check` | `Release build contains no Homebrew path.` (clean products, build status checked) |
| M3 exit, automated (`make convert-demo` on the Debug app) | jpg → pdf (568 KB from a 564 KB JPEG, one `/DCTDecode`), heic → tiff (LZW), jpg → png, wav → mp3, jpg → png on a 1.5 GB FAT32 image: each `1 saved`, no `.zivlet-*` left; 60 s mov → webm cancelled after 1.5 s: `0 saved, 0 failed, 1 cancelled`, nothing left. Finder reveal and the HUD itself need a person (§8) |

---

## 7. Known gaps for M4

| ID | Gap | Row / source |
|---|---|---|
| G-1 | Bundled ffmpeg/ffprobe helpers (with libvorbis, zscale, libsvtav1) and code-signing checks; until then Release builds have no media engine | P1-50s, 10 §8.9 |
| G-2 | WebP output (libwebp) and SVG input (resvg) | P1-09, P1-25+, D-M3-7/8 |
| G-3 | ETA from `speed=`, bytes written, stage counts in `JobProgress`; HUD per-item list, cascade, 4 s success card held while hovered (M3 uses 6 s, no hover hold), drag-out, thumbnail, before → after size | P1-07, P1-40/P1-41, 03a §4.5 |
| G-4 | Media verifier: stream count against the plan and AVFoundation `isPlayable` for MP4/MOV inside the engine | P1-23, 03b §5.9 |
| G-5 | Animated sources: APNG/HEICS carried instead of flattened; multi-page TIFF → single-image target as a folder `<base> Images` | P1-08, 03b §6.2 |
| G-6 | "Web (sRGB)" preset, HDR gain maps / tone-mapping, AVIF ffmpeg fallback route, Compress | P1-08, 03b §6.2–6.3 |
| G-7 | Undo for Move entries; status-menu "Recent results" | P1-15, 03a §4.7 |
| G-8 | Content sniffing at admission (sniffed type wins, note on the card); the image engine currently accepts any decodable content under a raster extension | 03a §3.2 |
| G-9 | HEIC 12 MP → JPEG ≤ 150 ms nightly signpost | P1-24 |
| G-10 | Downloads fallback is not announced on the card; cloud/SMB rename confirmation (directory watch) | 03a §4.3 |
| G-11 | Orphan reaper: owner-PID reuse check (start time), `Proxies/` trim; records are flat files, so no job-directory sweep is needed | 03a §4.8 |
| G-12 | Watch for the unreproduced `ZivletWheelTests` failure (§5.1) | — |
| G-13 | Plan-supplied output size estimates for the disk preflight (duration × PCM rate, frames × pixels) and a per-job maximum; per-stage lanes for multi-lane plans; retry-once on worker crash (with XPC) | D-M3-3, D-M3-13, P2-01 |
| G-14 | Per-file capability gating on hover (video without audio → no MP3 petal) | 03a §3.4 step 5 |
| G-15 | Process-wide in-flight decode budget for in-process ImageIO (today: 200 MP per frame and 1,000 MP per job, lanes narrowed under memory pressure) | review #11, 10 §8.9 |
| G-16 | Staging without a check-then-open window: a private `0700` staging directory or writers given a descriptor (ffmpeg `fd:`, ImageIO data consumer), publish by descriptor | review #15, D-M3-26 |
| G-17 | Clip-length guard for video → GIF (warn above 60 s) | 03b §5.6, review #7 |
| G-18 | Raise `RLIMIT_NOFILE` at launch as extra headroom beside the preparation gate | review #5 |

---

## 8. Owner QA (Debug build, real hardware)

Build: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer && make app`, open
`build/DerivedData/Build/Products/Debug/Zivlet.app`. Homebrew ffmpeg must be installed (`brew install ffmpeg`). Watch
Console with `subsystem:app.zivlet.Zivlet`. Record results in `docs/plan/spikes/M3-QA.md` (date, macOS build, Mac
model, pass/fail, notes).

| # | Steps | Expected | Covers |
|---|---|---|---|
| R1 | Drag a `.jpg` from Finder, tap ⇧, drop on PNG | HUD shows progress then "Saved photo.png"; `photo.png` beside the original, selected in Finder; original untouched | M3 exit, FR-07 |
| R2 | Same with a `.heic` → JPG, a `.mov` → MP4, a `.wav` → MP3, an `.mp4` → WEBM | Each output beside its original, plays in QuickTime (WebM in Safari), Finder reveals it | M3 exit |
| R3 | Drop the same file on the same petal twice | Second output is `name 2.ext`; nothing overwritten | FR-11 |
| R4 | Drop 5 files at once | One HUD for the batch ("name · n of 5", then "Saved 5 files"), one Finder reveal selecting all outputs | P1-33 |
| R5 | Drop a long `.mov` → WEBM, press Cancel within a few seconds | HUD says cancelled at once; no `.zivlet-*` file and no output left (`ls -la` the folder); no `ffmpeg` in Activity Monitor after ~1 s | M3 exit, 03a §4.6 |
| R6 | Convert, then press Undo on the success card | Output moves to the Trash; "Moved to the Trash." | P1-15 |
| R7 | Convert a file; while the success card is up (6 s) run `echo x >> <output>` in Terminal, then press Undo | Output stays; "1 file changed since it was saved, so it was left in place." Then convert again, quit, relaunch: `~/Library/Application Support/Zivlet/undo.json` still lists the batch | P1-15, 03a §4.7 |
| R8 | Convert into a read-only folder (e.g. a locked folder or a mounted DMG) | Output lands in `~/Downloads` | FR-17 |
| R9 | Drag an `.mp3` and look at the convert wheel | No OGG petal (Homebrew ffmpeg has no libvorbis) and no WEBP petal for images | FR-08, D-M3-6/8 |
| R10 | Start a long encode, `kill -9` the Zivlet process, relaunch | Console: "Cleaned up after a previous crash: 1 helpers, 1 files"; no `.zivlet-*` left; no stray ffmpeg | 03a §4.8 |
| R11 | Start a conversion and quit from the status menu | App quits within about 2 s; no partial file left | 03a §4.2 |
| R12 | Automated demo without a drag: `make convert-demo FILE=/abs/photo.jpg TO=png`, and `make convert-demo FILE=/abs/long.mov TO=webm CANCEL_MS=1500` | "OK: …photo.png (N bytes)"; "OK: cancelled, nothing left in …" | D-M3-14 |
| R13 | `make release-check` | "Release build contains no Homebrew path." | P1-21 |
| R14 | Convert a photo on a FAT32 or exFAT card or USB stick | Output beside the original; no "not enough free disk space" | P1-13, review #4 |
| R15 | Drop a file that fails (e.g. a renamed text file as `.png`), then at once start another batch | The failure card stays until Close; then the second batch's card shows. Cancel/Undo/Reveal act on the card on screen | D-M3-27 |
| R16 | Convert a JPEG to PDF and open it in Preview | Page size matches the photo at its DPI; the PDF is about the JPEG's size | D-M3-25 |

M3 passes when §6 is green and R1–R6, R9 and R12 pass (the 05 M3 exit definition). The other rows feed M4.
