# 11. Media engine: audio, video, GIF (and the media side of WebP/AVIF)

Date: 2026-10-20. Status: design proposal for decision.
Scope: every audio and video conversion, every GIF route, and every media file tool (compress, trim, split, join, speed, snapshots, crop, mute, redact video, normalize, trim silence, bleep, channels, visualizer, media metadata). Still-image WebP/AVIF encoding belongs to the image engine (separate doc). This doc covers only the parts of WebP/AVIF that touch ffmpeg (animated WebP, AV1 encoders, fallbacks).

Inputs read for context: `docs/design/00-decisions.md` and Zivlet's product scope (format matrix, tool list). Nothing here copies code from the reference app or Open-Tangerine. Their public behavior is only used as a baseline to beat.

Evidence labels: **VERIFIED-LOCAL** means it was run on this machine (Apple M2 Pro, macOS 27.0 build 26A428, Homebrew ffmpeg 8.1.2). **VERIFIED-UPSTREAM** means it was checked against upstream source, tags or release pages on 2026-10-20. **INFERRED** means engineering judgement. **SPIKE** means it must be measured before the decision is final.

---

## 0. TL;DR

- **Choose (a): bundle our own ffmpeg + ffprobe**, built from source (pinned, reproducible, arm64, macOS 26 minimum). Configure as **GPLv3** (`--enable-gpl --enable-version3`, never `--enable-nonfree`) with libx264, libvpx (VP8/VP9), SVT-AV1, dav1d, libopus, libvorbis/libogg, LAME, libwebp, zimg, VideoToolbox and AudioToolbox. Leave x265 and libaom out of v1. They are optional build flags.
- Ship it as **7 shared libav\* dylibs in `Contents/Frameworks` plus 2 thin executables in `Contents/Helpers`**. The codec libraries are folded statically into libavcodec. Estimated size is about 25 MB uncompressed and about 10–12 MB in the DMG. It carries every encoder we advertise.
- **Run it as a child process** using `swift-subprocess` 1.0.x (or `Foundation.Process`). Read progress from `-progress pipe:1 -stats_period 0.25 -nostats`. Cancel with SIGTERM, then SIGKILL after 2 s, using the package's teardown sequence. Each job gets its own temp directory, and the result is published to the source folder with an atomic rename.
- **Don't link libav\* in-process (b).** FFmpegKit was retired in January 2025. The surviving Swift wrappers either target players (kingslay/FFmpegKit, MPVKit) or are thin C-API wrappers (SwiftFFmpeg). Any of them would mean rewriting fftools' transcode pipeline and losing crash isolation.
- **Don't make AVFoundation the conversion engine (c).** AVFoundation plus AudioToolbox can do only about 20 of the 104 audio/video/GIF pairs (about 19%), and a second pipeline doubles the test matrix. AVFoundation *is* the right choice for the **UI**: AVPlayer previews in tool windows, thumbnails, scrubbing and waveforms. Formats AVFoundation can't play get a fast ffmpeg proxy (a remux, or a 540p VideoToolbox transcode).
- **Hardware first.** Use `h264_videotoolbox`, `hevc_videotoolbox` and `prores_videotoolbox` for MP4/MOV/MKV. No Apple silicon has a VideoToolbox AV1 or VP9 encoder (VERIFIED-LOCAL on M2 Pro; no evidence of one for M3–M5), so WebM uses libvpx-vp9 (default) or SVT-AV1 (option).
- **Make every advertised route work, WebM included.** Every advertised encoder is linked in. A cached `-encoders` probe gates routes. CI encodes every advertised pair against a fixture corpus.

---

## 1. Requirements this engine must satisfy

### 1.1 Format scope (Zivlet product scope)

| Group | Inputs | Outputs | Pairs |
|---|---|---|---|
| Audio | mp3 m4a wav flac ogg opus aiff wma | each of the other 7 | 56 |
| Video | mp4 mov mkv webm avi wmv | the other 5 video formats + gif + mp3 | 42 |
| GIF (treated as video) | gif | mp4 mov mkv webm avi wmv | 6 |
| **Total through this engine** | | | **104 of 275** |

Proposed extras (improvements, not required for parity): video to **M4A** (we stream-copy AAC, so it is instant), video/GIF to **animated WebP**, and **AV1 WebM** as a quality option.

### 1.2 Tools that run on this engine (from Zivlet's 27 tools)

Compress (audio/video, presets and target size), view/edit/strip metadata (audio/video), Normalize Volume, Remove Audio, Trim Video, Trim Audio (incl. auto-trim silence), Split Video (clips or merged), Join Videos, Change Video Speed, Video Snapshots, Crop Video, Redact Video (solid/blur, incl. face tracks from Vision), Bleep Audio, Convert Audio Channels, Audio Visualizer.

### 1.3 Design principles

| Principle | Decision |
|---|---|
| Every advertised route must work | **We link real encoders** (libvpx, libopus, libvorbis, SVT-AV1) instead of FFmpeg's *experimental* native Opus/Vorbis encoders, and **test every pair**. |
| Probe with structured output | Regexes over `ffmpeg -i` stderr are fragile. **We ship ffprobe and parse JSON.** |
| No build-path leaks | **We build with `-ffile-prefix-map` and `SOURCE_DATE_EPOCH`** so paths don't leak and builds are reproducible. |
| Clean child process | `-progress pipe:1 -nostats`, clean child env (`PATH=/usr/bin:/bin`, fixed locale), `-nostdin`. |
| Don't re-encode needlessly | **We remux (stream copy) whenever codecs fit the target container**, and offer keyframe-exact fast trim. |
| Hardware first | H.264/HEVC through VideoToolbox with calibrated presets, plus an x264 2-pass path for exact target-size compression. |

---

## 2. Verified platform and upstream facts (2026-10-20)

### 2.1 What macOS gives us (VERIFIED-LOCAL, M2 Pro, macOS 27.0)

`VTCopyVideoEncoderList`:
- Hardware: H.264, HEVC, HEVC with alpha ("Apple Muxed Alpha"), ProRes 422 Proxy/LT/422/HQ/4444/4444 XQ, JPEG.
- Software: the same codecs, plus H.263.
- **No AV1 encoder. No VP9 encoder.**

`VTIsHardwareDecodeSupported`: avc1 yes, hvc1 yes, apcn (ProRes) yes, **av01 no** (AV1 hardware decode starts at M3), vp09 no.

`AVURLAsset.audiovisualTypes()` (104 types):
- Readable: `org.xiph.flac`, `org.xiph.ogg-audio`, `public.avi`, `public.mp3`.
- **Not readable: WebM, Matroska, WMV, WMA, `org.xiph.opus`, GIF.**

AudioToolbox:
- Encoders: `aac` (and HE/LD/ELD variants), `alac`, `flac`, `opus`, `lpcm`, `ilbc`, `ima4`, `alaw`, `ulaw`, `apac`. **No MP3 encoder, no Vorbis.**
- Writable file types include `Oggf`, `flac`, `m4af`, `caff`, `WAVE`, `AIFF`, `BW64/RF64`. `MPG3` is listed, but there is no MP3 encoder, so it is passthrough only.

ImageIO destinations:
- `public.avif` write **yes**, `org.webmproject.webp` write **no**, GIF write yes, HEIC write yes.
- Whether AVIF is writable on macOS **26** must be checked on a 26 machine (SPIKE S-7). It matters only for the image engine's fallback.

### 2.2 Upstream versions to pin (VERIFIED-UPSTREAM)

| Component | Version to pin | Released | License | Role |
|---|---|---|---|---|
| FFmpeg | **9.0.2 "Lei"** (fallback: 8.1.3 "Hoare") | 2026-09-18 | LGPL-2.1+ / GPL-2+ / GPL-3 when configured | Engine. 9.0 adds an **animated WebP decoder and demuxer** and the ProRes RAW VT hwaccel. |
| x264 | `stable` @ `b35605ac` | 2025-06-08 | GPL-2.0+ | Software H.264 (2-pass target size, determinism) |
| libvpx | **v1.17.0** | 2026 | BSD-3 | VP8/VP9 encode and decode (WebM) |
| SVT-AV1 | **v4.2.0** | 2026-07-14 | BSD-3-Clause-Clear + AOM patent license 1.0 | AV1 encode (WebM option, AVIF fallback) |
| dav1d | **1.5.4** | 2026 | BSD-2 | AV1 decode (pre-M3 Macs, and ffmpeg software path) |
| Opus | **1.6.1** | 2026 | BSD-3 | Opus encode and decode |
| libogg / libvorbis | **1.3.6 / 1.3.7** | 2025 / 2020 | BSD-3 | Ogg Vorbis |
| LAME | **3.100** | 2017 (stable, final) | LGPL-2.0+ | MP3 encode |
| libwebp | **1.6.0** | 2025 | BSD-3 | WebP (incl. `libwebp_anim`) |
| zimg | **release-3.0.6** | 2025 | WTFPL | `zscale`: HDR→SDR tonemapping, high-quality colorspace |
| *Optional* x265 | 4.2 | 2026-04-19 | GPL-2.0+ | Software HEVC (not in v1) |
| *Optional* libaom | 3.15.2 | 2026 | BSD-2 + AOM patent | Lossless/4:4:4 AVIF (not in v1) |

FFmpeg 9.0.2's `libsvtav1.c` has `SVT_AV1_CHECK_VERSION(4,0,0)` branches, so SVT-AV1 4.x is supported. Its configure needs `SvtAv1Enc >= 0.9.0`, `vpx >= 1.4.0`, `dav1d >= 1.0.0` and `zimg >= 2.7.0`. libvpx 1.17.0's configure knows the target `arm64-darwin25-gcc` (Darwin 25 = macOS 26). All VERIFIED-UPSTREAM.

### 2.3 Measured encoder behavior (VERIFIED-LOCAL)

Test clip: 10 s, 1080p30 `testsrc2` plus a sine tone, ProRes 422 LT source. Encoder: Homebrew ffmpeg 8.1.2 on an M2 Pro.

| Encoder / settings | Wall time | Size | Notes |
|---|---|---|---|
| `h264_videotoolbox -q:v 65` + `aac_at 192k` | 1.73 s | 9.2 MB | about 5.8x realtime |
| `hevc_videotoolbox -q:v 60 -tag:v hvc1` | 2.27 s | 11.4 MB | |
| `prores_videotoolbox -profile:v 2` | 1.14 s | 66 MB | hardware ProRes engine (M2 Pro) |
| `libx264 -preset medium -crf 21` | 4.31 s | 11.5 MB | software |
| `libvpx-vp9 -crf 32 -b:v 0 -row-mt 1 -deadline good -cpu-used 4` | 18.9 s | 9.0 MB | **0.53x realtime: slow** |
| same with `-cpu-used 5 -tile-columns 2 -pix_fmt yuv420p` | 14.3 s | 7.4 MB | default choice |
| `libsvtav1 -preset 8 -crf 35` (10-bit source auto) | 6.2 s | 5.9 MB | chose 10-bit, so **force `-pix_fmt yuv420p`** |
| `libsvtav1 -preset 8 -crf 35 -pix_fmt yuv420p` | 3.2 s | 5.9 MB | about 3x realtime |
| `wmv2 -q:v 4` + `wmav2` | 1.84 s | 22.8 MB | |
| `mpeg4 -vtag xvid -q:v 4` + LAME | 0.78 s | 17.3 MB | |
| GIF palettegen/paletteuse, 15 fps, 480 px | 1.33 s | 1.8 MB | |
| Audio (libopus 128k / LAME V2 / FLAC -8) of 10 s | 0.08–0.09 s | — | |
| `ffmpeg -version` startup (shared libs) | 27 ms | | Process launch overhead is negligible. |
| `ffprobe -of json` | 35 ms | | |
| Remux MP4→MKV (`-c copy`) / mute (`-an -c copy`) | 41 / 37 ms | | Instant paths |

Other findings:
- SVT-AV1 prints a banner to stderr even at `-loglevel error`. Set `SVT_LOG=1` in the child environment.
- The `ogg` muxer's **default audio codec is FLAC**, so always force `-c:a libvorbis` for `.ogg`.
- **Cover art:** an `attached_pic` stream muxes fine into MP3, M4A and FLAC, but the Ogg/Opus muxer rejects it ("Unsupported codec id in stream 1"). For Ogg we write a `METADATA_BLOCK_PICTURE` Vorbis comment ourselves (base64 FLAC picture block) or drop the cover.
- `atempo` accepts 0.5–100 in one instance.
- `libopus` accepts only 48/24/16/12/8 kHz.
- `-filter_complex_script` is deprecated. Use `-/filter_complex <file>`.

---

## 3. The three options

### 3.1 Option (a): bundle a self-built ffmpeg CLI (GPL, full codec set)

**How it works:** we compile ffmpeg plus codec libraries from pinned sources in CI and embed `ffmpeg` and `ffprobe` in the app. Swift builds an argv for each job (a pure, unit-testable function), runs the process, parses progress and verifies the output with ffprobe.

Pros:
- **Complete coverage** of all 104 pairs and every media tool with one engine. fftools already solves stream mapping, timestamps, A/V sync, frame-rate conversion, filtergraphs, concat and 2-pass.
- **Process isolation.** A decoder crash on a hostile file kills one child, not the menu bar app. Memory is fully reclaimed. Cancellation is a signal.
- **Battle-tested argv semantics.** Users and contributors can reproduce any job on the command line. This helps a future "Show ffmpeg command" debug feature and our own CLI/Raycast plans.
- Parallel jobs are just parallel processes. No global-state issues.
- Upgrades are a version bump in a lockfile. Security point releases (frequent: 9.0.1 and 9.0.2 were mostly OOB fixes) ship through Sparkle.

Cons:
- We own a build pipeline (about 10 libraries). Mitigation: §6 script plus CI cache.
- Progress is only as precise as `out_time_us` divided by the expected duration. That is fine in practice. Two-pass and filter-heavy jobs need weighting.
- argv building must be careful (escaping in filtergraphs, file names). Mitigation: never put paths in filtergraphs. Use `file:` prefixes and a script file for very long graphs.

### 3.2 Option (b): link libav\* in-process through a Swift package

Candidates (VERIFIED-UPSTREAM, GitHub API, 2026-10-20):

| Package | Status | License | What it is | Verdict |
|---|---|---|---|---|
| arthenica/ffmpeg-kit | **Archived**. Retired January 2025, prebuilt binaries pulled in 2025 | LGPL-3.0 | fftools embedded as a library + prebuilt xcframeworks | Dead. Don't use. |
| tylerjonesio/ffmpeg-kit-spm | **Archived** February 2025 | LGPL-3.0 | SPM wrapper of the above | Dead |
| kingslay/FFmpegKit | Active (FFmpeg 9.0.2, pushed 2026-10-18), 229 stars | **GPL-3.0** (LGPL is a paid tier) | xcframeworks for libav\* + mpv/libplacebo/libass/dav1d/opus. `ffmpeg_execute(argc, argv)` runs fftools in-process. | Built for players (KSPlayer). No x264, vpx, SVT or LAME encoders by default. In-process fftools has global state and `exit()` paths, so it is effectively one job at a time and crashes take the app down. |
| sunlubo/SwiftFFmpeg | Low activity (FFmpeg 8.0 support November 2025), 651 stars | Apache-2.0 | Thin Swift wrapper over the libav\* C API. Needs FFmpeg installed. | We would have to rewrite the transcoder (demux → decode → filter → encode → mux, timestamps, A/V sync) that fftools gives for free. Months of work and endless edge cases. |
| mpvkit/MPVKit | Active | LGPL-3.0 | libmpv for playback | Playback only |
| sbooth/SFBAudioEngine | Active | MIT | In-process audio decode/encode (FLAC, Vorbis, Opus, MP3 via LAME, …) | Audio only. A second engine to maintain. |

Pros:
- No process launch (about 27 ms, which is irrelevant).
- Frame-level callbacks for exact progress.
- A single signing unit.

Cons:
- No crash isolation, unless we add an XPC service, which brings back IPC complexity.
- API churn every major FFmpeg release (FFmpeg 9.0 removed deprecated APIs).
- fftools-in-process is non-reentrant.
- Swift 6 strict concurrency around non-Sendable C pointers is painful.
- No GPL/LGPL advantage either: we are GPLv3 anyway.

**Rejected.** One exception: if we ever need libavformat in-process (for example, MKV thumbnails in a Quick Look-like view), the shared-dylib layout chosen in §6 lets an XPC service load the same dylibs later without a second build.

### 3.3 Option (c): AVFoundation-first with ffmpeg fallback

**What AVFoundation, AudioToolbox and VideoToolbox can do natively** (§2.1):
- Read: MP4/MOV/M4V, M4A, WAV, AIFF, CAF, MP3, FLAC, AVI (limited codecs), Ogg audio (partly).
- Write: MP4/MOV (H.264/HEVC/HEVC-alpha/ProRes via `AVAssetWriter`), M4A (AAC/ALAC), WAV, AIFF, CAF, FLAC (`AVAudioFile`/`ExtAudioFile`, `kAudioFileFLACType`), and possibly Opus in Ogg (`Oggf` is writable on 27; unverified on 26).
- Cannot write MP3, Vorbis, WMA, MKV, WebM, AVI or WMV. GIF only frame-by-frame through ImageIO, with no palette optimization.
- Cannot read MKV, WebM, WMV, WMA or Opus.

**Coverage of the 104 pairs:**
- Audio: readable inputs {mp3, m4a, wav, flac, aiff} × writable outputs {m4a, wav, flac, aiff} minus same-format pairs = **16 of 56**.
- Video: mov↔mp4 = **2 of 42**. video→mp3 is impossible.
- GIF: gif→mp4/mov through ImageIO frames + `AVAssetWriter` = **2 of 6**.
- **Total: about 20 of 104 (about 19%).** ffmpeg is therefore mandatory anyway.

Pros of an AVFoundation fast path:
- In-process.
- `AVAssetExportSession.export(to:as:)` with `states(updateInterval:)` gives exact progress.
- Passthrough presets for trim/mute on MP4/MOV.
- Apple's own AAC encoder. ffmpeg gets this too, through `aac_at`.

Cons:
- **Two engines produce the same formats with different defaults and metadata behavior.** For example, mp3→m4a would go through AVFoundation but ogg→m4a through ffmpeg, and the results would differ in bitrate mode, tag mapping and cover art. That doubles the test matrix and invites user-visible inconsistency.
- AVFoundation has no MP3 encoder, so even "simple" audio routes split.
- Every speed advantage is also available in ffmpeg: stream copy, VideoToolbox, `aac_at`.

**Rejected as the conversion engine, adopted as the UI engine** (§13).

### 3.4 Scorecard

| Criterion (weight) | (a) ffmpeg CLI | (b) libav\* in-process | (c) AVF-first + ffmpeg |
|---|---|---|---|
| Format/tool coverage (5) | 5 | 4 (if fftools embedded) | 5 (only because ffmpeg is still there) |
| Correctness and consistency (5) | 5 (one pipeline) | 4 | 2 (two pipelines) |
| Crash isolation and cancellation (4) | 5 | 1 (2 with XPC) | 3 |
| Engineering cost (4) | 4 | 1 | 2 |
| Progress fidelity (2) | 4 | 5 | 4 |
| Size (2) | 4 (about 25 MB) | 4 | 4 |
| Upgrade/security cadence (3) | 5 | 2 | 4 |
| Licensing simplicity (2) | 5 (GPLv3 app) | 4 | 5 |
| **Weighted total (out of 135)** | **127** | 80 | 93 |

---

## 4. Component selection

| Library | Include in v1? | Why | Static size (est., arm64) |
|---|---|---|---|
| VideoToolbox / AudioToolbox | **Yes** (system) | H.264/HEVC/ProRes hardware encode, `aac_at`/`alac_at`, VT decode hwaccel | 0 (system) |
| libx264 | **Yes** | Exact 2-pass target-size ("Accurate"), predictable software quality, deterministic CI goldens. Small. | ~1.2 MB |
| libx265 | **No** (flag `WITH_X265=1`) | VT HEVC covers HEVC output on every Apple silicon Mac (hardware with software fallback). x265 adds about 7 MB and the most aggressive patent-pool exposure. | ~7 MB |
| libvpx | **Yes** | VP9 (+VP8) WebM. VP9 with alpha (`yuva420p`). | ~1.7 MB |
| SVT-AV1 | **Yes** | AV1 WebM option, AVIF fallback (`avif=1` still mode, SPIKE S-5). Fast on NEON/i8mm. | ~2.8 MB |
| libaom | **No** (flag `WITH_AOM=1`) | Only needed for 4:4:4/lossless AVIF if ImageIO and SVT-AV1 both fall short | ~3.9 MB |
| dav1d | **Yes** | Fast AV1 decode (pre-M3 has no AV1 hardware decode) | ~0.8 MB |
| libopus | **Yes** | Real Opus (not the experimental native encoder) | ~0.4 MB |
| libvorbis + libogg | **Yes** | Real Vorbis for `.ogg` (the native encoder is experimental and poor) | ~0.3 MB |
| LAME | **Yes** | MP3. MP3 patents expired in 2017. | ~0.3 MB |
| libwebp (+mux/demux, sharpyuv) | **Yes** | `libwebp` and `libwebp_anim` encoders (animated WebP from GIF/video). The same static lib can be linked into the app for still WebP (image engine). | ~0.6 MB |
| zimg | **Yes** | `zscale` for HDR (PQ/HLG) → SDR tonemapping when the target is 8-bit (GIF, H.264 SDR, VP9 8-bit) | ~0.4 MB |
| zlib, bzip2, iconv | **Yes** (system, via explicit enables) | PNG/MOV `cmov`, Matroska bz2 tracks, subtitle charset conversion | 0 |
| fdk-aac | **Never** | "nonfree": its license is GPL-incompatible, so the binary would be non-redistributable. `aac_at` is better on macOS anyway. | — |
| libx264 via `--enable-nonfree`, OpenSSL, network protocols | **Never** | Offline app. `--disable-network`. | — |
| gifski (AGPL-3.0, Rust CLI) | **Later, optional** | Best GIF quality. AGPL-3.0 can be combined with GPLv3 (GPLv3 §13), and it is a separate CLI. Revisit after v1. | ~3–4 MB |
| whisper (FFmpeg 8+ filter, whisper.cpp MIT) | Later | Auto subtitles (Permute has transcription). Out of scope for v1. | model-dependent |

---

## 5. Licensing

1. **Zivlet is GPL-3.0-or-later** (consistent with `00-decisions.md`). ffmpeg is configured with `--enable-gpl --enable-version3`, so `ffmpeg -L` reports "GNU General Public License version 3 or later". The whole distribution is GPLv3.
2. **Compatibility of every bundled component with GPLv3:**

   | Component | License | GPLv3-compatible? |
   |---|---|---|
   | FFmpeg | GPL-2+/LGPL-2.1+ (as configured) | Yes |
   | x264, (x265) | GPL-2.0-or-later | Yes |
   | LAME | LGPL-2.0+ | Yes |
   | libvpx, Opus, Vorbis, Ogg, libwebp | BSD-3 | Yes |
   | dav1d, (libaom) | BSD-2 | Yes |
   | SVT-AV1 | BSD-3-Clause-Clear | Yes |
   | zimg | WTFPL | Yes |

   Apple frameworks (VideoToolbox, AudioToolbox) fall under GPLv3's System Library exception.
3. **Hard bans enforced in CI** (the build fails if any is true):
   - `ffmpeg -buildconf` contains `nonfree`.
   - `-L` does not print "version 3".
   - `otool -L` shows anything outside `@rpath`, `/usr/lib` or `/System`.
   - `-encoders` lists `libfdk_aac`.
4. **Corresponding Source (GPLv3 §6):** every GitHub release and every Sparkle appcast item comes with `zivlet-media-src-<lockhash>.tar.xz`. It contains:
   - all upstream tarballs (verified SHA-256);
   - our patches;
   - `media-versions.lock` and `build-media.sh`;
   - the exact Xcode/CLT version used.

   Host it in the same place as the binaries (the GitHub Release) for as long as the binary is offered. Show the license texts in About → Acknowledgements (auto-generated from the lockfile).
5. **Patents (INFERRED, not legal advice):**
   - VideoToolbox H.264/HEVC is Apple's licensed OS feature, which is our default path.
   - x264 in a free app carries the same theoretical AVC-pool exposure HandBrake, VLC and OBS have lived with for 15+ years. It is kept for "Accurate" target-size and can be dropped with one flag.
   - VP9, AV1 and Opus are royalty-free. Third-party pool claims exist for AV1, so we monitor them.
   - MP3 patents expired. MPEG-4 Part 2 (AVI) and WMV8/WMA2 are mostly or fully expired.
   - This is the reason x265 is excluded from v1.

---

## 6. Reproducible build (arm64, macOS 26 minimum)

§6 lives in [11a-media-build](11a-media-build.md) with the same section numbers.

---

## 7. Bundle layout, signing, hardened runtime, notarization

### 7.1 Layout

```
Zivlet.app/Contents/
  MacOS/Zivlet
  Helpers/ffmpeg            # LC_RPATH @executable_path/../Frameworks
  Helpers/ffprobe
  Frameworks/libavcodec.62.dylib   libavformat.62.dylib  libavfilter.11.dylib
             libavutil.60.dylib    libswscale.9.dylib    libswresample.6.dylib  (libavdevice disabled)
  Resources/Licenses/…      # generated from the lock file
```

`Contents/Helpers` is Apple's documented place for helper tools ("Placing content in a bundle"). Dylibs go in `Contents/Frameworks`. The major-versioned install names (`@rpath/libavcodec.62.dylib`) come from `--install-name-dir='@rpath'`.

### 7.2 Signing (inside-out, never `--deep` for signing)

```bash
ID="Developer ID Application: <Name> (<TEAMID>)"
APP=Zivlet.app/Contents
for f in $APP/Frameworks/libav*.dylib $APP/Frameworks/libsw*.dylib; do
  codesign --force --timestamp --options runtime --sign "$ID" "$f"; done
for t in ffmpeg ffprobe; do
  codesign --force --timestamp --options runtime --identifier "app.zivlet.helper.$t" --sign "$ID" "$APP/Helpers/$t"; done
codesign --force --timestamp --options runtime --entitlements Zivlet.entitlements --sign "$ID" Zivlet.app
codesign --verify --strict --deep -vvv Zivlet.app          # --deep is fine for *verification*
codesign -dv --verbose=4 $APP/Helpers/ffmpeg 2>&1 | grep -E 'flags=.*runtime|TeamIdentifier'
ditto -c -k --keepParent Zivlet.app Zivlet.zip
xcrun notarytool submit Zivlet.zip --keychain-profile zivlet-notary --wait
xcrun stapler staple Zivlet.app && spctl -a -vvv -t exec Zivlet.app
```

In Xcode, use a "Copy Files" phase (Destination: Wrapper, subpath `Contents/Helpers`; and Frameworks) with "Code Sign On Copy". Then **check** that the copies have `flags=0x10000(runtime)` and a secure timestamp. If not, sign them in a Run Script phase as above. Notarization rejects any nested Mach-O without hardened runtime or timestamp.

### 7.3 Entitlements

- **ffmpeg / ffprobe: none.**
  - No `com.apple.security.cs.disable-library-validation`: our dylibs carry our Team ID, which library validation accepts.
  - No `allow-jit` or `allow-unsigned-executable-memory`: ffmpeg, x264, libvpx, SVT and dav1d use static assembly, not JIT.
  - No sandbox entitlements: the app is not sandboxed, so there is nothing to inherit.

  Contrast: a sandboxed app would have to sign its tools with `app-sandbox + inherit`.
- **Main app:** no media-specific entitlements.
- The hardened runtime also strips `DYLD_*` environment variables, so a child can't be hijacked through the environment.

### 7.4 Runtime integrity check (cheap, optional)

At first use per launch, call `SecStaticCodeCreateWithPath` + `SecStaticCodeCheckValidity` on `Helpers/ffmpeg` with the requirement `anchor apple generic and certificate leaf[subject.OU] = "<TEAMID>"` (a few ms). On failure, show "Zivlet's media engine is damaged; please reinstall" and disable media routes. Never fall back to `/opt/homebrew/bin/ffmpeg` in release builds. A debug-only override through an environment variable is fine.

### 7.5 Optional hardening spike (S-8): sandbox the helper

ffmpeg parses untrusted media with the user's privileges. A stretch goal:
- Sign the helpers with a standalone `com.apple.security.app-sandbox` (embedded Info.plist via `-sectcreate __TEXT __info_plist`).
- Pass inputs and outputs as **inherited file descriptors** (`-fd N -i fd:`, FFmpeg ≥6).

Risks:
- `-movflags +faststart` and 2-pass logs reopen files by name.
- Concat needs many fds.
- The container temp dir must exist.

Not for v1. Track it as a security improvement.

---

## 8. Runtime architecture

### 8.1 Modules (Swift 6, strict concurrency)

```
MediaEngine/
  EngineLocator.swift        // bundle URLs for ffmpeg/ffprobe, signature check (7.4)
  CapabilityProbe.swift      // -encoders/-muxers/-filters once per binary hash -> Capabilities (cached JSON)
  MediaProbe.swift           // ffprobe JSON -> MediaInfo (Codable)
  Plan/                      // PURE: (MediaInfo, Route, Options, Capabilities) -> FFmpegPlan
    AudioPlans.swift  VideoPlans.swift  GIFPlans.swift  ToolPlans/*.swift
  Runner/
    FFmpegRunner.swift       // actor: spawn, progress stream, cancel, stderr ring buffer
    ProgressParser.swift     // pure, value-type
    JobScheduler.swift       // resource classes + limits
  Publish/
    OutputStager.swift       // temp dir on destination volume, atomic rename, collision naming
    OutputVerifier.swift     // ffprobe output, duration/stream checks, "bigger than source" rule
  Errors/MediaError.swift    // typed errors + user copy + log context
```

`FFmpegPlan` is plain data: `passes: [[String]]`, `passWeights: [Double]`, `expectedDurationMicros: Int64?`, `outputs: [URL]`, `resourceClass`. That makes argv golden-file tests trivial (§14), and the plan can later back a "Copy ffmpeg command" debug menu item.

### 8.2 Probing (ffprobe JSON)

```
ffprobe -v error -hide_banner -of json -show_format -show_streams -show_chapters file:<abs path>
```

Decode into `MediaInfo` with:
- `format.duration`, `bit_rate`, `tags`;
- per stream: `codec_type`, `codec_name`, `profile`, `width`, `height`, `pix_fmt`, `color_transfer` (`smpte2084`/`arib-std-b67` = HDR), `color_primaries`, `avg_frame_rate`, `sample_rate`, `channels`, `channel_layout`, `bits_per_raw_sample`, `sample_fmt`, `disposition.attached_pic`, `disposition.default`, `side_data_list` (Display Matrix rotation), `tags.language`.

Probe once per file per job. Cache by `(path, size, mtime)` for the wheel. Probing on hover hides slices that make no sense (for example video→MP3 when there is no audio track), with a 150 ms budget.

### 8.3 Runner (sketch against swift-subprocess 1.0.2; verify exact API at implementation)

```swift
import Subprocess   // swiftlang/swift-subprocess 1.0.x (Apache-2.0)
import System

struct FFmpegProgress: Sendable, Equatable {
    let outTimeMicros: Int64?
    let speed: Double?
    let totalSize: Int64?
    let isEnd: Bool
}

/// Pure, immutable parser: feed one "key=value" line, get the next parser and maybe a progress event.
struct ProgressParser: Sendable {
    let pending: [String: String]
    init(pending: [String: String] = [:]) { self.pending = pending }

    func consuming(_ line: String) -> (ProgressParser, FFmpegProgress?) {
        guard let eq = line.firstIndex(of: "=") else { return (self, nil) }
        let key = String(line[..<eq]), value = String(line[line.index(after: eq)...])
        let next = pending.merging([key: value]) { _, new in new }
        guard key == "progress" else { return (ProgressParser(pending: next), nil) }
        let event = FFmpegProgress(
            outTimeMicros: next["out_time_us"].flatMap(Int64.init).map { max(0, $0) },  // "N/A" -> nil
            speed: next["speed"].flatMap { Double($0.dropLast()) },                    // "4.77x"
            totalSize: next["total_size"].flatMap(Int64.init),
            isEnd: value == "end")
        return (ProgressParser(), event)
    }
}

actor FFmpegRunner {
    private let ffmpeg: FilePath
    init(ffmpeg: FilePath) { self.ffmpeg = ffmpeg }

    func run(arguments: [String], workingDirectory: FilePath,
             onProgress: @Sendable (FFmpegProgress) -> Void) async throws -> StderrTail {
        var options = PlatformOptions()
        options.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: .seconds(2))] // SIGTERM, then SIGKILL
        options.processGroupID = 0          // own process group: kill the whole job tree on cancel
        options.qualityOfService = .userInitiated
        let env: Environment = .custom([
            "PATH": "/usr/bin:/bin", "LC_ALL": "en_US.UTF-8", "SVT_LOG": "1", "AV_LOG_FORCE_NOCOLOR": "1"])
        let result = try await Subprocess.run(
            .path(ffmpeg),
            arguments: Arguments(["-hide_banner", "-nostdin", "-y", "-loglevel", "error",
                                  "-progress", "pipe:1", "-stats_period", "0.25", "-nostats"] + arguments),
            environment: env, workingDirectory: workingDirectory, platformOptions: options,
            input: .none, output: .sequence, error: .sequence
        ) { execution in
            async let tail = StderrTail.collect(execution.standardError, limitBytes: 64 * 1024)
            var parser = ProgressParser()
            for try await line in execution.standardOutput.strings() {
                let (next, event) = parser.consuming(line)
                parser = next
                if let event { onProgress(event) }
            }
            return try await tail
        }
        guard case .exited(0) = result.terminationStatus else {
            throw MediaError.ffmpegFailed(status: result.terminationStatus, stderr: result.closureResult)
        }
        return result.closureResult
    }
}
```

**Progress math:**
- `fraction = clamp(outTime / expectedDuration)`.
- Expected duration comes from the plan: the trimmed range, or source ÷ speed for speed changes, or the sum of clips for join.
- Two-pass jobs weight each pass (x264 1st pass is 0.35, 2nd is 0.65).
- loudnorm analysis + render is 0.4 / 0.6.
- If the duration is unknown (broken streams), show an indeterminate bar, but still show size written.
- Throttle UI updates to 10 Hz.

**Cancellation:**
- A Swift task is cancelled, which triggers the teardown sequence. ffmpeg handles SIGTERM by flushing and exiting, and a second signal forces it. SIGKILL follows after 2 s.
- The job's temp directory is then deleted, so **no partial file is ever visible beside the source** (it was never there).

**Orphans:** macOS has no `PR_SET_PDEATHSIG`. If Zivlet crashes, children keep running. Mitigation:
- Each job writes `{pid, pgid, startTime}` into `~/Library/Caches/app.zivlet/jobs/<uuid>/job.json`.
- At launch, for each stale job, check `proc_pidpath(pid)` == our `Helpers/ffmpeg`. If it matches, `killpg(pgid, SIGKILL)`. Then remove the directory.

**Scheduling** (`JobScheduler` actor, resource classes):

| Class | Examples | Concurrency |
|---|---|---|
| `remux` | stream copy, mute, fast trim | 4 |
| `audio` | any audio encode | `hw.perflevel0.physicalcpu` (performance cores) |
| `hwVideo` | VideoToolbox encodes | 2 (M2 Pro has 1 video encode engine; Max 2, Ultra 4. A third job only queues in VT.) |
| `swVideo` | libvpx, SVT-AV1, x264 | 1 (each is already multithreaded; `-row-mt 1`, SVT's own threading) |

Batch drops fan out over these queues. The HUD shows "n of m saved".

### 8.4 Staging, publishing, verification

1. Temp dir: `FileManager.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destinationFolder, create: true)`. This is on the same volume, so publishing is an atomic `rename(2)`.
2. ffmpeg writes `out.<ext>` there. Paths are always absolute and passed as `file:<path>`, so ffmpeg never treats `a:b.mp4` as a protocol. Paths are never interpolated into filtergraph strings. Extra inputs (watermark images, palettes) are `-i` inputs referenced by index.
3. Verify with `ffprobe` on the output:
   - expected stream kinds are present;
   - |duration − expected| ≤ max(0.25 s, 1%);
   - size > 0;
   - for **Compress**: output < source (or < target), else discard the output and tell the user "The compressed file came out larger than the original, so it was not saved."
4. Publish with Finder-style collision naming (`name.mp4`, then `name 2.mp4`). Optionally copy Finder tags and comments (xattrs) from the source, minus `com.apple.quarantine`. Then select the result in Finder (shared app behavior).

### 8.5 Errors

`MediaError` cases:
- `.engineMissing`, `.engineDamaged`
- `.unsupportedInput(reason)`, `.noAudioTrack`, `.noVideoTrack`
- `.encoderUnavailable(name)` (should be impossible after the capability gate)
- `.diskFull`, matched from `No space left on device`
- `.permissionDenied`
- `.cancelled`
- `.verificationFailed(details)`
- `.targetTooSmall(minBytes)`
- `.ffmpegFailed(status, stderrTail)`
- `.crashed(signal)`

Each case maps to one-sentence user copy. The full argv (paths marked `.private`) and the stderr tail go to `os.Logger(subsystem: "app.zivlet", category: "media")`. Errors are never swallowed: a batch reports per-file failures in the HUD and in a "Show details" sheet.

---

## 9. Hardware acceleration policy

| Need | Default encoder | Key options | Fallback |
|---|---|---|---|
| H.264 (MP4/MOV/MKV, visualizer, join) | `h264_videotoolbox` | `-profile:v high -q:v <Q> -allow_sw 1 -pix_fmt yuv420p -tag:v avc1` | `libx264 -preset medium -crf <C>` if VT session creation fails |
| HEVC (source is HEVC, 10-bit or HDR; or user picks HEVC) | `hevc_videotoolbox` | `-profile:v main10 -pix_fmt p010le` for 10-bit/HDR (color tags copied), `-tag:v hvc1` | `-allow_sw 1` (Apple's software HEVC encoder) |
| HEVC with alpha (MOV from alpha sources) | `hevc_videotoolbox` | `-pix_fmt bgra -alpha_quality 0.75 -tag:v hvc1` | ProRes 4444 |
| ProRes (MOV "Edit-friendly" option) | `prores_videotoolbox` | `-profile:v 2` (422) / `3` (HQ) / `4` (4444) | `prores_ks` (base M1 has no ProRes engine; VT then uses Apple's software ProRes) |
| AV1 | `libsvtav1` (**no Apple silicon has a VT AV1 encoder**) | `-preset 8 -crf 35 -pix_fmt yuv420p -svtav1-params tune=0` | — |
| VP9 | `libvpx-vp9` | `-crf 32 -b:v 0 -row-mt 1 -tile-columns 2 -deadline good -cpu-used 5` | — |
| Exact target size ("Accurate") | `libx264` 2-pass | `-b:v <R> -pass 1 -an -f null /dev/null` then `-pass 2 … -passlogfile <tmp>/x264` | VT ABR + bitrate search ("Fast") |
| Decode | software by default; `-hwaccel videotoolbox` for H.264/HEVC/ProRes (and AV1 on M3+) when the filter chain is CPU-side anyway | — | dav1d / libvpx / native decoders |

Further policy:
- **VT quality presets** (`-q:v`, 1–100, Apple silicon only): High 72, Balanced 60, Small 48. These are starting points to calibrate with VMAF against x264 CRF 20/23/26 on a fixture set (SPIKE S-3).
- **Constant bitrate** (`-constant_bit_rate 1`) only for target-size "Fast" mode, and only if verification shows ABR overshoots.
- `-spatial_aq 1` and `-prio_speed 0` exist in FFmpeg 9's `videotoolboxenc.c`. Enable `spatial_aq` if S-3 shows a gain.
- **Never** advertise "hardware AV1 encode". Re-test `VTCopyVideoEncoderList` on new chips through the capability probe (it reads ffmpeg's encoder list, and VT is queried at session creation). If Apple ships AV1 encode, FFmpeg would need an `av1_videotoolbox` encoder, which doesn't exist upstream today.

---

## 10. Exact codec matrix

Common rules apply to every route unless the row says otherwise:
- **Remux first:** if every kept stream's codec is allowed in the target container (allowed sets below) and no filter is needed, use `-c copy`. It is lossless and instant. The user can force "Re-encode" in per-format settings.
- **Metadata:** `-map_metadata 0 -map_chapters 0` (global tags and chapters kept) unless the user turns "Preserve metadata" off (`-map_metadata -1 -map_chapters -1`).
- **Rotation:** honored automatically on re-encode (ffmpeg autorotate). Display matrix side data is preserved on copy.
- **Odd dimensions** for 4:2:0 encoders: `scale=trunc(iw/2)*2:trunc(ih/2)*2` (added only when needed).
- **HDR → 8-bit SDR target** (GIF, H.264, VP9 8-bit, AVI, WMV): `zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p`. HDR → HEVC/MOV/MP4 keeps HDR (Main10, color tags copied).
- **Audio sample format/depth:** preserved where the codec allows. Lossy codecs resample only if the codec's rate set requires it.
- **Cover art:** `attached_pic` streams are mapped by index from ffprobe, so video tracks of a movie are never mistaken for cover art.

### 10.1 Audio outputs (sources: any audio, or the first/selected audio track of a video)

| Output | Muxer | Codec / encoder | Default | Quality options | Rate / channel / depth rules | Tags & cover | Remux allowed when source is |
|---|---|---|---|---|---|---|---|
| **MP3** | `mp3` | MP3 / `libmp3lame` | `-q:a 2` (VBR V2, ~190 kbps) | VBR V0/V2/V4, or CBR 128/192/256/320 (`-b:a`) | rate ≤ 48 kHz (else `-ar 48000`); >2 ch → `-ac 2` | `-id3v2_version 3 -write_xing 1`; cover copied as APIC (verified) | mp3 |
| **M4A** | `ipod` (`-f ipod`) | AAC-LC / `aac_at` | `-b:a 192k` | 128/192/256/320; **ALAC** (`alac_at`) "Lossless" option | rate > 48 kHz → 48000; up to 7.1 | iTunes atoms; cover copied (verified); `-movflags +faststart` | aac, alac |
| **WAV** | `wav` | LPCM / `pcm_s16le` · `pcm_s24le` · `pcm_s32le` · `pcm_f32le` | match source depth (≤16 → s16, 24 → s24, 32-int → s32, float → f32) | depth 16/24/32f | any rate/channels; `-rf64 auto` (no 4 GB cliff) | INFO tags (partial); no cover | pcm_s16le/s24le/s32le/f32le |
| **AIFF** | `aiff` | LPCM BE / `pcm_s16be` · `pcm_s24be` · `pcm_s32be` | match source depth (float → s24be) | depth 16/24/32 | any | `-write_id3v2 1` (tags; cover SPIKE S-6) | pcm_s16be/s24be/s32be |
| **FLAC** | `flac` | FLAC / `flac` | `-compression_level 8` | — (lossless) | 16-bit → `s16`; 24-bit → `-sample_fmt s32 -bits_per_raw_sample 24`; float → 24-bit | Vorbis comments; cover as PICTURE block (verified) | flac |
| **OGG** | `ogg` | Vorbis / `libvorbis` (**forced**: ogg defaults to FLAC) | `-q:a 6` (~192 kbps) | q 3/5/6/8 | up to 8 ch (Vorbis mapping) | Vorbis comments; cover via `METADATA_BLOCK_PICTURE` tag written by us (stream mux unsupported) | vorbis |
| **OPUS** | `opus` (Ogg, `.opus`) | Opus / `libopus` | `-b:a 128k -vbr on -application audio -ar 48000` | 64/96/128/160/192/256 kbps | always 48 kHz; >2 ch → `-mapping_family 1` | Opus tags; cover via `METADATA_BLOCK_PICTURE` (verified stream mux fails) | opus |
| **WMA** | `asf` | WMA v2 / `wmav2` | `-b:a 192k` | 128/160/192 | ≤ 2 ch (`-ac 2`), rate ≤ 48 kHz | ASF tags; cover dropped | wmav2 |
| *M4A from video (new)* | `ipod` | copy if AAC/ALAC, else `aac_at 192k` | `-map 0:a:<sel> -vn -sn -dn` | as M4A | as M4A | as M4A | aac, alac |
| **MP3 from video** | `mp3` | `libmp3lame -q:a 2` | `-map 0:a:<sel> -vn -sn -dn` | as MP3 | as MP3 | title/artist from container tags | mp3 track |

### 10.2 Video outputs (sources: mp4 mov mkv webm avi wmv, and gif)

| Output | Muxer | Video (re-encode default) | Audio (re-encode default) | Remux sets (copy if all kept streams fit) | Container specifics |
|---|---|---|---|---|---|
| **MP4** | `mp4` | H.264 High, `h264_videotoolbox -q:v 60 -tag:v avc1`; **HEVC** Main10 if source is HDR or 10-bit (`hevc_videotoolbox -tag:v hvc1 -pix_fmt p010le`) | AAC `aac_at -b:a 192k` (keep up to 6 ch) | video {h264, hevc, av1, mpeg4}; audio {aac, alac, mp3, ac3, eac3}. Opus/Vorbis/PCM/WMA audio is re-encoded to AAC for QuickTime compatibility. | `-movflags +faststart`; maps `0:v:0` + all audio; text subtitles → `mov_text`; image subtitles (PGS/VobSub) dropped with a note |
| **MOV** | `mov` | same as MP4. Option "ProRes 422" (`prores_videotoolbox -profile:v 2`, audio `pcm_s16le`). Alpha sources → HEVC-alpha. | AAC 192k (PCM with ProRes) | video {h264, hevc, prores, mjpeg, mpeg4}; audio {aac, alac, pcm_*, mp3} | `-movflags +faststart`; text subs → `mov_text` |
| **MKV** | `matroska` | H.264 VT (as MP4) only when remux is impossible (e.g., WMV2, MPEG-4 ASP sources still copy, since MKV accepts almost anything) | AAC 192k only when the codec is unsupported (rare); otherwise copy | nearly everything: `-map 0 -c copy` keeps all video, audio, subtitle and attachment streams and chapters | the most common route is a pure remux, about 40 ms (measured) |
| **WEBM** | `webm` | **VP9** `libvpx-vp9 -crf 32 -b:v 0 -row-mt 1 -tile-columns 2 -deadline good -cpu-used 5 -pix_fmt yuv420p` (alpha sources: `yuva420p`). Option **AV1**: `libsvtav1 -preset 8 -crf 35 -pix_fmt yuv420p`. | **Opus** `libopus -b:a 128k -ar 48000` (>2 ch: `-mapping_family 1`) | video {vp8, vp9, av1}; audio {opus, vorbis} | text subs → `webvtt`; others dropped. |
| **AVI** | `avi` | MPEG-4 Part 2 `mpeg4 -vtag xvid -q:v 3` | MP3 **CBR** `libmp3lame -b:a 192k` (VBR MP3 in AVI breaks old players) | video {mpeg4, mjpeg, h264}; audio {mp3, pcm_s16le, ac3} | `-fps_mode cfr`; ≤ 2 ch; no subtitles |
| **WMV** | `asf` | WMV8 `wmv2 -q:v 3` | WMA v2 `wmav2 -b:a 192k` | video {wmv1, wmv2}; audio {wmav2} | `-fps_mode cfr`; ≤ 2 ch, ≤ 48 kHz |
| **GIF** | `gif` | palette pipeline (§10.3) | none (`-an`) | — | `-loop 0` |
| **MP3** | see §10.1 | — | — | — | — |

### 10.3 GIF specifics

**Video → GIF** (defaults: 15 fps capped at source fps; max width 480 px; options 320/480/640/800/original; dither "Sierra (smooth)" or "Bayer (smaller)"):

```
-filter_complex "[0:v]fps=15,scale='min(480,iw)':-2:flags=lanczos,split[a][b];
                 [a]palettegen=stats_mode=diff:max_colors=256[p];
                 [b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" -an -loop 0
```

- HDR sources get the tonemap chain before `fps`.
- A guard warns before encoding when the estimated output is over 50 MB or the clip is over 60 s.
- The UI offers a trim range so users don't GIF a whole movie.

**GIF → video:**
- Use `-fps_mode vfr` for mp4/mov/mkv/webm (GIF frame delays are variable). For avi/wmv, use `-fps_mode cfr -r <round(avg_frame_rate), capped at 50>`.
- Transparency:
  - **WebM** keeps alpha (VP9 `yuva420p`);
  - **MOV** keeps alpha (HEVC-alpha);
  - **MP4/MKV/AVI/WMV** flatten onto white with `color=white:s=WxH[bg];[bg][0:v]overlay=shortest=1,format=yuv420p` (white matches how GIFs look on the web; documented, not silent).
- Even dimensions enforced.

**Animated WebP (improvement):** `-c:v libwebp_anim -quality 75 -loop 0 -lossless 0` from GIF/video, with FFmpeg 9's new animated-WebP decoder for WebP input.

---

## 11. Tools → engine mapping

| Tool | Engine path (ffmpeg unless noted) | Notes |
|---|---|---|
| Compress, audio | mp3/m4a/ogg/opus → same codec at a lower bitrate (Balanced/Strong); **wav/aiff → FLAC** (lossless) or user choice | refuse if output ≥ source |
| Compress, video (preset) | VT HEVC `-q:v` (Balanced 55 / Strong 45) + optional max height 1080/720 + AAC 128k/96k | VT `-q:v` instead of a fixed bitrate (better quality per byte) |
| Compress, video (target size) | budget `videoBitrate = (target×8 − audioBits − 2% mux overhead)/duration`. **Fast:** VT H.264 ABR, verify, retry ×0.92 up to 3×. **Accurate:** x264 2-pass. | precise. Shows "minimum achievable size" before running. |
| Metadata view/edit/strip | read: ffprobe tags. Edit: `-c copy -map 0 -metadata key=value …` (`-metadata:s:a:0` for stream tags). Strip: `-c copy -map 0 -map_metadata -1 -map_chapters -1 -fflags +bitexact` | copy-only, instant. MOV GPS (`©xyz`/`location`) removed by `map_metadata -1`. ExifTool is the image engine's domain. |
| Mute video | `-map 0 -map -0:a -c copy` | instant (measured 37 ms) |
| Trim video/audio | **Fast (keyframe):** `-ss <a> -to <b> -i in -map 0 -c copy -avoid_negative_ts make_zero`. **Exact:** re-encode with input-side `-ss` + `-t`. | Fast mode is lossless and near-instant |
| Auto trim silence | analysis: `-af silencedetect=noise=<dB>dB:d=0.1 -f null -` and parse `silence_start`/`silence_end` from stderr, **or** render directly with `silenceremove=start_periods=1:start_threshold=<dB>dB:stop_periods=1:stop_threshold=<dB>dB` (end trim via `areverse` is avoided on long files) | threshold −80…−10 dB |
| Split video | separate clips: N × fast/exact trim jobs. Merged ("remove clips"): concat demuxer on copied segments when keyframe-aligned, else `trim/atrim + concat` filter re-encode | |
| Join videos | same codec params everywhere → **concat demuxer + `-c copy`** (instant). Else canvas = first clip: `scale=W:H:force_original_aspect_ratio=decrease,pad=W:H:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=<first>` per input, `concat=n=N:v=1:a=1`, silent-audio fill with `anullsrc` for clips without audio. Output MP4 (H.264 VT + AAC). | |
| Change speed | `setpts=PTS/<s>` + `atempo=<s>` (0.5–100 in one instance; below 0.5 chain two). Pitch preserved. | |
| Snapshots | `-ss <t> -i in -frames:v 1 -update 1 file:<tmp>/Snapshot.png`; multiple: one job per timestamp (input-seek fast) | the UI frame grab itself uses `AVAssetImageGenerator` for AVF-readable formats |
| Crop video | `crop=w:h:x:y` (+ even dims), re-encode in the source container's default codec; audio copied | |
| Redact video | solid: `drawbox=…:t=fill:enable='between(t,a,b)'`; blur: `split` → `crop` → `gblur=sigma=σ:steps=3` → `overlay=…:enable=…`. **Face tracking** (Vision `VNTrackObjectRequest` boxes per frame window) produces many boxes, so emit a filter script and pass it with `-/filter_complex <file>`, or use `sendcmd` | script file avoids argv-length limits |
| Normalize | EBU R128 two-pass `loudnorm`: pass 1 `loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json -f null -` (parse JSON); pass 2 `loudnorm=…:measured_I=…:measured_TP=…:measured_LRA=…:measured_thresh=…:offset=…:linear=true`. Presets: −16 LUFS (web/podcast), −14 (streaming), −23 (broadcast). | video: audio re-encoded, video copied |
| Bleep | per range: `volume=enable='between(t,a,b)':volume=0` on the program, mixed with `sine=f=1000:r=48000` gated by `volume=enable='not(between(t,a,b))':volume=0` → `amix=normalize=0`. A clean graph rather than per-sample `aeval`. | video: video copied |
| Audio channels | mono: `-ac 1` (or `pan=mono|c0=0.5*c0+0.5*c1`); stereo with balance: `pan=stereo|c0=<L>*c0|c1=<R>*c1`; swap and dual-mono options | |
| Visualizer | waveform: `[0:a]showwaves=s=WxH:mode=cline:rate=30:colors=<brand>:scale=sqrt,format=yuv420p`; static image: `-loop 1 -framerate 30 -i img -i audio -shortest -vf scale…,pad…,setsar=1`; encoded with `h264_videotoolbox` + `aac_at` → MP4 | own brand color |
| Waveform for UI editors | AVF-readable audio: `AVAudioFile` in-process, downsampled. Otherwise `-map 0:a:<n> -ac 2 -ar 2000 -c:a pcm_f32le -f f32le pipe:1` streamed to a min/max reducer. | low sample rate keeps the pipe small |

---

## 12. WebP / AVIF (media side only)

- **Still WebP encode:** ImageIO can't write WebP (VERIFIED-LOCAL). Recommendation to the image engine: link the same pinned **libwebp 1.6.0 static library in-process**. `WebPConfig.target_size` and `pass` give native target-size compression, so there is no `cwebp` process. The ffmpeg `libwebp` encoder remains a fallback.
- **Animated WebP:** ffmpeg `libwebp_anim` (enabled). FFmpeg 9.0 also **decodes** animated WebP.
- **AVIF still:** ImageIO writes `public.avif` on macOS 27 (VERIFIED-LOCAL). macOS 26 is S-7. If missing on 26, fall back to `ffmpeg -frames:v 1 -c:v libsvtav1 -svtav1-params avif=1 -crf <N> -pix_fmt yuv420p out.avif` (FFmpeg has an `avif` muxer). SPIKE S-5 confirms SVT-AV1's still-picture mode through FFmpeg. 4:4:4 or lossless needs libaom (optional flag).

---

## 13. AVFoundation's role (UI, not conversion)

- **Tool window previews and scrubbing:** `AVPlayer` / `AVPlayerView` for AVF-playable files. For MKV/WebM/WMV/AVI-with-odd-codecs, generate a **preview proxy** in the job cache:
  - if the codecs are AVF-decodable (H.264/HEVC/AAC in MKV), remux to MP4 (`-c copy`, under 1 s);
  - else transcode at 540p with `h264_videotoolbox -q:v 50` + `aac_at 96k` (about 6–10x realtime).

  The edit decisions (times, rects) apply to the **original** file at render time.
- **Thumbnails / frame grabs:** `AVAssetImageGenerator` (async `image(at:)`) for AVF formats; ffmpeg `-frames:v 1` for others.
- **VP9/AV1 in AVPlayer:** `VTRegisterSupplementalVideoDecoderIfAvailable` may enable VP9 decode in AVFoundation, which would let WebM proxies be plain remuxes (SPIKE S-9, a nice-to-have).
- Audio scrubbing waveforms come from `AVAudioFile` where readable (§11).

---

## 14. Testing

1. **Plan golden tests (unit, fast):** for each route and tool, `(fixture MediaInfo JSON, options) → argv` is snapshot-tested. Covers remux decisions, HDR, alpha, odd dimensions, channel limits, cover-art mapping and every default in §10. This is the bulk of the 80% coverage target.
2. **Parser tests:** `ProgressParser` (`N/A` values, negative initial `out_time_us`, `progress=end`), ffprobe JSON decoding (missing fields), stderr error classification.
3. **Pair integration tests (CI, bundled engine):** `tests/fixtures/media/` holds small (1–3 s) files for every input format plus edge cases:
   - VFR GIF with transparency
   - 10-bit HDR HEVC (PQ)
   - rotated iPhone MOV
   - 5.1 FLAC
   - 24-bit WAV
   - mono Opus
   - MKV with ASS subtitles and chapters
   - AVI with PCM
   - WMV
   - MP3 with cover
   - a file without audio
   - a file with only audio
   - odd dimensions 853×479

   **All 104 pairs plus all media tools** run, and each output is verified with ffprobe (codec, container, duration ±1%, channel count, alpha kept where promised). The build fails if any advertised pair fails, so we only ship the encoders we advertise.
4. **Capability-gating test:** delete an encoder from a test build and assert the wheel hides the slice and shows the reason.
5. **Cancellation/orphan tests:** cancel mid-encode, then assert no output beside the source, temp dir gone, process gone. Kill the parent and assert the next launch reaps the child.
6. **Signing test (release pipeline):** `codesign --verify --strict`, `spctl`, check runtime flags on helpers and dylibs, and launch the notarized app on a clean VM to run one pair.
7. **Quality calibration (one-off, S-3):** VMAF of VT presets vs x264 CRF. Defaults are set from the data.

---

## 15. Open questions and spikes

| ID | Question | Method | Blocks |
|---|---|---|---|
| S-1 | Real stripped size of the shared build (target ≤ 30 MB) | run §6 script | release size budget |
| S-2 | Does Xcode "Code Sign On Copy" apply hardened runtime + timestamp to Helpers and dylibs? | `codesign -dv` after an archive | signing script vs Xcode phases |
| S-3 | VT `-q:v` presets vs x264 CRF (VMAF), and `spatial_aq` gains | fixture set + libvmaf (dev-only build) | default presets |
| S-4 | swift-subprocess 1.0.2 API details (teardown, process group, QoS) under Swift 6 strict concurrency; fallback to `Foundation.Process` if needed | prototype runner | runner implementation |
| S-5 | SVT-AV1 still-picture AVIF through FFmpeg 9 (`-svtav1-params avif=1`) quality vs ImageIO | encode test images | AVIF fallback |
| S-6 | AIFF ID3 cover-art support in the aiff muxer; WMA cover | mux test | metadata copy rules |
| S-7 | ImageIO AVIF writing on macOS 26.x (verified only on 27) | run `CGImageDestinationCopyTypeIdentifiers` on 26 | image engine fallback |
| S-8 | Sandboxed helper with fd passing (§7.5) | prototype | security hardening (post-v1) |
| S-9 | AVPlayer VP9 playback after `VTRegisterSupplementalVideoDecoderIfAvailable` | prototype | proxy strategy |
| S-10 | AudioToolbox Ogg-Opus writing on macOS 26 (seen on 27) | not needed if ffmpeg is the engine | informational |

---

## 16. RECOMMENDATION

**Choice:** option **(a)**, a self-built, bundled **ffmpeg 9.0.x + ffprobe** as the only conversion and processing engine for audio, video and GIF. AVFoundation is used **only for UI** (preview, thumbnails, waveforms). The build:
- is configured as **GPLv3** (`--enable-gpl --enable-version3`, never `nonfree`);
- links **libx264, libvpx, SVT-AV1, dav1d, libopus, libvorbis/libogg, LAME, libwebp, zimg**, plus **VideoToolbox/AudioToolbox**;
- is shipped as shared libav\* dylibs (codecs folded in) in `Contents/Frameworks` and two helpers in `Contents/Helpers`;
- is signed with Developer ID, hardened runtime, secure timestamp and **no entitlements**, then notarized and stapled;
- is driven through a pure argv planner, a `swift-subprocess` runner with `-progress pipe:1` parsing, SIGTERM→SIGKILL cancellation, per-job temp directories, atomic publish and ffprobe verification.

**Rationale:**
1. It is the only option that covers all 104 media pairs and all media tools with **one** consistent pipeline. AVFoundation covers about 19%. The in-process libraries would need a transcoder rewrite or a non-reentrant fftools hack.
2. Process isolation gives crash safety on hostile files, trivial cancellation, parallelism and memory hygiene.
3. Hardware where it exists (VT H.264/HEVC/ProRes, `aac_at`), best software encoders where it doesn't (VP9, AV1, Opus, Vorbis, MP3), and x264 for exact target-size. Every advertised output uses a real, tested encoder, never an experimental one.
4. Being GPLv3 removes LGPL limits on which encoders can be linked. The size cost is small (about 25 MB).
5. Reproducible, path-clean builds with a CI gate (license, dependencies, encoder list, all-pairs test) make "we ship the encoders we advertise" enforceable, not aspirational.

**Risks:**
- **Build pipeline upkeep:** about 10 upstreams, autotools quirks (LAME symbol list, Vorbis `-force_cpusubtype_ALL`), and FFmpeg major bumps. Mitigation: lockfile, cached CI artifact, Renovate-style PRs, and FFmpeg 8.1.x as a known-good fallback branch.
- **Signing/notarization of nested code:** a single unsigned or non-runtime dylib fails notarization. Mitigation: an explicit signing script and a verification step in CI (S-2).
- **Software VP9 is slow** (about 0.5–0.7x realtime at 1080p on M2 Pro). Mitigation: `-cpu-used 5`, row-mt, a determinate progress bar with ETA from `speed=`, an AV1 (SVT, about 3x realtime) option, and queueing software jobs one at a time.
- **Patent exposure of software H.264 (x264):** low in practice for a free app, and VideoToolbox is the default. Mitigation: one-flag removal (`--disable-libx264`), losing only "Accurate" 2-pass. x265 is excluded for this reason.
- **ffmpeg runs unsandboxed on untrusted files.** Mitigation: `--disable-network`, minimal environment, fast security point releases through Sparkle, signature check, and the post-v1 sandboxed-helper spike (S-8).
- **Orphaned children after a crash.** Mitigation: process groups and PID files reaped at launch.
- **GPL source obligations:** every release must ship the matching source bundle. Mitigation: produced by the same CI job and attached automatically.

**Fallback:**
- If the self-built pipeline slips, start from **Homebrew-equivalent component versions built by the same script without x264** (VT-only H.264). If the build is still blocked, use a **temporary static build from a reputable reproducible script** (for example, adapting `markus-perl/ffmpeg-build-script`, MIT, **without** its `--enable-gpl-and-non-free` flag, which pulls fdk-aac) so app work can proceed. Swap in our own artifact before the first public release.
- If shared-dylib signing proves troublesome, switch to **two static executables** (about 2× size) or a static ffmpeg plus a minimal static ffprobe built with `--disable-encoders --disable-muxers` (about 12 MB).
- If FFmpeg 9.0.x shows a regression in our pair tests, pin **8.1.3**. Our usage is CLI-only, so nothing else changes.

---

## Sources

- FFmpeg releases and branches: https://ffmpeg.org/download.html. Changelog for 9.0/8.1 at tag `n9.0.2` (GitHub mirror FFmpeg/FFmpeg). `configure` and `libavcodec/videotoolboxenc.c` and `libsvtav1.c` at `n9.0.2`.
- FFmpeg legal checklist: https://ffmpeg.org/legal.html
- libvpx tags (v1.17.0) and `configure` targets: https://github.com/webmproject/libvpx
- SVT-AV1 releases and CHANGELOG (v4.2.0, 2026-07-14): https://gitlab.com/AOMediaCodec/SVT-AV1
- x264 stable branch: https://code.videolan.org/videolan/x264 ; x265 tags: https://bitbucket.org/multicoreware/x265_git
- libaom releases: https://storage.googleapis.com/aom-releases/ ; dav1d: https://code.videolan.org/videolan/dav1d ; Opus/Ogg/Vorbis: https://github.com/xiph ; libwebp: https://github.com/webmproject/libwebp ; zimg: https://github.com/sekrit-twc/zimg
- swift-subprocess (1.0.2, teardown sequence, process group, QoS): https://github.com/swiftlang/swift-subprocess
- FFmpegKit retirement / archive: https://github.com/arthenica/ffmpeg-kit ; kingslay/FFmpegKit: https://github.com/kingslay/FFmpegKit ; SwiftFFmpeg: https://github.com/sunlubo/SwiftFFmpeg ; MPVKit: https://github.com/mpvkit/MPVKit ; SFBAudioEngine: https://github.com/sbooth/SFBAudioEngine
- markus-perl/ffmpeg-build-script (reference only): https://github.com/markus-perl/ffmpeg-build-script
- Apple: Placing content in a bundle (https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle); Hardened Runtime and notarization (https://developer.apple.com/documentation/security/hardened-runtime, https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- HandBrake VideoToolbox docs (encoder set, no AV1 encode): https://handbrake.fr/docs/en/1.9.0/technical/video-videotoolbox.html ; Jellyfin Apple hardware acceleration (AV1 decode from M3): https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/apple
- Local verification scripts and benchmark (local prototype, not published): `vt.swift`, `at.swift`, `iio.swift`, `bench.sh`, `bench2.sh`, `cov.sh` (M2 Pro, macOS 27.0, Homebrew ffmpeg 8.1.2).
