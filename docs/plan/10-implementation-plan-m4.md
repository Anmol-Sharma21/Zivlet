# 10 — M4 implementation plan: Phase 1 complete (private alpha 0.1) (TDD)

Date: 2026-10-21. Status: ready to execute. Milestone: **M4** of [05 §2](05-task-list.md) ("Phase 1 complete (private
alpha 0.1)": all P1 tasks; 153 pairs green, tap → wheel p95 ≤ 16 ms at 120 Hz, no prompts other than folder prompts,
hostile corpus crash-free, notarized DMG + Sparkle stable channel). This file is the index: gap audit, toolchain,
prototype results, stream order, decisions and owner steps. The tasks are in eight parts, each under 800 lines:

| Part | Stream | Tasks |
|---|---|---|
| [10a](10a-m4-vendor-builds.md) | A — vendor builds | A1 lock + verified fetch · A2 tool check · A3 FFmpeg 9.0.2 + codecs · A4 stage + verify · A5 CWebP.xcframework · A6 zivlet-svg (resvg) · A7 cache/pack · A8 reproducibility |
| [10b](10b-m4-bundling-signing.md) | A — bundling and release gates | A9 binary targets · A10 helpers in `Contents/Helpers` + `Frameworks` · A11 helper signature check · A12 signing + signature gate · A13 licences + corresponding source · A14 size gate |
| [10c](10c-m4-image-media-engines.md) | B — engines | B1 WebP plan · B2 WebP writer · B3 SVG input · B4 image plan completion · B5 HDR/Vorbis fixes · B6 verifier + long-GIF note |
| [10d](10d-m4-actions.md) | C — actions | C1 requests · C2 Copy, Copy Path · C3 AirDrop · C4 Move + undo · C5 Move panel, Terminal · C6 action service · C7 wiring, FLOAT hidden |
| [10e](10e-m4-settings-menu-onboarding.md) | D — app shell, part 1 | D1 settings store · D2 settings wiring · D3 Settings window · D4 menu bar · D5 launch at login · D6 onboarding + practice |
| [10f](10f-m4-hud-feedback.md) | D — app shell, part 2 | D7 progress model · D8 HUD · D9 result card · D10 mode-switch tests + QA list · D11 sound/haptics |
| [10g](10g-m4-verification.md) | E — verification | E1 fixtures · E2 161-pair matrix · E3 hostile corpus + sniffing · E4 hardening gaps · E5 diagnostics · E6 bench · E7 flaky watch |
| [10h](10h-m4-release-exit.md) | F — release | F1 CI workflows · F2 Sparkle · F3 DMG · F4 notarize · F5 appcast + SBOM · F6 release.yml · F7 dry run · F8 M4 exit |

Inputs: [05-task-list](05-task-list.md) §4 (P1 rows) and §8, [09-m3-record](09-m3-record.md) (D-M3-*, G-1…G-18),
[03a](03a-system-design-interaction.md) §2.7, §3.2, §4.5–§4.8, [03b](03b-system-design-engines.md) §5–§8,
[04-tech-doc](04-tech-doc.md) §3, §6, [design/10](../design/10-tech-strategy.md) §8–§11,
[design/11](../design/11-media-engine.md) §7, §12, §14, [design/11a](../design/11a-media-build.md) §6,
[design/13](../design/13-image-pdf-engine.md) §2.3, §3.

Clean-room rule: unchanged from M1–M3. No code, assets, sounds or UI strings from the reference app or from
Open-Tangerine. Every sentence quoted in these parts is Zivlet's own wording (new ones are marked *new*). The tick is
synthesized by `ToneSynth`; the practice file is drawn by Zivlet at first run; the DMG has no third-party artwork.

---

## 0. Verification status of this plan

| Check | Result (2026-10-21, `main` at `5888294`, macOS 27.0 26A428, Xcode 27, M2 Pro 10-core, 16 GB) |
|---|---|
| `make test` on `main` | exit 0, nine bundles, **516 tests**: Wheel 65, WheelCore 55, Trigger 31, TriggerHost 27, Runtime 94, EngineKit 57, Core 59, EngineMedia 83, EngineImage 45 (M3 record said 40 for EngineImage; the 5 orientation tests of `4c5c82d` were added after its gate table) |
| Gap audit | every P1 row and G-n checked against the code (`grep` for the named types, reading `AppDelegate`, `StatusMenu`, `EngineLocator`, `ImageRoutes`, `ToneSynth`, `WheelFeedback`, the test suites), not against the docs (§1) |
| Prototypes | run in a scratch directory, outside the repository: FFmpeg 9.0.2 + 10 codec libraries, libwebp 1.6.0 xcframework, resvg 0.47.0 static library, Sparkle 2.10.0 measured; the existing 104-pair and smoke suites run against the bundled-layout build (§3) |
| Code in the parts | the build script in A3 and the crate in A6 ran as written except where the part says what changed; Swift test code in the parts is specification-grade and was **not** compiled in this session (types such as `ImageRig` helpers named there are created by the task). Each task's RED step therefore lists the expected compile error rather than a recorded one |

Not verifiable here: Developer ID signing, notarization, Gatekeeper on a clean VM, Sparkle updates (owner keys), real
drags, AirDrop, terminal apps other than Terminal, 120 Hz latency, usability testers (§7).

---

## 1. Gap audit

### 1.1 Phase 1 rows (05 §4; 45 rows) — status in the code today

| Row | Status | Evidence (code and tests at `5888294`) | M4 task |
|---|---|---|---|
| P1-01 EngineKit contracts | done (adapted, D-M3-4) | `Engine`, `ExecutionPlan`, `Stage.ffmpeg/.image`, weights validated | B1 adds `WebPOptions` to the image stage |
| P1-02 MediaInfo parser | done | `MediaProbe`, 15 tests, fixtures built in code | — |
| P1-03 Input confinement | done | probe `-protocol_whitelist file -format_whitelist`, run `-f <demuxer>`, `contentMismatch` | A3 also disables hls/dash/sdp/rtsp/rtp demuxers (P0-36); E3 adds sniffing |
| P1-04 Audio planner | done | goldens; Ogg forces libvorbis (gate tests) | — |
| P1-05 Video planner | done, one defect | goldens; prototype: HDR chain fails on an untagged stream (`no path between colorspaces`) | B5 |
| P1-06 GIF-input planner | done | goldens | — |
| P1-07 Progress parser | partial | `speed` parsed, ETA not surfaced (G-3) | D7 |
| P1-08 Image plan builder | partial | first frame only for animations, no Web (sRGB), gain maps or AVIF fallback (G-5, G-6) | B4 |
| P1-09 WebP plan builder | missing | `ImageRoutes.missing` returns `["libwebp"]` | B1 |
| P1-10 Images → PDF plan | done in `EngineImage` (D-M3-11) | `ImagePDFTests`, DCT pass-through | — |
| P1-11 Capability parsers | done | encoders/filters + ImageIO types; `-muxers` not parsed (all muxers used are core) | — |
| P1-12 Semaphore + lanes | done | `AsyncSemaphore`, `LaneLimits` tests | — |
| P1-13 Preflight + location | done | `DiskPreflight`, FAT32 image test | — (plan estimates: G-13, deferred) |
| P1-14 NameReserver | superseded (D-M3-2) | kernel `RENAME_EXCL`, 50 concurrent publishes | — |
| P1-15 UndoLog | partial | conversions only; no move entries, no menu "Recent Results" (G-7) | C4, D4 |
| P1-20 SubprocessRunner | done | `SubprocessRunner` tests | — |
| P1-21 EngineLocator | done in code, never exercised | bundled path unit-tested with injected URLs; no app has helpers yet | A10 |
| P1-22 Capability probe runner | done | cache tests, shared first probe | — |
| P1-23 MediaEngine + verifier | partial | no stream-count check; `isPlayable` only in tests (G-4) | B6 |
| P1-24 ImageEngine | partial | HEIC 12 MP signpost missing (G-9) | E6 |
| P1-25 libwebp + encoder | missing | no `Vendor/`, no `CWebP` | A5, A9, B2 |
| P1-26 Images → PDF (Quartz) | done in `EngineImage` | JPEG bytes embedded, page count/size verified | — |
| P1-30 Workspace + publisher | done; hardening open | `PublisherTests`; check-then-open window (G-16) | E4 |
| P1-31 JobScheduler | done | 200-file batch, cancel, quit tests | — |
| P1-32 OrphanReaper | partial | PID + path check; no start-time check (G-11) | E4 |
| P1-33 Drop → job wiring | done except `png → webp` | `ConversionService`, `DemoConversion`; webp row deferred by D-M3-8 | B2, F8 X8 |
| P1-40 Progress HUD | partial | `App/ResultHUD.swift` (360 × 132, progress, Cancel); no cascade, ETA, bytes, 50 ms signpost | D7, D8 |
| P1-41 Result card + Undo | partial | Undo, Reveal, failure copy; no thumbnail, sizes, Open, Copy, drag-out, details, Retry, hover hold | D9 |
| P1-42 Mode switching + cancel | mostly done | `glassEffectID` morph, Reduce Motion, re-tap close, Esc only while visible, Space change hides; no highlight-reset test, no `docs/plan/qa/trigger.md` | D10, O-6 |
| P1-43 Sound and haptics | partial | own synthesized tick (35 ms gate), haptics; no user toggles | D1, D2, D11 |
| P1-44 Copy, Copy Path, AirDrop | missing | `AppDelegate.handle` only logs `.action` | C1–C3, C6, C7 |
| P1-45 Move, Terminal | missing | — | C4–C7 |
| P1-46 Menu bar + Settings | partial | `StatusMenu`: counts, bindings line, Quit, DEBUG demo; no Settings, Practice, Pause, login item | D1–D5 |
| P1-47 Onboarding | missing | — | D6, O-6 |
| P1-48 Diagnostics | partial | 6 `Logger` categories, `check-log-privacy.sh`; no signposts, no Copy Diagnostics | E5 |
| P1-50 Bundle helpers | missing | no helpers in any build | A3, A4, A10, A11 |
| P1-51 Licence gate + source | partial | `THIRD_PARTY_NOTICES.md` planned table only | A13 |
| P1-52 Signature + size gates | missing | — | A12, A14 |
| P1-53 release.yml + Sparkle | missing | no `.github/workflows/` at all | F1–F6, O-1…O-4 |
| P1-60 Fixture generator | partial | lavfi synthesis inside the media tests | E1 |
| P1-61 Pair matrix | partial | 104 media pairs (real ffmpeg) + 43 raster pairs pass; webp and svg missing; no nightly | E2 |
| P1-62 Hostile corpus | partial | planner path/robustness tests; no hostile files | E3 |
| P1-63 Performance signposts | missing | — | E6, O-6 |
| P1-64 Real-drag QA | missing [QA][HW] | — | O-6 (checklist from D10) |
| P1-65 Alpha 0.1 | missing [OWNER] | — | F8, O-5 |

Summary: **18 done** (one with a defect fixed in B5, one superseded), **16 partial**, **11 missing**.

P0 rows that M4 depends on and that do not exist in this repository: P0-07 PR CI (→ F1), P0-36 vendor FFmpeg build
(→ A1–A4), P0-37 vendor workflow + reproducibility (→ A7, A8, F1), P0-38 signing + release dry run (→ A12, F7; the
notarized part is O-1).

### 1.2 M3 gaps (09 §7)

| Gap | Status today | M4 task / disposition |
|---|---|---|
| G-1 bundled helpers + signing checks | missing | A3, A4, A10, A11 |
| G-2 WebP output, SVG input | missing | A5, A6, A9, B1–B3 |
| G-3 ETA, bytes, stages; HUD list, cascade, 4 s hold, drag-out, thumbnail, sizes | partial (`speed` parsed) | D7, D8, D9 |
| G-4 stream count, `isPlayable` in the engine | missing | B6 |
| G-5 animation carried; multi-page TIFF → folder | missing | B4 |
| G-6 Web (sRGB), HDR gain maps, AVIF fallback, Compress | missing | B4; Compress is a tool (P2) and stays in M5 |
| G-7 undo for moves; menu Recent Results | missing | C4, D4 |
| G-8 content sniffing | missing | E3 |
| G-9 HEIC signpost | missing | E6 |
| G-10 announce Downloads fallback; cloud/SMB rename confirmation | missing | D9 (announce); the directory-watch confirmation is not a P1 acceptance → M5 |
| G-11 reaper start-time check, `Proxies/` trim | partial | E4 (start time); `Proxies/` does not exist until P2 previews |
| G-12 unreproduced wheel-test failure | watch (not seen in today's full run) | E7 |
| G-13 plan size estimates, per-stage lanes, retry on worker crash | partial (source-size estimate + `-fs` cap) | deferred to P2-01 (XPC worker); not a P1 acceptance |
| G-14 per-file gating on hover | missing | deferred to M5 with hover probes (03a §3.4 step 5); not a P1 acceptance |
| G-15 process-wide decode budget | missing | E4 |
| G-16 staging without a check-then-open window | partial (D-M3-26 checks) | E4 (private 0700 staging directory) |
| G-17 long video → GIF warning | missing | B6 |
| G-18 raise `RLIMIT_NOFILE` | missing | E4 |

---

## 2. Toolchain on the dev Mac (2026-10-21)

| Tool | Version | Source | Needed for | Action taken |
|---|---|---|---|---|
| Xcode / clang | Xcode 27, Apple clang 21.0.0, SDK MacOSX27.0 | `/Applications/Xcode.app` | everything | — |
| pkgconf (`pkg-config`) | 3.0.7 | Homebrew | FFmpeg configure | present |
| GNU libtool (`glibtool`, `glibtoolize`) | 2.6.2 | Homebrew | zimg `autogen.sh` (`LIBTOOLIZE=glibtoolize`) | present |
| cmake | 4.4.4 | Homebrew | SVT-AV1, Opus, libwebp | **installed** (`brew install`) |
| meson | 1.12.1 | Homebrew | dav1d | **installed** |
| ninja | 1.13.2 | Homebrew | cmake/meson backend | **installed** |
| autoconf / automake | 2.73 / 1.19 | Homebrew | zimg | **installed** |
| nasm | 3.02 | Homebrew | not needed on arm64 (installed with the batch; no build invoked it) | installed |
| yasm | — | — | not needed on arm64 | not installed |
| cargo / rustc | 1.96.0 (Homebrew) | Homebrew | zivlet-svg (resvg) | present; pinned by `Vendor/rust-toolchain.txt` (no rustup) |
| xcodegen | 2.45.4 | Homebrew | project | present |
| git-lfs | — | — | not needed (D-M4-15) | not installed |
| create-dmg | — | — | not needed (`hdiutil`, F3) | not installed |
| Homebrew ffmpeg | 8.1.2 | Homebrew | Debug fallback and `make smoke` owner gate (lacks libvorbis, zscale) | present |
| Ruby (system) | `/usr/bin/ruby` with `yaml` | macOS | workflow lint (F1) | present |

Disk: 17–20 GiB free during the session; a full vendor tree needs about 0.5 GB (451 MB measured).

---

## 3. Prototype results

All prototypes ran under the session scratch directory; downloads went to `Vendor/downloads/<name>-<version>/`
(ignored locally through `.git/info/exclude` until A1 adds it to `.gitignore`), each in its own directory, extracted
into separate source directories, SHA-256 recorded (the three Xiph tarballs also matched Xiph's published
`SHA256SUMS`).

### 3.1 FFmpeg 9.0.2 GPLv3 with codecs folded in

| Component | Build time (clean, 10 cores) | Notes |
|---|---|---|
| x264 @ b35605ac (stable) | 8 s | |
| libvpx 1.17.0 | 15 s | `arm64-darwin25-gcc` target exists in its configure |
| SVT-AV1 4.2.0 | 25 s | |
| dav1d 1.5.4 | 4 s | |
| Opus 1.6.1 | 4 s | |
| libogg 1.3.6 / libvorbis 1.3.7 | 8 s / 8 s | vorbis needs `-force_cpusubtype_ALL` removed |
| LAME 3.100 | 13 s | **failed first**: `memset`/`bcopy` undeclared because configure's STDC check fails under modern clang → `ac_cv_header_stdc=yes` (D-M4-4) |
| libwebp 1.6.0 | 4 s | |
| zimg 3.0.6 | 16 s | |
| FFmpeg 9.0.2 | 76 s | **failed twice first**: host-compiler check without a sysroot (→ `SDKROOT`), undefined `_iconv*` (→ `--extra-libs=-liconv`) (D-M4-4) |
| **Total** | **181 s** | work tree 451 MB |

Library versions are FFmpeg 9's: `libavcodec.63`, `libavformat.63`, `libavfilter.12`, `libavutil.61`, `libswscale.10`,
`libswresample.7`, `libavdevice.63` (11 §7.1 lists FFmpeg 8 numbers; D-M4-1). All binaries: arm64 only, `minos 26.0`,
`sdk 27.0`; dependencies only `@rpath/…`, `/usr/lib/…` and `/System/Library/…` (libz, libbz2, libiconv, libc++,
VideoToolbox, AudioToolbox, CoreMedia, CoreVideo, CoreFoundation, CoreServices); `LC_RPATH
@executable_path/../Frameworks`; `-buildconf` has no `nonfree`; `-L` says GPL v3.

Path leaks: the first build embedded build paths through FFmpeg's configuration string (in every library) and
libvpx's `vpx_codec_build_config`; `-ffile-prefix-map` does not touch those. Scrubbing `config.h` and `vpx_config.c`
after configure (D-M4-3) brought every binary to **0** matches for `/Users/`, `/private/tmp/`, `/var/folders/`,
`/opt/homebrew`.

`--disable-devices` alone removed `lavfi`, which every fixture recipe uses; the build keeps exactly one input device,
`lavfi` (D-M4-2).

### 3.2 Sizes (stripped with `strip -x`, ad-hoc signed)

| Part | Full encoder set | Encoder allow-list + hostile demuxers off |
|---|---|---|
| `ffmpeg` + `ffprobe` | 396 + 196 KB | ≈ same |
| `libavcodec.63` | 21,532 KB | 20,608 KB |
| `libavfilter.12` | 4,340 KB | 4,364 KB |
| `libavformat.63` | 2,264 KB | 2,228 KB |
| `libswscale.10` / `libavutil.61` / `libswresample.7` / `libavdevice.63` | 1,168 / 724 / 104 / 44 KB | same |
| **Helpers + Frameworks installed** | **30,792 KB (30.07 MiB)** | **29,700 KB (29.0 MiB)** |
| zip / ULMO DMG of that tree | 14.1 MB / 10.97 MB | — / 10.53 MB |

05 P0-36 sets "stripped size ≤ 30 MB": the full set is 0.07 MiB over, the allow-list is under. The allow-list build
lacked `mov_text` because FFmpeg's configure name is `movtext` (1 smoke case became a known issue); A3/A4 fix the name
and check runtime names. Other parts: libwebp in a stripped test executable 0.50 MB total; resvg +2.15 MB linked;
Sparkle.framework 2.9 MB universal; current Release app 3.4 MB. **Projected installed app ≈ 38–40 MB, DMG ≈ 16–18 MB**
(gate: 85 / 40 MB hard, 70 / 32 warn).

### 3.3 resvg 0.47.0 static library (`zivlet-svg`)

Build: 32 s first time (crate download + compile, while FFmpeg built in parallel), 18 s clean recompile, static
library 4.4 MB, linked +2.15 MB; objects `minos 26.0`; no build paths after `--remap-path-prefix`. Behaviour: 120 × 80
gradient + Helvetica text → 240 × 160 at scale 2; 100,000 × 100,000 → 8192 × 8192; `not svg` → error 1; a `file`
image href was not drawn while a `data:` PNG was. First render in a process 0.65 s (system font database, cold),
under 0.05 s afterwards. The prototype source, which A6 adopts (plus a 64 MiB input cap and a size-only call):

```rust
//! C ABI for SVG → RGBA rendering. Only `data:` image hrefs resolve; no file or network access.
use std::sync::OnceLock;

#[repr(C)]
pub struct ZivletSvgImage { pub width: u32, pub height: u32, pub rgba: *mut u8 } // premultiplied RGBA8

pub const ZIVLET_SVG_OK: i32 = 0;
pub const ZIVLET_SVG_PARSE: i32 = 1;
pub const ZIVLET_SVG_SIZE: i32 = 2;
pub const ZIVLET_SVG_ALLOC: i32 = 3;
pub const ZIVLET_SVG_ARGUMENT: i32 = 4;

fn fonts() -> &'static std::sync::Arc<resvg::usvg::fontdb::Database> {
    static DB: OnceLock<std::sync::Arc<resvg::usvg::fontdb::Database>> = OnceLock::new();
    DB.get_or_init(|| {
        let mut db = resvg::usvg::fontdb::Database::new();
        db.load_system_fonts();
        std::sync::Arc::new(db)
    })
}

fn options() -> resvg::usvg::Options<'static> {
    let mut opt = resvg::usvg::Options::default();
    opt.resources_dir = None;
    opt.fontdb = fonts().clone();
    opt.image_href_resolver = resvg::usvg::ImageHrefResolver {
        resolve_data: resvg::usvg::ImageHrefResolver::default_data_resolver(),
        resolve_string: Box::new(|_, _| None),
    };
    opt
}

/// Renders `len` bytes of SVG at `scale` with the longest edge capped at `max_edge`.
#[no_mangle]
pub unsafe extern "C" fn zivlet_svg_render(
    data: *const u8, len: usize, scale: f32, max_edge: u32, out: *mut ZivletSvgImage,
) -> i32 {
    if data.is_null() || out.is_null() || !(scale > 0.0) || max_edge == 0 { return ZIVLET_SVG_ARGUMENT; }
    let bytes = std::slice::from_raw_parts(data, len);
    let tree = match resvg::usvg::Tree::from_data(bytes, &options()) { Ok(t) => t, Err(_) => return ZIVLET_SVG_PARSE };
    let size = tree.size();
    let longest = size.width().max(size.height()) * scale;
    let s = if longest > max_edge as f32 { max_edge as f32 / size.width().max(size.height()) } else { scale };
    let w = (size.width() * s).ceil() as u32;
    let h = (size.height() * s).ceil() as u32;
    if w == 0 || h == 0 { return ZIVLET_SVG_SIZE; }
    let mut pixmap = match resvg::tiny_skia::Pixmap::new(w, h) { Some(p) => p, None => return ZIVLET_SVG_ALLOC };
    resvg::render(&tree, resvg::tiny_skia::Transform::from_scale(s, s), &mut pixmap.as_mut());
    let mut data = pixmap.take().into_boxed_slice();
    let ptr = data.as_mut_ptr();
    std::mem::forget(data);
    *out = ZivletSvgImage { width: w, height: h, rgba: ptr };
    ZIVLET_SVG_OK
}

#[no_mangle]
pub unsafe extern "C" fn zivlet_svg_free(image: *mut ZivletSvgImage) {
    if image.is_null() || (*image).rgba.is_null() { return; }
    let n = ((*image).width as usize) * ((*image).height as usize) * 4;
    drop(Box::from_raw(std::slice::from_raw_parts_mut((*image).rgba, n)));
    (*image).rgba = std::ptr::null_mut();
}
```

resvg 0.48.1 is the newest release; 0.47.0 is kept because krilla-svg 0.8.1 (P2-10) shares usvg 0.47 (10 §3).
krilla was skipped: SVG → PDF is a raster page for now (D-M4-6).

### 3.4 Reproducibility

Two clean builds in different directories: `ffmpeg`, `ffprobe`, `libavformat`, `libavutil` byte-identical;
`libavcodec` differed (after `strip -x`, 49 bytes: `LC_UUID`, the linker's ad-hoc signature and a few more). Every
static archive differed because `ZERO_AR_DATE` was not set. A3 sets it; A8 proves or records the rest.

### 3.5 libwebp 1.6.0 xcframework

`libCWebP.a` (webp + mux + demux + sharpyuv) → `CWebP.xcframework`, 836 KB, packaged in 2 s; a SwiftPM
`.binaryTarget(path:)` pointing outside the package directory builds (checked). From Swift: `WebPEncode` still with
alpha + sharp YUV (1,256 bytes for 320 × 200), `WebPMuxSetChunk("ICCP")`, 5-frame `WebPAnimEncoder` (6,060 bytes);
ImageIO reads all three as `org.webmproject.webp` with 1/1/5 frames. ImageIO writable types on this Mac include
`public.heics` and `public.avif`, not WebP.

### 3.6 Media pair matrix with the bundled-layout build

Helpers laid out as `Zivlet.app/Contents/{Helpers,Frameworks}` and used through `ZIVLET_FFMPEG_DIR` (so the rpath
resolution inside the bundle is exercised), in a scratch copy of the package:

| Run | Result |
|---|---|
| Unchanged tests, `--disable-devices` build | everything failed: `-f lavfi` unavailable → D-M4-2 |
| Unchanged tests, lavfi kept | 104 pairs pass, but 7 `ogg → *` pairs were known issues (fixture used the native `vorbis` encoder, disabled in our build) and the HDR smoke case was a known issue (fixture needs `libx265`, not in our build) |
| Fixtures changed as in B5, plus an assertion that no pair is gated off | **104 / 104 media pairs pass, 0 gated off, 0 known issues** (ogg in and out, VP9/Opus WebM, MP4/MOV playable); smoke **15 / 15** once the HDR fixture is tagged in the bitstream. An untagged HDR fixture made the planned chain fail with zscale "no path between colorspaces" → B5 hardening |
| Allow-list build, same tests | 104 / 104; smoke 14 + 1 known issue (`movtext` name, §3.2) |

So the bundled build covers what Homebrew's lacks: `libvorbis` (ogg) and `zscale` (HDR → SDR). Raster pairs (43
today) do not use ffmpeg.

### 3.7 Sparkle

Sparkle 2.10.0 (2026-09-13): tarball SHA-256 recorded in A1; `Sparkle.framework` 2.9 MB universal; tools
`generate_appcast`, `sign_update`, `generate_keys`, `BinaryDelta` in `bin/`.

---

## 4. Streams, order and estimate

### 4.1 Dependencies

```text
A1 → A2 → A3 → A4 ─────────────┬──→ A10 → A11 → A12 → A13 → A14 ──→ F3 → F4 → F5 → F6 → F7 → F8
      └→ A5 ─┐                  │                                     ↑
      └→ A6 ─┴→ A9 → B1 → B2 ───┼──→ E2 (matrix) ─────────────────────┤
                    └→ B3 ──────┤                                     │
             A3/A4 → B5, B6 ────┘   E1 → E2 → E3                      │
B4 (after B2)                       E4, E5, E6, E7 (independent)      │
C1 → C2, C3, C4 → C5 → C6 → C7 (C7 after D2: both edit AppDelegate)  │
D1 → D2 → D3, D4, D5 → D6;  D7 → D8 → D9;  D10, D11 (any time) ───────┘
F1 (any time after A7) · F2 (after D3)
```

### 4.2 Recommended order (one agent) or split (parallel agents)

1. **Wave 1** (no shared files): A1–A4 (vendor) ∥ C1–C4 (actions core) ∥ D1, D7 (settings and progress values) ∥ E4
   (hardening) ∥ E5.
2. **Wave 2**: A5, A6, A9 → B1–B3, B5, B6 ∥ D2–D5, D8 ∥ C5, C6 ∥ E1.
3. **Wave 3**: A10–A14 ∥ B4 ∥ D6, D9–D11 ∥ C7 ∥ E2, E3, E6, E7 ∥ F1, F2.
4. **Wave 4**: F3–F7, then F8 automated exit; then the owner steps.

Merge points that need care: `Package.swift` (A9, C1, D1, E1, E2 each add targets — rebase, never reorder existing
targets), `App/AppDelegate.swift` (D2, C7, D6, F2 — keep it a composition root; new wiring goes into
`App/*Wiring.swift` files), `Scripts/coverage.sh` `GATED_MODULES`, `Makefile`.

### 4.3 Estimate (ESTIMATE)

| Stream | 05 sizing (S = 1 d, M = 3 d, L = 7.5 d; minus work already done) |
|---|---|
| A vendor, bundling, gates | ≈ 15 engineer-days (A3 recipe proven: ≈ 1.5 d left of its M) |
| B engines | ≈ 12 |
| C actions | ≈ 9 |
| D app shell and HUD | ≈ 16 |
| E verification and hardening | ≈ 14 |
| F release pipeline (to the owner steps) | ≈ 10 |
| **Total** | **≈ 76 engineer-days**; critical path A1 → A3 → A4 → A10 → A12 → F6 ≈ 15 days of it |

At the pace M2 and M3 were executed by agents in this repository (both plans written and implemented on 2026-10-21),
streams A–F should reach "code complete, automated exit X1–X9 green" in **about 2–4 agent work sessions**. That is an
extrapolation, not a measurement: M4 has more UI (Settings, onboarding, card) that needs screenshots and manual looks,
and the vendor build adds 3 minutes per clean run. The alpha itself waits on the owner steps in §7, which have no
estimate here.

---

## 5. Decisions (D-M4-n)

| ID | Decision | Why |
|---|---|---|
| D-M4-1 | FFmpeg **9.0.2**; libraries `avcodec.63`, `avformat.63`, `avfilter.12`, `avutil.61`, `swscale.10`, `swresample.7`, `avdevice.63` | Measured (§3.1); 11 §7.1's numbers are FFmpeg 8's |
| D-M4-2 | Encoders by allow-list (`Vendor/encoders.txt`, configure names); native `opus`/`vorbis` encoders off; demuxers `hls,dash,webm_dash_manifest,sdp,rtsp,rtp` off (P0-36); **one input device, `lavfi`** | Smaller (29.0 MiB vs 30.07) and only the encoders the planners use; fixtures and the matrix must run on the shipped binary; a hostile file cannot select lavfi because run argv forces `-f <demuxer>` and the probe has `-format_whitelist` (E3 adds a test that a lavfi graph saved as `.mp4` is refused) |
| D-M4-3 | Scrub build paths from FFmpeg's `config.h` and libvpx's `vpx_config.c` after configure | `-ffile-prefix-map` does not cover compiled-in configure strings (§3.1) |
| D-M4-4 | Recipe fixes: `SDKROOT` exported, `--extra-libs=-liconv`, `--build` = `--host` for autotools, `ac_cv_header_stdc=yes` for LAME, `ZERO_AR_DATE=1` | Each was a real failure or difference in the prototype |
| D-M4-5 | Vendor layout under `Vendor/` (04 §6 wins over 11a's `scripts/media/`): `versions.lock`, `fetch.sh`, `build-*.sh`, `downloads/`, `src/`, `build/`, `prefix/`, `out/`, `rs/` | One place; 04 is the newer layout |
| D-M4-6 | SVG input pulled forward from P2-10/P2-11 (resvg only): 7 raster targets; svg → pdf is one raster page at 2× with a card note until krilla-svg (P2-10) gives vector PDF | The M4 brief asks for SVG input; krilla is the heavy part and not needed for raster targets |
| D-M4-7 | `Vendor/rs/zivlet-svg`: our own crate (GPL-3.0-or-later), resvg `=0.47.0` with `text, system-fonts, memmap-fonts, raster-images`; `data:`-only image hrefs; `panic = "abort"` (superseded by D-M4-18: unwind, caught at the C boundary); `Cargo.lock` committed; crates downloaded into `Vendor/downloads/cargo-home`; Rust 1.96.0 from Homebrew pinned by a version check (no rustup) | Deterministic and contained (§3.3) |
| D-M4-8 | WebP is written in-process by libwebp inside the existing `.image` stage (`ImagePipelineSpec.webp`), not a new stage kind | Same decode path, orientation policy and verifier as other rasters |
| D-M4-9 | `CWebP` and `CZivletSVG` are SwiftPM binary targets pointing at `Vendor/out`, built on demand by `Vendor/ensure-native.sh` before `make test/app/coverage` (≈ 25 s on a clean clone) | No binaries committed; a clean clone still builds with the documented Homebrew tools |
| D-M4-10 | Helpers embedded and signed by one post-build script (`embed-helpers.sh` → `sign-app.sh --helpers-only`), not XcodeGen Copy Files + Code Sign On Copy; Debug without a vendor stage warns and falls back to `ZIVLET_FFMPEG_DIR`/Homebrew, Release fails | One signing path for Xcode and the release workflow (11 §7.2 asks to check Xcode's copies anyway) |
| D-M4-11 | Sparkle 2.10.0 via SwiftPM; feed URL placeholder `https://updates.zivlet.invalid/stable/appcast.xml` and empty public key → updater not started, menu item disabled; XPC services stripped (not sandboxed), framework thinned to arm64 | Nothing can reach a network before the owner sets the real feed and key; `.invalid` is reserved and never resolves |
| D-M4-12 | HDR tone-map chain names its input (`tin`, `min`, `pin`) from `MediaInfo`; Vorbis and HDR test fixtures made with `libvorbis` and tagged `hevc_videotoolbox` main10 | Found by the prototype matrix (§3.6) |
| D-M4-13 | FLOAT petal hidden (`CapabilitySnapshot.unavailableActions`) until the shelf (P2-55); the Phase 1 actions wheel shows five | Phase 1 scope is 5 actions (05 §4) |
| D-M4-14 | XCUITest target exists but is owner-run until a runner can grant automation permission; card behaviour is covered by model + snapshot tests | XCUITest needs an Accessibility/automation grant this environment cannot give |
| D-M4-15 | Fixtures are generated deterministically, hash-checked against committed manifests when the vendored ffmpeg is used; nothing binary is committed and no Git LFS | 05 P1-60 asked for LFS for a large set; determinism makes storage unnecessary |
| D-M4-16 | HUD panels are a `HUDWindow`: borderless and non-activating, but able to become key, with `becomesKeyOnlyIfNeeded` | A borderless window cannot become key, so Escape and the selectable details did nothing; a click into the details now makes the card key, while a button click never takes the keyboard from the person's app (review fix) |
| D-M4-17 | The hot-petal label is white or black by the better worst case over the painted gradient; when neither reaches 4.5:1, light and dark move toward base in steps of 0.1; the Glass highlight is opaque | A label can sit over most of the petal; a flat base always reaches 4.58:1 with one of the two (FR-26, review fix) |
| D-M4-18 | zivlet-svg bounds its work: a per-primitive cost model (ns per filtered pixel, measured in release on an M2 Pro), about 3 s of filter work, the longest edge lowered to 256 px at the lowest, else refused; embedded raster images ≤ 64, each ≤ 50 MP, ≤ 200 MP in total by header; `zivlet_svg_probe` gives the planned edge and the largest image (charged to the decode budget); panics unwind and are caught at each C entry point | resvg's filters cannot be cancelled and a few hundred bytes of SVG took 7–65 s; a render that has started still runs to its end (≤ about 3 s) |
| D-M4-19 | ffprobe and every ffmpeg pass run through `/usr/bin/sandbox-exec` with a per-job profile: deny by default, `system.sb`, read the helper's folder and the `-i` inputs, write only the job's `.zivlet-<job>` folder, Mach and IOKit for VideoToolbox, no network | The helpers parse untrusted media; the app itself stays unsandboxed (G-M4-7). The reaper accepts a launcher record when the same PID and start time now run ffmpeg or ffprobe |
| D-M4-20 | CI: pull requests from forks never run on the self-hosted runner; only main's pushes and schedules write the vendor cache; the release job builds every vendor output from source and keeps its appcast feed in a release-only folder; every component cache key covers the driving scripts; restored outputs are re-verified (stamps, tree hashes, verify-media) and Release embeds only a stage whose stamp is current and that passes verify-media | A persistent runner with a shared cache could otherwise take a PR's outputs into a signed build (review fix); the runner topology is O-4 |
| D-M4-21 | The settings store checks only that the fallback folder is an absolute path; `JobRequestFactory` uses Downloads when the chosen folder is gone or read-only | An unplugged drive used to reset and then lock the whole output group (review fix) |
| D-M4-22 | HUD text sits on a colour-scheme scrim (black or white at 0.65) under the glass; secondary text is the primary colour at 0.8 instead of `.secondary` | 4.5:1 or better even when the glass lets a white or black backdrop through untouched (NFR-14, review fix) |
| D-M4-23 | "Transparency was flattened onto white." is planned from the alpha channel and withdrawn after the run when no flattened pixel was transparent (`StagedOutput.withdrawnNotes`) | An alpha channel alone (every screenshot) made the note appear on the most common conversion (review fix) |
| D-M4-24 | Source pins get a second, independent check: OpenPGP signatures for ffmpeg and libwebp (`Vendor/verify-sources.sh`, committed keys and fingerprints), and other published hashes for the rest (`Vendor/PROVENANCE.md`) | The SHA-256 pins alone were trust on first use (review fix); x264 and the toolchains stay open (G-M4-6) |

---

## 6. Conventions

| Item | Rule |
|---|---|
| Environment | `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` before every `swift`, `xcodebuild`, `make` |
| TDD | Each task: failing test (or failing script test under `Vendor/tests/`, `Scripts/tests/`, `Fixtures/tests/`) → run and see the stated failure → implement → green → commit. Shell tests use `Vendor/tests/lib.sh` asserts |
| Gates after every task | `make test lint` (and `make coverage` when a gated module changed); vendor tasks also `make vendor-test` |
| Full gate list (M4) | `make test`, `make lint`, `make coverage` (80 % per module; 13 modules after M4), `make app`, `make release-check`, `ZIVLET_FFMPEG_DIR=/opt/homebrew/bin make smoke`, plus new: `make vendor-test`, `make licence-gate`, `ZIVLET_MATRIX=subset make matrix`, `make fixtures-check`, `bash Scripts/tests/*.sh` |
| Commits | Conventional, `git commit -s`, no `Co-Authored-By`; types feat, fix, refactor, docs, test, chore, perf, ci; scopes as used in the parts (`vendor`, `engine`, `media`, `image`, `runtime`, `actions`, `settings`, `ui`, `updates`, `app`, `release`, `fixtures`, `matrix`, `hostile`, `perf`) |
| Code rules | Immutable values (copies via `with`), files < 800 lines (aim 200–400), functions < 50 lines, nesting ≤ 4, no `print`, typed errors with Zivlet's own user copy, validation at boundaries (lock lines, settings, URLs, SVG size, Team ID) |
| Public repo | No reference to private working notes or personal paths in code, docs or commit messages; generated files under `Vendor/out`, `build/` only; downloads stay in `Vendor/downloads` (ignored) |
| Push | Not before the Verify phase |
| Build caches | Clean only with the project's scripts (`Vendor/` work dirs, `build/`); never user data |

---

## 7. Owner steps

| ID | Step | What the agent prepares | What unblocks |
|---|---|---|---|
| O-1 | Developer ID Application certificate in the release runner's keychain; App Store Connect API key or `notarytool store-credentials zivlet-notary`; Team ID into `Config/Signing.xcconfig` (ignored) or the `release` environment | `sign-app.sh`, `verify-signatures.sh --require-developer-id`, `notarize.sh` with the O-1 message, `release.yml` dry-run path | notarized app + DMG, `spctl` acceptance, helper Team-ID requirement (A11) in force |
| O-2 | Sparkle EdDSA key: run `generate_keys` (from `Vendor/out/sparkle-tools`), back the private key up offline, add it as `SPARKLE_ED_PRIVATE_KEY` to the `release` environment, put the public key into `Config/Release.xcconfig` `SPARKLE_PUBLIC_ED_KEY` | F2 config validation, F5 appcast script with the O-2 message | signed appcast, updater enabled |
| O-3 | Final bundle id / domain (O-10), feed URL and download URL prefix (`ZIVLET_FEED_URL`, `ZIVLET_DOWNLOAD_URL_PREFIX`) | placeholders in xcconfig, validation refuses `.invalid` | real feed; must be final before the first Sparkle-enabled build |
| O-4 | Register self-hosted runners: `zivlet` on the owner's Mac or a Tart host, and `zivlet-release` on a separate host and macOS user with its own keychain, workspace and `ZIVLET_RELEASE_FEED_DIR` (never sharing `RUNNER_TOOL_CACHE` with `zivlet`, D-M4-20); in the repository settings require approval for workflows from outside contributors; Tart images for macOS 26.0 / 26.x / 27.x | `ci.yml`, `nightly.yml`, `vendor.yml`, `release.yml`, `vm-smoke.sh`, `make ci-local` | CI and nightly run on GitHub; Gatekeeper smoke on 26.0 |
| O-5 | Private tester list; decide and push tag `v0.1.0-alpha` | `release.yml` drafts the release; release notes draft | alpha 0.1 (P1-65) |
| O-6 | Human QA on real hardware with `docs/plan/qa/trigger.md` and `docs/plan/qa/actions.md`: real-drag matrix (P1-64); onboarding usability, 5 of 5 testers (P1-47); AirDrop to a real device; each terminal (P-TERM); Move Here panel and cross-volume move; launch at login from `/Applications`; 120 Hz tap → wheel p95 ≤ 16 ms and M1 Air numbers (P1-63); the M3 R-rows still open (09 §8); XCUITest run (D-M4-14) | checklists, DEBUG demo arguments, bench script, UI test target | M4 exit rows that CI cannot do |

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| Disk space on the dev Mac (17–20 GiB free) | Vendor tree 0.5 GB; keep one work tree; `Vendor/repro-check.sh` uses two temporary trees and removes them |
| Upstream tarball moved or changed | Hash mismatch fails the fetch; the source bundle keeps copies for the GPL obligation |
| Xcode/SDK update changes binaries | Cache key includes `xcodebuild -version`; nightly repro check |
| WebP or SVG decoders crash on hostile input in-process | Hostile corpus (E3) covers both; XPC isolation is P2-01; decode budget (E4) |
| Size creep (Sparkle, resvg) | A14 gate; Sparkle thinned and XPC services stripped |
| UI work cannot be fully verified unattended | Model + snapshot tests; owner QA rows are explicit (O-6) |

---

## 9. Definition of done for this plan

- [ ] Tasks A1–F7 committed in order within each stream, each with its own signed conventional commit.
- [ ] F8 automated rows X1–X9 pass on the dev Mac; numbers recorded in the M4 record (`docs/plan/11-m4-record.md`).
- [ ] Coverage ≥ 80 % for all 13 gated modules; `make lint` clean; no file over 800 lines.
- [ ] `THIRD_PARTY_NOTICES.md` lists every bundled component as Present, with licence texts in the app.
- [ ] Owner steps O-1…O-6 listed in the record with their state; M4 is "complete" only when they are done.
