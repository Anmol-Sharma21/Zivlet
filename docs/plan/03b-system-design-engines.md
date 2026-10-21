# 03b — System design, part 2: media, image, actions, shell, security

Date: 2026-10-20. Part 2 of 2 ([index](03-system-design.md), [part 1](03a-system-design-interaction.md)).
Citation keys as in 03a: `[10 §n]`, `[11 §n]`, `[13 §n]`, `[14 §n]`, `[15 C-n]`, `[01-prd …]`, `[D00]`, `[spec]` (Zivlet design value),
`[new]` (chosen here; the named spike tunes it).

---

## 5. Media engine (`EngineMedia`)

### 5.1 Probe model

```
ffprobe -v error -hide_banner -of json -show_format -show_streams -show_chapters
        -protocol_whitelist file -format_whitelist mov,matroska,webm,avi,asf,mp3,wav,flac,ogg,aiff,gif
        file:<abs path>
```
Source: [11 §8.2], [10 §8.9 challenge]. Decoded into immutable values:

```swift
public struct MediaInfo: Sendable, Codable, Equatable {
    public let formatName: String            // ffprobe format.format_name → forced -f demuxer (§5.2)
    public let durationMicros: Int64?        // nil = unknown → indeterminate progress
    public let bitRate: Int?
    public let tags: [String: String]
    public let streams: [StreamInfo]
    public let chapterCount: Int
}
public struct StreamInfo: Sendable, Codable, Equatable {
    public let index: Int
    public let kind: Kind                    // video, audio, subtitle, attachment, data
    public let codec: String, profile: String?
    public let width: Int?, height: Int?, pixFmt: String?, bitsPerRawSample: Int?, hasBFrames: Int?
    public let colorTransfer: String?, colorPrimaries: String?, avgFrameRate: Rational?
    public let sampleRate: Int?, channels: Int?, channelLayout: String?, sampleFmt: String?
    public let isAttachedPic: Bool, isDefault: Bool, rotationDegrees: Int, language: String?
}
```

| Derived predicate | Rule | Source |
|---|---|---|
| `isHDR` | `colorTransfer ∈ {smpte2084, arib-std-b67}` | [11 §8.2] |
| `bitDepth` | `bitsPerRawSample`, else a pix_fmt table (`…p10le`, `p010le` → 10; `…p12le` → 12; else 8). No substring test (a naive substring match misclassifies formats such as `nv12`) | [spec] |
| `hasAlpha` | pix_fmt ∈ {yuva420p, yuva444p, rgba, bgra, argb, abgr, gbrap, ya8} | [11 §10.3] |
| `primaryVideo` | first video stream with `!isAttachedPic` | [11 §10] |
| `primaryAudio` | default-disposition audio, else first audio | [11 §10.1] |
| `cover` | stream with `isAttachedPic` (mapped by index, never by type) | [11 §10] |

Probe once per file per job; wheel-hover probes cached by `(path, size, mtime)`, 150 ms budget [11 §8.2].

### 5.2 Planner contract and canonical argv

[review] Dispatch is an explicit route table on the source and target categories: video→gif, gif→video, audio|video→audio, video→video; any other pair (image, document, data, archive) is `pairNotSupported` before a planner runs. `MediaPlanner.plan(_:catalog:registry:)` takes the catalog and registry (default `.standard`).

`AudioPlanner`, `VideoPlanner`, `GIFPlanner`, `ToolPlanner`: `(MediaInfo, target, ConversionOptions, Capabilities) throws -> FFmpegPlan`,
all pure. `FFmpegPlan {passes: [FFmpegPass {argv, weight}], expectedDurationMicros, outputs, lane}` ([review]: one pass value instead of parallel `passes`/`passWeights` arrays; weights finite and > 0, at least one pass, enforced by the throwing init and the decoder) [11 §8.1]. Goldens compare the
whole argv, so the order is fixed:

```
-hide_banner -nostdin -y -loglevel error -progress pipe:1 -nostats
-protocol_whitelist file,pipe -f <demuxer> -i file:<src>
[-f ffmetadata -i file:<job>/meta.txt]                  ← only files Zivlet wrote (cover tags, chapters)
<-map …> <video args> [-vf <chain>] <audio args> <subtitle args>
-map_metadata 0 -map_chapters 0                          ← or -1 -1 when "Preserve metadata" is off
<container args> -f <muxer> file:<staged>
```

| Rule | Value | Source |
|---|---|---|
| Demuxer map | mp4/mov/m4a → `mov`; mkv/webm → `matroska`; avi → `avi`; wmv/wma → `asf`; mp3, wav, flac, aiff, gif → same; ogg/opus → `ogg` | [10 §8.9 challenge] |
| Paths | Always absolute, `file:` prefixed; never inside a filtergraph; extra inputs by index | [11 §8.4] |
| Filter order in `-vf` | tonemap → scale → even-dims → format | [11 §10] |
| HDR → 8-bit target | `zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p` | [11 §10] |
| Odd dimensions | `scale=trunc(iw/2)*2:trunc(ih/2)*2` only when needed | [11 §10] |
| Max height option | Original / 2160 / 1080 / 720 → `scale=-2:<H>` only if source display height > H | [spec] |
| Metadata off | `-map_metadata -1 -map_chapters -1`, cover dropped | [spec] |

### 5.3 Per-stream copy decision

Each kept stream is copied if its codec is in the target's copy set and the playable predicate holds; otherwise re-encoded with the
target default [10 R-14].

| Target | Video copy set | Audio copy set | Extra predicate | Source |
|---|---|---|---|---|
| mp4 | h264, hevc, av1, mpeg4 | aac, alac, mp3, ac3, eac3 | AV1 only if AV1 HW decode **and** "Maximum compatibility" (default on) is off; HEVC adds `-tag:v hvc1`; mpeg4 only Simple Profile with `hasBFrames == 0`, else `-bsf:v mpeg4_unpack_bframes` or re-encode | [10 §4.5], [15 C-9] |
| mov | h264, hevc, prores, mjpeg, mpeg4 | aac, alac, pcm_*, mp3 | as mp4 | [10 §4.5] |
| mkv | video (cover art included), audio, attachments: per-stream `-map 0:<i>` then `-c copy` ([review]: not `-map 0`; ffmpeg 8.1.2 refuses `tmcd`/data streams and `mov_text` in Matroska) | same | data streams (`tmcd`, `mebx`) dropped; `mov_text`/`text` → `-c:s:<k> srt`; subrip/ass/ssa/webvtt/dvd/pgs/dvb subs copied; other subtitle codecs dropped; chapters kept | [11 §10.2], [review] |
| webm | vp8, vp9, av1 | opus, vorbis | text subs → `webvtt`, others dropped | [11 §10.2] |
| avi | mpeg4, mjpeg, h264 | mp3, pcm_s16le, ac3 | ≤ 2 ch | [11 §10.2] |
| wmv | wmv1, wmv2 | wmav2 | ≤ 2 ch, ≤ 48 kHz | [11 §10.2] |

Pair test: AVFoundation `isPlayable` on every MP4/MOV output (M-COPY, M1 and M3+) [15 C-9].

### 5.4 Audio outputs (sources: any audio, or the primary audio of a video)

Map: `-map 0:<primaryAudio> -vn -sn -dn` (+ `-map 0:<cover> -c:v copy -disposition:v:0 attached_pic` where noted).
Quality ladder = Settings › Formats per output (default **Balanced**).

| Target | Muxer | Encoder | Compact | **Balanced (default)** | High | Other choices | Constraints | Cover | Copy when source is |
|---|---|---|---|---|---|---|---|---|---|
| mp3 | `mp3` | `libmp3lame` | `-q:a 4` | `-q:a 2` | `-q:a 0` | CBR 128/192/256/320 `-b:a` | `-ar 48000` if > 48 kHz; `-ac 2` if > 2 ch; `-id3v2_version 3 -write_xing 1` | APIC (map) | mp3 |
| m4a | `ipod` | `aac_at` | `-b:a 128k` | `-b:a 192k` | `-b:a 256k` | 320k; Lossless → `alac_at` | > 48 kHz → 48000; ≤ 7.1; `-movflags +faststart` | attached_pic (map) | aac, alac |
| wav | `wav` | `pcm_s16le/s24le/s32le/f32le` | — | match source depth | — | 16 / 24 / 32f | `-rf64 auto` | none | pcm_s16le/s24le/s32le/f32le |
| aiff | `aiff` | `pcm_s16be/s24be/s32be` | — | match source (float → s24be) | — | 16 / 24 / 32 | `-write_id3v2 1` | spike M-6 | pcm_s16be/s24be/s32be |
| flac | `flac` | `flac` | `-compression_level 3` | `-compression_level 8` | `-compression_level 12` | — | 24-bit → `-sample_fmt s32 -bits_per_raw_sample 24`; float → 24-bit; otherwise explicit `-sample_fmt s16` ([review]: without it ffmpeg 8.1.2 picks s32/24-bit for a lossy decoder's `fltp`) | attached_pic (map) | flac |
| ogg | `ogg` | `libvorbis` (forced) | `-q:a 3` | `-q:a 6` | `-q:a 8` | q 5 | ≤ 8 ch | `METADATA_BLOCK_PICTURE` via ffmetadata | vorbis |
| opus | `opus` | `libopus` | `-b:a 96k` | `-b:a 128k` | `-b:a 192k` | 64/160/256k | always `-vbr on -application audio -ar 48000`; > 2 ch → `-mapping_family 1` | `METADATA_BLOCK_PICTURE` via ffmetadata | opus |
| wma | `asf` | `wmav2` | `-b:a 128k` | `-b:a 192k` | `-b:a 192k` (ladder ceiling) | 160k | `-ac 2`, ≤ 48 kHz | dropped (noted) | wmav2 |

Sources: rows [11 §10.1], [10 §4.4]; FLAC levels [spec]; ladders compact/high [11 §10.1 "quality options"]. Depth "match source":
≤ 16 → s16, ≤ 24 → s24, 32-int → s32, float → f32; unknown → 16 [11 §10.1], [spec]. [review] "Float" means a float PCM codec (`pcm_f*`), never `sample_fmt`: lossy decoders (mp3, aac, vorbis, opus, wma) report `fltp` and count as unknown depth, so mp3 → wav is `pcm_s16le`, mp3 → flac 16-bit, aac → aiff `pcm_s16be`. Never the experimental native
`vorbis`/`opus` encoders [10 §4.4].

### 5.5 Video outputs (sources: mp4 mov mkv webm avi wmv; gif in §5.6)

Video quality: Compact / Balanced / High. Default Balanced, **MOV High** (parity) [spec].

| Target | Video re-encode | Compact / Balanced / High | Audio re-encode | Streams mapped | Container args | Source |
|---|---|---|---|---|---|---|
| mp4 | `h264_videotoolbox -profile:v high -allow_sw 1 -pix_fmt yuv420p -tag:v avc1 -q:v Q`; 10-bit/HDR → `hevc_videotoolbox -profile:v main10 -pix_fmt p010le -tag:v hvc1 -q:v Q` (colour tags copied) | Q = 48 / 60 / 72 | `aac_at -b:a 192k`, `-ac 6` if > 6 ch | `0:<v>` + all audio + text subs → `-c:s mov_text`; image subs dropped (noted) | `-movflags +faststart` | [11 §9, §10.2] |
| mov | as mp4; ProRes option `prores_videotoolbox -profile:v 2` (audio `pcm_s16le`); alpha source → `hevc_videotoolbox -pix_fmt bgra -alpha_quality 0.75 -tag:v hvc1` | Q = 48 / 60 / 72 | `aac_at -b:a 192k` | as mp4 | `-movflags +faststart` | [11 §9, §10.2] |
| mkv | VT H.264 (as mp4) only for streams that can't be copied | Q = 48 / 60 / 72 | `aac_at -b:a 192k` only if needed | per-stream maps (see §5.3) | — | [11 §10.2] |
| webm | `libvpx-vp9 -b:v 0 -row-mt 1 -tile-columns 2 -deadline good -cpu-used 5 -pix_fmt yuv420p -crf C` (alpha → `yuva420p`); AV1 option `libsvtav1 -preset 8 -crf 35 -pix_fmt yuv420p -svtav1-params tune=0` | C = 37 / 32 / 27 | `libopus -b:a 128k -ar 48000` (> 2 ch `-mapping_family 1`) | `0:<v>` + primary audio + text subs → `webvtt` | — | [11 §9, §10.2]; C ±5 [new; M-3] |
| avi | `mpeg4 -vtag xvid -fps_mode cfr -q:v Q` | Q = 5 / 3 / 2 | `libmp3lame -b:a 192k` (CBR), `-ac 2` | `0:<v>` + primary audio | — | [11 §10.2]; ladder [new; M-3] |
| wmv | `wmv2 -fps_mode cfr -q:v Q` | Q = 5 / 3 / 2 | `wmav2 -b:a 192k`, `-ac 2`, `-ar 48000` when the source is above 48 kHz ([review]: wmav2 refuses 96 kHz) | `0:<v>` + primary audio | `-f asf` | [11 §10.2]; ladder [new; M-3] |
| mp3 | — | — | as §5.4 mp3 (copy if MP3) | `0:<primaryAudio> -vn -sn -dn` | — | [10 §4.5] |

| Fallback / policy | Rule | Source |
|---|---|---|
| VT session fails | `libx264 -preset medium -crf C`, C = 26 / 23 / 20 | [11 §9] |
| Software video lane | VP9, AV1, x264 → `swVideo` (width 1); VT → `hwVideo` | [10 §8.1] |
| VT values | Starting points; calibrate by VMAF vs x264 CRF 20/23/26 (M-3) | [11 §9] |
| Rotation | autorotate on re-encode; display matrix kept on copy | [11 §10] |

### 5.6 GIF

**Video → GIF** (`GIFPlanner`), no audio:

```
-filter_complex "[0:<v>]<tonemap,>fps=F,scale='min(W,iw)':-2:flags=lanczos,split[a][b];
                 [a]palettegen=stats_mode=diff:max_colors=256[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle"
-an -loop 0 -f gif file:<staged>
```

| Option | Default | Choices | Source |
|---|---|---|---|
| F (fps) | 15, capped at source fps (planner writes the number) | 10 / 15 / 24 | [11 §10.3], [spec] |
| W (max width) | 480 | 320 / 480 / 640 / 800 / Original | [11 §10.3], [10 §4.5] |
| Dither | Sierra (smooth) `sierra2_4a` | Bayer (smaller) `bayer` | [11 §10.3] |
| Guard | Warn before encoding if estimated output > 50 MB or clip > 60 s; offer a trim range | [11 §10.3] |
| No video stream | `MediaPlanError.noVideoTrack`; shown as "There's no video in this file to turn into a GIF." [critic3: own copy] | [spec] |

**GIF → video:**

| Target | Rule | Source |
|---|---|---|
| mp4, mkv | VT H.264 (§5.5), `-fps_mode vfr`, alpha flattened: `color=white:s=WxH[bg];[bg][0:v]overlay=shortest=1,format=yuv420p` (noted) | [11 §10.3], [10 §4.6] |
| mov | HEVC-alpha (keeps transparency), `-fps_mode vfr` | [10 §4.6] |
| webm | VP9 `yuva420p` (keeps alpha), `-fps_mode vfr` | [10 §4.6] |
| avi, wmv | `-fps_mode cfr -r round(avg_frame_rate)` capped at 50, flattened; no `-r` when the probed rate is not finite or outside (0, 1000] (`StreamInfo.usableFrameRate`; the GIF `fps=` then uses the option alone) | [11 §10.3], [review] |

### 5.7 Golden examples (Balanced, metadata on)

```
mp4 (h264+aac) → mov:   … -f mov -i file:/a/x.mp4 -map 0:0 -map 0:1 -c:v copy -c:a copy
                        -map_metadata 0 -map_chapters 0 -movflags +faststart -f mov file:<staged>
mkv (h264+opus) → mp4:  … -f matroska -i file:/a/x.mkv -map 0:0 -map 0:1 -c:v copy -c:a aac_at -b:a 192k
                        -map_metadata 0 -map_chapters 0 -movflags +faststart -f mp4 file:<staged>
wav (24-bit) → mp3:     … -f wav -i file:/a/x.wav -map 0:0 -vn -sn -dn -c:a libmp3lame -q:a 2
                        -map_metadata 0 -map_chapters 0 -id3v2_version 3 -write_xing 1 -f mp3 file:<staged>
```
(`…` = the fixed prefix of §5.2 up to `-protocol_whitelist file,pipe`.) One golden file per pair × option set lives in
`Packages/ZivletKit/Tests/EngineMediaTests/Goldens/`.

### 5.8 Media tools (planner rows)

| Tool | argv core | Source |
|---|---|---|
| Mute | `-map 0 -map -0:a -c copy` (lane `remux`) | [10 §5 #8] |
| Compress video | VT HEVC `-q:v` 55 (Balanced) / 45 (Strong) + optional 1080/720 cap + AAC 128k/96k; target size: Fast = VT ABR ×0.92 retry ≤ 3, Accurate = x264 2-pass | [11 §11], [10 §5 #1] |
| Compress audio | Same codec at a lower bitrate; wav/aiff → FLAC; output ≥ input → "Already optimal" | [10 §5 #1] |
| Normalize | Two-pass `loudnorm` (measured values into pass 2, `linear=true`); presets −16/−14/−23 LUFS, TP −1.5, LRA 11 | [10 §5 #7] |
| Speed | `setpts=(PTS-STARTPTS)/s`; `atempo` chain: halve while s < 0.5, double while s > 2.0, append remainder | [spec] |
| Trim Video | Fast: `-c copy -avoid_negative_ts make_zero`; Exact: re-encode | [10 §5 #9] |

### 5.9 Verification and errors

| Check | Rule | Source |
|---|---|---|
| Streams | Expected kinds present in ffprobe of the output | [11 §8.4] |
| Duration | `|out − expected| ≤ max(0.25 s, 1 %)` | [11 §8.4] |
| Size | > 0; Compress: < source or < target, else discard | [11 §8.4] |
| Playable | MP4/MOV: `AVURLAsset.load(.isPlayable)` | [15 C-9] |
| Errors | `noAudioTrack`, `noVideoTrack`, `encoderUnavailable`, `diskFull` (from `No space left on device`), `ffmpegFailed(status, stderrTail 64 KB)`, `crashed(signal)` → Core taxonomy | [11 §8.5], [10 §8.4] |

---

## 6. Image engine (`EngineImage`)

### 6.1 Pipeline (ImageIO + Core Image, in the worker)

| Step | Rule | Source |
|---|---|---|
| Decode | `CGImageSourceCreateWithURL` with `kCGImageSourceShouldCache: false`; resize via `CreateThumbnailAtIndex` + `ThumbnailMaxPixelSize` + `WithTransform: true` | [13 §2.1] |
| Orientation | EXIF orientation applied exactly once. The tag is kept (pixels copied unturned) only for JPEG, HEIC/HEIF and TIFF, whose readers honour it and whose ImageIO encoders write it; PNG, BMP, GIF, AVIF (ImageIO writes no `irot`/`imir`), WebP and any other type get it baked into the pixels and written as 1; PDF applies it through the page transform | [10 §4.2], [new: 09 D-M3-29] |
| Colour | Keep source ICC (e.g. Display P3) unless the preset says "Web (sRGB)" | [10 §4.2] |
| Depth | Keep 16-bit where the target allows (PNG, TIFF, HEIC 10-bit) | [10 §4.2] |
| HDR | Gain map kept for HEIC/AVIF/JPEG (`kCGImageDestinationEncodeToISOHDR`); else `CIToneMapHeadroom` to 8-bit | [13 §2.1] |
| Alpha → JPEG/BMP-24 | Flatten onto the background colour (default white); card notes it | [10 §4.2 fn 2] |
| Metadata | EXIF/XMP carried via the properties dictionary; "Preserve metadata" off → empty dictionary after thumbnail decode | [10 §4.2], [spec] |
| Encode | `CGImageDestinationAddImage` into staging; finalize; verify by re-opening the output | [13 §2.1] |
| Memory | Decode cap 200 MP with tiling | [10 §8.9] |

### 6.2 Per-target encode settings

Image quality: Compact / **Balanced (default)** / High; options apply per output format [spec].

| Target | Engine | Compact / Balanced / High | Other settings | Source |
|---|---|---|---|---|
| jpg | ImageIO | `kCGImageDestinationLossyCompressionQuality` 0.65 / 0.85 / 0.96 | baseline; alpha flattened | [spec] |
| heic | ImageIO | 0.65 / 0.85 / 0.96 | animated source → HEICS | [spec], [10 §4.2] |
| avif | ImageIO (if writable, G-0) | 0.65 / 0.85 / 0.96 | fallback `libsvtav1 -svtav1-params avif=1:tune=3`, `yuv444p` for graphics; card: "transparency/colour profile not preserved"; hidden for alpha sources | [spec], [10 §4.2 challenge] |
| webp | libwebp (`CWebP`) | `config.quality` 65 / 85 / 96 | `method 4`, `use_sharp_yuv 1`; alpha → `exact 1`; metadata via `WebPMux` ICCP/EXIF/XMP; animated → `WebPAnimEncoder` with source delays | [spec], [13 §2.3] |
| png | ImageIO | — | animated → APNG; P1: oxipng lossless pass | [10 §4.2], [13 §2.4] |
| tiff | ImageIO | — | LZW (`kCGImagePropertyTIFFCompression = 5`); multi-page kept | [spec] |
| bmp | ImageIO | — | — | [10 §4.2] |
| pdf | Quartz (`QZ`) | — | JPEG source bytes embedded unchanged; page = image size at its DPI (72 if absent); multi-page TIFF → multi-page PDF | [10 §4.1, §4.2], [new page rule] |

| Rule | Value | Source |
|---|---|---|
| Animated source → non-animated target | First frame + "Animation flattened to first frame" | [10 §4.2] |
| Multi-page (non-animated) source → single-image target | Folder `<base> Images` | [spec] |
| Lossless WebP larger than source | Never written as a silent fallback | [10 §4.2] |

### 6.3 Compress (images)

| Step | Rule | Source |
|---|---|---|
| WebP | libwebp `target_size = bytes`, `pass = 6`, `method 6` | [13 §2.3] |
| JPEG/HEIC/AVIF/TIFF | Binary search quality in [0.30, 0.92], ≤ 7 in-memory encodes; if still too big, max pixel −15 % per step, ≤ 3 steps; keep the best | [13 §2.6] |
| Preset budgets | Balanced: ≤ 0.8 × source; Strong: ≤ 0.5 × source | [spec] |
| Size presets | Original / Large 2560 / Medium 1920 / Small 1280 px longest edge | [spec] |
| PNG | libimagequant + oxipng (Phase 2) | [10 §5 #1] |
| Guard | Output ≥ input → keep nothing, report "Already optimal" | [13 §2.6] |

### 6.4 SVG and PDF raster (image-side routes)

| Route | Rule | Source |
|---|---|---|
| svg → raster | resvg at 2× intrinsic size, longest edge ≤ 8192; `.svgz` gunzipped in Swift, ≤ 64 MB; resolver accepts `data:` only | [10 §4.1, §4.3, §8.9] |
| svg fallback | NSImage, then offline WKWebView; renderer named on the card | [10 §4.3] |
| svg → pdf | krilla-svg vector PDF (same usvg 0.47 tree) | [10 §3 challenge] |
| pdf → jpg/png | 300 DPI default (presets 72/150/300/600), cap 16,384 px and 200 MP; white background; JPEG quality per §6.2; one page → file, several → `<base> <EXT> Pages/Page 001.<ext>` | [10 R-8], [spec] |

---

## 7. Actions (`ZivletActions`, app process, no engine)

| # | Action | Implementation | Errors / edge cases | Source |
|---|---|---|---|---|
| 1 | AirDrop | `NSSharingService(named: .sendViaAirDrop)`; de-dup by `standardizedFileURL`; `canPerform(withItems:)` then `perform`; controller retained until the delegate fires | "Zivlet couldn't start AirDrop for these files." [critic3: all strings in this column are Zivlet's own copy]; `NSUserCancelledError` (3072) is silent | [10 §6], [spec] |
| 2 | Float | `FloatShelfPanel`: non-activating `NSPanel`, `.floating`, `canJoinAllSpaces + stationary + ignoresCycle + fullScreenAuxiliary`; several shelves; `floatWheelBehavior` = new shelf (default) / add to most recent; edge attach within 28 pt, stay within 48 pt, move after 8 pt; new shelves cascade (+24, −24); presentation change 0.26 s; click-through by hit-testing the drawn shape, monitor installed only while visible; type-to-select resets after 0.8 s; references files, never copies; restored after relaunch | Missing file → greyed + "Locate…" | [10 §6], [spec] |
| 3 | Copy | `NSPasteboard.general.clearContents()` + `writeObjects(urls as [NSURL])` | "Copy works only with items stored on this Mac." | [10 §6], [spec] |
| 4 | Move | `NSOpenPanel` (directories, prompt "Move Here", above the wheel); per item `NSFileCoordinator` write + `moveItem`; collisions → `name 2`; `EEXIST` race → next name; cross-volume: copy, verify size + count, trash source; folder into itself refused; UndoLog entry | "Choose a folder on this Mac to move into."; result "Moved N items" + per-item failures | [10 §6], [spec] |
| 5 | Copy Path | Newline-joined POSIX paths as `.string`; ⌥ held at drop: shell-quoted, space-separated | "Paths can be copied only for items stored on this Mac." | [10 §6] |
| 6 | Terminal | Folder stays; file/package → parent; de-dup; `NSWorkspace.open(dirs, withApplicationAt:, configuration:)`; terminals: Terminal (default), iTerm2, Ghostty, WezTerm, Warp, each verified by P-TERM; unknown stored id → Terminal | "<Name> isn't installed. Choose another in Settings." | [10 §6], [spec] |

| Rule | Value | Source |
|---|---|---|
| Ordering | Wheel hidden first; AirDrop, Move, Terminal deferred one run-loop turn so the drag session ends before a panel takes focus | [spec] |
| Success feedback | Small HUD toast ("Copied 3 items", "Moved 2 items · Undo") | [spec], [01-prd §5.8] |
| Failure UI | Non-modal card with the file name per failure; no app-modal `runModal` | [spec] |
| Non-file URLs | Refused per action with the copy above | [spec] |

---

## 8. Settings, onboarding, menu bar, launch at login

### 8.1 Settings store

`SettingsStore` (`@Observable @MainActor`) over `UserDefaults`, one versioned Codable value per group, migrations by
`schemaVersion`; no scattered `@AppStorage` [14 §3.2]. Invalid stored values → defaults + log line (validated at load).

| Key group | Field | Default | Source |
|---|---|---|---|
| Trigger | `TriggerBindings` | ⇧ / ⌘ / ⌃ | §1.7 |
| | `honorsModifierHeldAtDragStart`, `retapClosesWheel` | false [critic3], true | 03a §1.5 |
| | Esc closes wheel (opt-in) | off | [14 §1.3] |
| | Ignore list (source apps) | empty | [14 §1.4] |
| Feedback | Sound / Haptics | on / on | [spec], [14 §2.4] |
| | Wheel style | Glass (alt: Solid high-contrast) | [14 §2.3] |
| Output | Location | Beside original; fallback `~/Downloads` | [D00 O-14] |
| | Reveal results in Finder | on [critic3: 01-prd §5.8, 03a §4] | [spec] |
| | Copy Finder tags | on | [10 §8.5] (optional there), [new] default |
| Formats (per output) | quality | Balanced; MOV High | [spec] |
| | preserve metadata | on | [spec] |
| | video max height | Original | [spec] |
| | audio depth (wav/aiff) | Match source | [spec] |
| | GIF fps / width | 15 / 480 | §5.6 |
| | Maximum compatibility (video copy) | on | [15 C-9] |
| | EPUB layout / PDF→Office layout | Reflowable / Editable paragraphs | [spec] |
| | PDF raster DPI | 300 | [10 R-8] |
| Tools | Image compress strength / size | Balanced / Original | [spec] |
| | Video compress strength | Balanced | [spec] |
| Actions | Float behaviour | New shelf | [spec] |
| | Terminal | `com.apple.Terminal` | [spec] |
| Documents | Fidelity | Automatic | [D00 O-7] |
| Automation | Apple Events features (Finder selection, iWork) | off | [D00 O-17] |
| Advanced | Lane width overrides | per §4.2 | [10 R-4] |
| Updates | Auto-check / auto-download | on / off | [14 §3.3 page 6, §3.5]; auto-download default [new] |

Panes: General, Formats, Tools, Keyboard & Automation, Updates, Advanced (helper versions, licences, Copy diagnostics)
[14 §3.2]. Window: `NSWindowController` + `NSTabViewController(.toolbar)` hosting SwiftUI `Form(.grouped)` [14 §3.2].
Formats pane also lists capability-hidden routes with the reason [10 §8.8].

### 8.2 Onboarding (720 × 480, resumable)

| Page | Content | Source |
|---|---|---|
| 1 Welcome | Name, one-line promise, where the menu bar icon is | [14 §3.3] |
| 2 Practice convert | Sample file in the window; drag, tap ⇧; the **real** trigger and wheel open (self-test; on failure show diagnostics) | [14 §3.3] |
| 3 Tools + actions | Same with ⌘ and ⌃; key caps from current bindings | [14 §3.3] |
| 4 Keyboard path | Services shortcut; optional global hotkey | [14 §3.3] |
| 5 Privacy | TCC prompts for protected folders (P-P1 table); optional "Grant now" buttons | [14 §3.3] |
| 6 Login + updates | Toggles default on; sets `SUEnableAutomaticChecks` | [14 §3.3] |
| 7 Location | If under `/Volumes/` or translocated, offer Move to Applications | [14 §3.3] |

`didCompleteOnboarding` written only on Finish; quitting resumes at the same page [14 §3.3]. Page transition 0.22 + 0.32 s
(0.14 + 0.18 s Reduce Motion) [spec]. No folder-grant page, no paywall [D00].

### 8.3 Menu bar

AppKit `NSStatusItem` (square, template icon) + `NSMenu` rebuilt in `menuNeedsUpdate` [14 §3.1], [spec]:

1. State line: "Zivlet is ready" / "Working on N".
2. Shortcut summary `⇧: Convert · ⌘: Tools · ⌃: Actions` (disabled) [spec].
3. Active tasks: one SwiftUI row each (name middle-truncated to 38 chars keeping the extension, progress bar, Cancel) [spec].
4. Recent results (Reveal / Undo).
5. Settings… (⌘,), Getting Started…, Check for Updates…, About, Quit (⌘Q).

Lifecycle: `.accessory` policy + `LSUIElement`; `disableAutomaticTermination("Watching drag gestures")`; jobs in
`beginActivity([.userInitiated, .idleSystemSleepDisabled])`; reopen (double-click app) opens Settings because the item may be
hidden by macOS 26 [14 §3.1].

### 8.4 Launch at login

| Item | Rule | Source |
|---|---|---|
| API | `SMAppService.mainApp.register()` / `unregister()`; no helper bundle | [14 §3.4] |
| State map | notRegistered → off; enabled → on; requiresApproval → needs approval; notFound → unavailable | [spec] |
| Toggle shows on | when on **or** needs approval | [spec] |
| Needs approval | Inline "Allow Zivlet in Login Items" + button → `openSystemSettingsLoginItems()` | [spec] |
| Refresh | On appear and on `NSApplication.didBecomeActiveNotification` | [spec] |
| Errors | Register throws → inline message, state re-read; never silent | [spec] |

---

## 9. Security hardening (unsandboxed app, untrusted inputs)

| Threat | Control | Where | Test | Source |
|---|---|---|---|---|
| Parser exploit takes down the app | Third-party parsers run only in `ZivletWorker.xpc` or helpers; the app runs Apple decoders only for previews the user opened | process model | hostile corpus: no crash escapes the worker | [10 §2.1 challenge] |
| Swapped helper binary | `SecStaticCodeCheckValidity` per helper, first use per launch, requirement `anchor apple generic and certificate leaf[subject.OU] = "<TEAMID>"`; never fall back to Homebrew | EngineLocator | tampered-binary test | [10 §8.9] |
| Environment injection | `PATH=/usr/bin:/bin`, fixed `LC_ALL`, `-nostdin`, private `TMPDIR`, `PERL5LIB` only ours, ExifTool `-config ''`; hardened runtime strips `DYLD_*` | SubprocessRunner | env snapshot test | [10 §8.9] |
| ffmpeg local-file disclosure (HLS/concat playlists) | Build without `hls,dash,webm_dash_manifest,sdp,rtsp,rtp` demuxers and network; probe with `-format_whitelist`; open with forced `-f` and `-protocol_whitelist file,pipe`; `concat`/`image2`/`ffmetadata` only for files we wrote | EngineMedia | HLS-as-.mp4 and ffconcat-as-.mkv fixtures refused | [15 C-4], [10 §8.9] |
| Path tricks | `file:` absolute paths; no paths in filtergraphs; output names built by `OutputNamer` only (no `/`, `:`, Cc characters, `.`/`..`; ≤ 255 bytes). [review] The media planner refuses source/staged paths with Cc characters or `..` components and a staged path that spells the source; the runtime (P1) creates the staged file exclusively (`O_EXCL`) in an app-owned temp directory and never relies on `-y` | EngineMedia, Core | property tests | [11 §8.4] |
| Quarantine laundering | Copy `com.apple.quarantine` from any input onto every output before publish | Publisher | 9 archive pairs assert the xattr | [15 C-5] |
| Archive bombs / traversal | No `..`, symlinks, absolute paths; no owner/setuid bits; total ≤ min(20 × archive + 1 GB, free − 2 GB); ≤ 100,000 entries; per-entry ratio check; no nested auto-extract | EngineArchive | zip-slip, 42.zip, symlink escape corpus | [10 §8.9] |
| XML / OOXML / EPUB | DTD/ENTITY rejected; node and depth budgets; ZIP ≤ 1 GB uncompressed, ratio ≤ 100; input cap 128 MB; DRM/`encryption.xml`/CFB `EncryptionInfo` refused | EngineDocs | fuzzers nightly | [10 §8.9] |
| Image / PDF memory | Thumbnail decode with max pixel; 200 MP cap with tiling; PDF raster ≤ 16,384 px | EngineImage, EnginePDF | giant-dimension fixtures | [10 §8.9] |
| Network exfiltration | ffmpeg `--disable-network`; no network APIs in worker or helpers; WebKit `WKContentRuleList` blocks http(s)/file/ftp, non-persistent store, navigation blocked; resvg `data:` only | engines | `nettop`-style CI check, rule-list tests | [10 §8.9] |
| Office macros / links | LibreOffice private profile, macro security Very High, no OLE/DDE updates; download pinned by SHA-256 in the EdDSA-signed manifest, Team ID checked | OfficeEngine | manifest tamper test | [10 §8.9] |
| URL scheme abuse | `zivlet://` only opens UI with files preselected; never runs a job | app | URL fuzz | [10 §8.9] |
| XPC peer spoofing | Worker accepts only connections from our Team ID (peer code-signing requirement); every request decoded and validated (non-empty inputs, known formats, paths are absolute file URLs) | ZivletIPC | wrong-signature client refused | [02 §7.5], [new; verify the macOS 26 XPC peer-requirement API in the worker phase] |
| Boundary validation | `JobRequest.init` throws on empty inputs or unknown operation; Settings decode failures → defaults; CLI args via ArgumentParser with explicit errors | Core, UI, CLI | unit tests | [02 §7.2] |
| Drop-target misuse | Copy semantics only; the negotiated drag operation never deletes or moves a source | WheelDropView | P-T6 | [15 C-8] |
| Privacy of logs | Paths `privacy: .private`; no input logging; diagnostics bundle stays local | all | log review | [10 §8.7], [spec] |
| Disk exhaustion | Preflight 1.5 × estimate + 512 MB; ENOSPC → `diskFull`; staging deleted | Runtime | fill-disk test | [10 §8.6] |
| Fuzzing | Subtitle parser (`-sanitize=fuzzer`), SDoc readers, archive and PDF corpora, nightly | CI | 0 crashes | [10 §8.9] |
