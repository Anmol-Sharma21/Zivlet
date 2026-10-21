# 11 — M4 record: Phase 1 code complete (private alpha 0.1 waiting on the owner)

Date: 2026-10-22. Status: **M4 code complete on `main`**. The review findings are addressed (§3) and the automated
exit rows are run (§4). The owner steps O-1 … O-6 (§7) are outstanding, so M4 is not "complete" in the sense of
[10 §9](10-implementation-plan-m4.md): no notarized DMG, no Sparkle feed, no runner, no tag and no human QA yet.
Milestone: **M4** of [05 §2](05-task-list.md) ("Phase 1 complete (private alpha 0.1)").

This is a record, not a plan. The plan is [10](10-implementation-plan-m4.md) with its parts
[10a](10a-m4-vendor-builds.md) … [10h](10h-m4-release-exit.md). This file says what M4 contains, which decisions it
added after the plan (D-M4-16 … D-M4-24, defined in [10 §5](10-implementation-plan-m4.md)), what the review changed,
the gate numbers, the known gaps, and the owner steps.

Clean-room rule: unchanged from M1–M3. No code, assets, sounds or UI strings from the reference app or from
Open-Tangerine. The tick is synthesized by `ToneSynth`, the practice file is drawn by Zivlet, and every sentence in the
HUD, cards, Settings, onboarding and the QA lists is Zivlet's own wording.

---

## 1. What M4 contains

| Stream | What is in `main` | Plan |
|---|---|---|
| A — vendor builds and bundling | `Vendor/versions.lock` with a verified fetch; a build-tool check; FFmpeg 9.0.2 (GPLv3) with x264, libvpx, SVT-AV1, dav1d, opus, ogg, vorbis, LAME, libwebp and zimg folded into shared libav*; a staged and gated media tree (`verify-media.sh`: licence, dependencies, build paths, encoders, demuxers, devices, protocols, size); `CWebP.xcframework` (libwebp 1.6.0); `CZivletSVG.xcframework` (our `zivlet-svg` crate over resvg 0.47.0); cache key, pack, unpack and a reproducibility check; binary targets built on demand; helpers embedded in `Contents/Helpers` and `Frameworks` and signed inside-out; the helper signature check; licence manifest, gate and corresponding-source bundle; the size gate | 10a, 10b |
| B — engines | WebP plan and libwebp writer (still and animated, ICC/EXIF/XMP); SVG input (seven raster targets, SVG → PDF as an image page); APNG and HEICS animation carried; Web (sRGB); HDR gain maps tone-mapped for SDR targets; HDR tone-map chain fix; Vorbis and HDR fixtures; stream count and AVFoundation playability in the verifier; the long-GIF note; plan goldens for every raster pair | 10c |
| C — actions | validated action requests; Copy and Copy Path (Option: shell-quoted); AirDrop; Move planner and executor (cross-volume copy, verify, Trash) with undo; Open in Terminal (five terminals); the Move Here panel; the action service with toasts, cards and undo; the five actions on the wheel, Float hidden | 10d |
| D — app shell | versioned settings store with migration; settings drive bindings, feedback, theme, reveal and the fallback folder; Settings window (General, Updates, Advanced); status menu (state, batches, Recent Results, Pause, Practice); launch at login; resumable onboarding with Zivlet's own practice file and a key legend; progress with ETA, bytes and stages; the HUD in `ZivletUI` (cascade, 50 ms budget); the result card (thumbnail, sizes, Open, Copy, drag-out, details, Retry, Downloads note); UI test target (owner-run) | 10e, 10f |
| E — verification | deterministic fixture generator; the 161-pair matrix (PR subset, nightly full) with property checks and, after the review, eight targeted cases; content sniffing; a hostile corpus with canaries; private 0700 staging; the reaper's start-time check; a process-wide decode budget; a raised open-file limit; Copy Diagnostics with redaction, signposts and a trigger trace; the bench with a 10 % regression gate | 10g |
| F — release | CI, nightly and vendor workflows for a self-hosted runner; Sparkle 2.10.0 with a placeholder feed (updater off until O-2/O-3); DMG, notarize, appcast, SBOM and release-notes scripts; the release workflow up to the owner's keys; the M4 exit runner `Scripts/m4-exit.sh` | 10h |

New SwiftPM modules in M4: `ZivletActions`, `ZivletSettings`, `ZivletUI` (with the HUD moved out of the app) and the
binary targets `CWebP` and `CZivletSVG`; dev tools `zivlet-fixtures` and `zivlet-bench`; test target
`ZivletMatrixTests`. The action HUD moved from `App/` into `ZivletUI` in the review so it is tested.

## 2. Commits

92 commits after `9492318` (the plan), counting this record, all signed off, none with a co-author trailer. In plan order: A1–A14
`f60f424` … `bad0980`; B1–B6 `397a794` … `82c65f2`; C1–C7 `16c2c29` … `c58e55e`; D1–D11 `55becbc` … `1b8cd8f`;
E1–E7 `1778640` … `11f7d7c`; F1–F6 `050c951` … `460c14e`; review fixes `1a87764` … `b8dfe2e` and this record (§3).

## 3. Review of M4 and what changed

Each finding was checked against the code first. Every one held, at least in part, and every one was fixed or is
recorded as a gap.

| Finding | Severity | Disposition | Commit |
|---|---|---|---|
| Copy Diagnostics ran its hashing, log read and redaction on the main actor | HIGH | fixed: `collect` and `Diagnostics.build` are `@concurrent`; the log is read from 10 minutes back; a test checks the thread | `1a87764` |
| A missing fallback folder reset and then locked the output group | MEDIUM | fixed (D-M4-21) | `e5ba188` |
| Undo could run twice; the card kept offering trashed outputs and never left | MEDIUM | fixed in the result card and the action HUD; `UndoReply.removed` | `9ae314c`, `4b4bb2f` |
| Move to Applications quit even when the relaunch failed; the copy blocked the main thread and could leave a partial bundle | MEDIUM | fixed: copy off the main actor with a progress line, temporary name then rename, new instance, quit only on a new process | `e237fd0` |
| Borderless HUD panels could not become key (Escape, selectable details) | MEDIUM | fixed (D-M4-16). Escape works once the card is key, which is after a click into it (G-M4-10) | `b1a12b2`, `4b4bb2f` |
| Stale hover flag pinned toasts; size read before layout | MEDIUM | fixed | `4b4bb2f` |
| The cascade slot collided after a close; the spare panel was never rebuilt | MEDIUM | fixed | `f4a7750` |
| Reopened practice re-enabled the login item | MEDIUM | fixed | `b9bcc88` |
| The owner checklist had no rows for actions, app location, usability or hardware; `Scripts/m4-exit.sh` was missing | MEDIUM | fixed: `docs/plan/qa/actions.md`, `Scripts/m4-exit.sh` | `e9f1727`, `9501be3` |
| Matrix property checks that could never fail (one fixture per source) | MEDIUM | fixed: eight targeted cases (frames, pages, SVG page size, Web sRGB), exact PDF page check. The subset stays 24 pairs, against the plan's "about 40" (G-M4-9) | `9579e0f` |
| Pull-request code on a persistent self-hosted runner could poison the cache used by the signed build | HIGH | fixed in the repository (D-M4-20); the runner topology is O-4 | `602cf90` |
| Restored vendor outputs were trusted on their own say-so | MEDIUM | fixed: re-verified on unpack and checked again before a Release embed. Expected hashes kept outside the tarball are not done (G-M4-8); the release job now builds from source instead | `d01665b` |
| Source pins were trust on first use | MEDIUM | partly fixed (D-M4-24): signatures for ffmpeg and libwebp, second sources for every other pin except x264. The Rust toolchain and Homebrew tools are still unpinned (G-M4-6) | `eff4920` |
| Untrusted SVGs: unbounded CPU, cancel ignored, `panic = "abort"` | MEDIUM | fixed (D-M4-18). Measured in release: each review document now takes at most about 3 s or is refused; a render that has started cannot be cancelled (G-M4-4) | `9e232c7` |
| Embedded SVG raster images decoded with no limits | MEDIUM | fixed (D-M4-18): header-size caps, and the decode budget is charged | `9e232c7` |
| Neither the app nor the helpers were sandboxed | MEDIUM | helpers fixed (D-M4-19); the app itself is still unsandboxed (G-M4-7) | `b55f51f`, and the Release fix found by X1 |
| HUD text under 4.5:1 over light backdrops | MEDIUM | fixed by the model (D-M4-22); the on-screen measurement is owner row F1–F4 | `39cc413` |
| Hot-petal label under 4.5:1 | MEDIUM | fixed (D-M4-17); checked against the gradient model and the rendered solid wheel; on screen, owner row F5 | `7c9470f` |
| "Transparency was flattened" on every opaque RGBA image | MEDIUM | fixed (D-M4-23) | `ddbfa9f` |

What the review measured that the plan had not: resvg's filter costs in a release build at 8192 × 8192. One
full-canvas blur took 7.2 s, a blur with a deviation under 2 px (IIR) about 4 × that per pixel, turbulence 6.2 s plus
about 2.5 s per octave, a radius-5 morphology 65 s, a 3 × 3 convolution 4.9 s, lighting 2.5 s and a colour matrix
1.9 s. With the bound, the same documents render in 1.8–2.9 s at a lower edge (5,222 px for one blur, 2,553 px for
ten-octave turbulence, 1,170 px for a radius-50 morphology), and 200 stacked small blurs are refused.

## 4. Gates and exit rows (2026-10-22, macOS 27.0, Xcode 27, M2 Pro)

`Scripts/m4-exit.sh` (all rows, logs under `build/m4-exit/`):

| Row | Command | Result |
|---|---|---|
| X1 | `make vendor-test lint test coverage app release-check licence-gate` | pass on the second run: vendor and script tests, swift-format lint, 13 test bundles (917 tests), coverage 91–100 % per gated module (ZivletActions 91 %, ZivletUI 92 %, ZivletTriggerHost 92 %, all others ≥ 95 %), Debug app, Release build with no Homebrew path, 13 Mach-O files ad-hoc signed with hardened runtime, 41.1 MB installed, licences OK (13 components, 58 crates). The first run failed: the new sandbox profile put `/opt/homebrew` into the Release binary; fixed by naming it in Debug only (`fix(media): keep the Homebrew prefix out of the Release sandbox profile`) |
| X2 | `ZIVLET_FFMPEG_DIR=Vendor/out/media-stage/Helpers make smoke` | pass: 16 cases, 0 known issues |
| X3 | `ZIVLET_FFMPEG_DIR=/opt/homebrew/bin make smoke` | pass: 16 cases, 3 known issues (Homebrew lacks libvorbis and zscale, D-M3-6) |
| X4 | `ZIVLET_MATRIX=full make matrix` | pass: 161 pairs, 8 targeted cases, 13 hostile files, with the sandboxed helpers |
| X5 | `make fixtures-check` and `Vendor/repro-check.sh` | pass: 47 small fixtures match the manifest; two clean media builds give identical ffmpeg, ffprobe and libav* files |
| X6 | `make bench` | **fail** against the 10 % gate, twice: MOV → MP4 10.2 s and 11.4 s (baseline 8.97 s), tap → wheel p95 28.7 ms and 25.5 ms (baseline 19.3 ms); HEIC → JPEG 25–26 ms, drop → admit 0.7 ms, drop → HUD 10–14 ms, idle wake-ups 0. Not a code regression as far as measured: the same ffmpeg command without any sandbox also took 11.7 s at that time, the sandbox added under 1 %, and `mediaanalysisd` was using 135 % CPU (load average 6–14). Re-run on a quiet Mac before tagging (G-M4-11) |
| X7 | `make release-dry-run` | pass: ad-hoc dry run in `build/release` (DMG 12 MB, source bundle, SBOM with 70 packages, dSYMs); notarization and appcast skipped with the O-1 and O-2 messages |
| X8 | demo set through the Debug app | pass: jpg→png, png→webp, heic→jpg, mov→mp4, wav→mp3, mp4→webm each saved once through the Debug app (the Release app from the DMG is owner row E2) |
| X9 | no TCC request other than folder access | pass: no Accessibility, Input Monitoring or event-posting request while X8 ran |

Also run during the review: `make script-test` (every `Scripts/tests/*.sh`), the crate's own tests
(`cargo test --locked`: 13), `ZIVLET_MATRIX=subset make matrix` (24 pairs, 8 targeted cases, 13 hostile files), the full matrix (161 pairs)
with the sandboxed helpers, and `make fixtures-test`.

## 5. Decisions

D-M4-1 … D-M4-15 are the plan's ([10 §5](10-implementation-plan-m4.md)). The review added D-M4-16 … D-M4-24 to the
same table: the keyable HUD window, the legible hot-petal label, bounded SVG work, the helper sandbox, CI and cache
trust, path-only folder validation, the HUD scrim, the withdrawn transparency note, and source provenance. D-M4-7's
`panic = "abort"` is superseded by D-M4-18.

## 6. Known gaps

| ID | Gap | Where it goes |
|---|---|---|
| G-M4-1 | Owner steps O-1 … O-6 (§7): no Developer ID signature, notarization, Sparkle key, feed, runner, tag or human QA yet | owner |
| G-M4-2 | The real-hardware checklists (`qa/trigger.md`, `qa/actions.md`) are not run; the M3 R-rows still open (09 §8) stay open | O-6 |
| G-M4-3 | The scrim and label fixes are checked by model and by the rendered solid wheel, not measured on a real screen over white windows | O-6, actions.md F |
| G-M4-4 | An SVG render that has started cannot be cancelled (it runs to its end, at most about 3 s of filter work); there is no out-of-process render with a wall-clock or memory limit | P2-01 (XPC worker) |
| G-M4-5 | The cost model's numbers come from one Mac (M2 Pro); on an M1 Air the same budget means more seconds | measure with O-6 H2; adjust `WORK_BUDGET_NS` if needed |
| G-M4-6 | x264 is pinned to a GitLab archive of a commit, which has no second source and may not stay byte-identical; the Rust toolchain is checked by version string and the Homebrew build tools by presence only | M5: verify x264 by content against the commit, pin toolchains |
| G-M4-7 | The app itself is not sandboxed: ImageIO, libwebp and resvg decode untrusted files in-process | P2-01 (XPC worker), then the app sandbox |
| G-M4-8 | Restored vendor outputs are checked against their own stamps and hashes plus the media gate, but not against expected hashes kept outside the tarball; the release job builds from source instead | when builds are reproducible across hosts (X5) |
| G-M4-9 | The PR matrix subset is 24 pairs plus 8 targeted cases, not the plan's "about 40" pairs; the nightly full matrix covers all 161 | M5 if PR time allows |
| G-M4-10 | Escape closes a HUD card only once it is key (after a click into it), by design (D-M4-16) | — |
| G-M4-11 | `make bench` failed its 10 % gate on a loaded Mac (X6). After the exit run, `make bench` was made busy-aware (`Scripts/bench-guard.sh`, [perf/README](perf/README.md)): it samples the load first, waits up to 180 s for a busy Mac, then skips with status 3 and the busy process named, records the sample as `load` in its JSON, and `make m4-exit` shows X6 as `skipped (busy)`. The guard is tested with injected samples only; no benchmark has been run with it yet, so the quiet re-run is still open | re-run on a quiet Mac; if MOV → MP4 or tap → wheel still regress, bisect between `460c14e` and `main` |
| G-13, G-14 | plan size estimates, per-stage lanes, retry on worker crash; per-file gating on hover | P2-01, M5 (unchanged from the plan) |

## 7. Owner steps

| ID | Step | State |
|---|---|---|
| O-1 | Developer ID certificate, notary key, Team ID | open; scripts fail with the O-1 message |
| O-2 | Sparkle EdDSA key pair | open; updater off |
| O-3 | Final bundle id, domain, feed and download URLs | open; placeholders refuse `.invalid` |
| O-4 | Runners: `zivlet`, and `zivlet-release` on its own host and user with its own keychain and feed folder; approval required for workflows from outside contributors (D-M4-20) | open; `make ci-local` runs the CI steps locally |
| O-5 | Tester list; tag `v0.1.0-alpha` | open |
| O-6 | Human QA with `qa/trigger.md` and `qa/actions.md` (real drags, AirDrop, terminals, Move, app location, login item, contrast on screen, five testers, 120 Hz and M1 Air numbers, XCUITest) | open |
