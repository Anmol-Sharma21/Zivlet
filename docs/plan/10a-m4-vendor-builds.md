# 10a — M4 stream A, part 1: vendor builds (FFmpeg + codecs, libwebp, resvg)

Part of [10-implementation-plan-m4](10-implementation-plan-m4.md). Conventions: index §6. Shell commands run from the
repository root with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; Swift commands from
`Packages/ZivletKit`.

The build recipe in A3 is the prototype script that was run on 2026-10-21 (index §3), adapted only for the repository
layout (`Vendor/` instead of a scratch directory). Every flag in it was exercised; the fixes it needed are recorded
as D-M4-3 and D-M4-4.

---

## Task A1 — `Vendor/versions.lock`, pinned fetch, gitignore (P0-36 part, 04 §6)

| Field | Value |
|---|---|
| Goal | One lock file names every vendored source (name, version or commit, URL, SHA-256). `Vendor/fetch.sh` downloads each tarball into its own empty directory under `Vendor/downloads/<name>-<version>/`, verifies the hash and refuses on mismatch, then extracts into `Vendor/src/<name>-<version>/`. Nothing downloaded is executed by the fetch step |
| 05 rows | P0-36 (lock + fetch part), carried into M4 because no `Vendor/` exists yet |
| Sources | 11a §6.1–6.2, 04 §6 (`Vendor/versions.lock`), owner rule "pinned SHA-256, untrusted downloads" |

**Files:** create `Vendor/versions.lock`, `Vendor/fetch.sh`, `Vendor/tests/test-fetch.sh`, `Vendor/tests/lib.sh`;
modify `.gitignore` (add `Vendor/downloads/`, `Vendor/prefix/`, `Vendor/logs/`, `Vendor/rs/*/target/`), `Makefile`
(targets `vendor-test`, `vendor-fetch`). Existing ignores already cover `Vendor/src/`, `Vendor/build/`, `Vendor/out/`.

### A1.1 Failing test first

`Vendor/tests/lib.sh` (tiny assert helpers, shared by every vendor test):

```bash
#!/usr/bin/env bash
# Minimal assertions for Vendor/tests/*.sh. Each test file runs in its own temp dir.
set -euo pipefail
fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1] ${3:-}"; }
assert_file() { [[ -s "$1" ]] || fail "missing file $1"; }
assert_no_file() { [[ ! -e "$1" ]] || fail "unexpected file $1"; }
assert_fails() { if "$@" >/dev/null 2>&1; then fail "command succeeded: $*"; fi; }
tmpdir() { mktemp -d "${TMPDIR:-/tmp}/zivlet-vendor-test.XXXXXX"; }
```

`Vendor/tests/test-fetch.sh`:

```bash
#!/usr/bin/env bash
# fetch.sh verifies SHA-256 before extracting, keeps one directory per component and refuses bad lock lines.
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/srv/pkg-1.0" && echo hello > "$T/srv/pkg-1.0/README"
tar -C "$T/srv" -czf "$T/pkg-1.0.tar.gz" pkg-1.0
GOOD=$(shasum -a 256 "$T/pkg-1.0.tar.gz" | cut -d' ' -f1)

echo "pkg 1.0 file://$T/pkg-1.0.tar.gz sha256:$GOOD" > "$T/good.lock"
"$ROOT/Vendor/fetch.sh" --lock "$T/good.lock" --downloads "$T/dl" --src "$T/src"
assert_file "$T/dl/pkg-1.0/pkg-1.0.tar.gz"
assert_eq "$(cat "$T/src/pkg-1.0/README")" "hello"

echo "pkg 1.0 file://$T/pkg-1.0.tar.gz sha256:$(printf '0%.0s' {1..64})" > "$T/bad.lock"
assert_fails "$ROOT/Vendor/fetch.sh" --lock "$T/bad.lock" --downloads "$T/dl2" --src "$T/src2"
assert_no_file "$T/src2/pkg-1.0"

echo "pkg 1.0 file://$T/pkg-1.0.tar.gz" > "$T/nohash.lock"
assert_fails "$ROOT/Vendor/fetch.sh" --lock "$T/nohash.lock" --downloads "$T/dl3" --src "$T/src3"

echo "../evil 1.0 file://$T/pkg-1.0.tar.gz sha256:$GOOD" > "$T/evil.lock"
assert_fails "$ROOT/Vendor/fetch.sh" --lock "$T/evil.lock" --downloads "$T/dl4" --src "$T/src4"
echo "PASS test-fetch"
```

### A1.2 Run, expect failure

`make vendor-test` → `Vendor/fetch.sh: No such file or directory` (and `make: *** No rule to make target 'vendor-test'`
before the Makefile change).

### A1.3 Implement

`Vendor/versions.lock` (hashes measured on 2026-10-21; the Xiph three also match Xiph's published `SHA256SUMS`):

```text
# name      version                                   url                                                                                                   sha256
ffmpeg      9.0.2                                     https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz                                                        sha256:8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
x264        b35605ace3ddf7c1a5d67a2eb553f034aef41d55  https://code.videolan.org/videolan/x264/-/archive/b35605ace3ddf7c1a5d67a2eb553f034aef41d55/x264-b35605ace3ddf7c1a5d67a2eb553f034aef41d55.tar.bz2  sha256:6eeb82934e69fd51e043bd8c5b0d152839638d1ce7aa4eea65a3fedcf83ff224
libvpx      1.17.0                                    https://github.com/webmproject/libvpx/archive/refs/tags/v1.17.0.tar.gz                                 sha256:1020f184046187baa2985dbde38e0691f49c44088bca7a1842b0236c6081dc0a
svtav1      4.2.0                                     https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v4.2.0/SVT-AV1-v4.2.0.tar.bz2                         sha256:512f2ea5649e3e76c2dddcc25c2556fb67a9582baaab207c9c96161c94659dad
dav1d       1.5.4                                     https://code.videolan.org/videolan/dav1d/-/archive/1.5.4/dav1d-1.5.4.tar.bz2                            sha256:2abfb0c89212e6e4733a54e0ae509ec00a5b845a6360946f918806e14aedb011
opus        1.6.1                                     https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz                                             sha256:6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1
libogg      1.3.6                                     https://downloads.xiph.org/releases/ogg/libogg-1.3.6.tar.xz                                            sha256:5c8253428e181840cd20d41f3ca16557a9cc04bad4a3d04cce84808677fa1061
libvorbis   1.3.7                                     https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.xz                                      sha256:b33cc4934322bcbf6efcbacf49e3ca01aadbea4114ec9589d1b1e9d20f72954b
lame        3.100                                     https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz                            sha256:ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
libwebp     1.6.0                                     https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz            sha256:e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564
zimg        3.0.6                                     https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.6.tar.gz                              sha256:be89390f13a5c9b2388ce0f44a5e89364a20c1c57ce46d382b1fcc3967057577
sparkle     2.10.0                                    https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz              sha256:c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
```

`Vendor/fetch.sh` rules (complete script is ~50 lines; write it to these rules):

- Arguments `--lock`, `--downloads`, `--src` (defaults `Vendor/versions.lock`, `Vendor/downloads`, `Vendor/src`);
  `--only <name>` limits to one component.
- Each non-comment line has exactly four fields; field 1 matches `^[a-z0-9][a-z0-9_-]*$`, field 2
  `^[A-Za-z0-9._-]+$`, field 4 `^sha256:[0-9a-f]{64}$`; anything else exits 2 with the line number.
- Download with `curl -fsSL --retry 3 --proto '=https,file'` into `<downloads>/<name>-<version>/` (created empty),
  skip when a file with the right hash is already there; verify with `shasum -a 256`; on mismatch delete the file and
  exit 1 printing expected and actual hashes.
- Extract with `tar -xf <file> -C <src>/<name>-<version> --strip-components 1` into a freshly created directory; the
  archive is never `cd`-ed into and nothing inside it runs during fetch.
- `sparkle` is fetched but not extracted into `src` (F2 uses the SwiftPM binary instead; the tarball provides
  `bin/generate_appcast`, `bin/sign_update`, `bin/generate_keys`, extracted to `Vendor/out/sparkle-tools/` by F5).

Makefile:

```make
vendor-test:
	@for t in Vendor/tests/test-*.sh; do bash "$$t" || exit 1; done

vendor-fetch:
	Vendor/fetch.sh
```

### A1.4 Verify green

`make vendor-test` → `PASS test-fetch`. `make vendor-fetch` → 12 components verified (about 85 s on the dev Mac's
connection, 2026-10-21), `git status --short` shows no file under `Vendor/downloads` or `Vendor/src`.

### A1.5 Commit

`git add .gitignore Makefile Vendor/versions.lock Vendor/fetch.sh Vendor/tests && git commit -s -m "chore(vendor):
pinned source lock and verified fetch"`.

---

## Task A2 — Build tool check (`Vendor/check-tools.sh`)

| Field | Value |
|---|---|
| Goal | Fail fast with one line per missing build tool, before any configure runs. Reads versions; never installs anything itself (the owner or the agent runs `brew install …` from its message) |
| Sources | 11a §6.1 (build-only tools from Homebrew, nothing linked), index §2 |

**Files:** create `Vendor/check-tools.sh`, `Vendor/tests/test-check-tools.sh`.

### A2.1 Failing test first

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
# An empty PATH (plus coreutils) must name every missing tool and exit 1.
mkdir -p "$T/bin"; for c in bash env grep sed awk head cut tr uname; do ln -s "$(command -v $c)" "$T/bin/$c"; done
out=$(PATH="$T/bin" "$ROOT/Vendor/check-tools.sh" 2>&1 || true)
for tool in cmake meson ninja autoconf automake glibtoolize pkg-config cargo rustc; do
  grep -q "missing: $tool" <<<"$out" || fail "no message for $tool"
done
grep -q "brew install" <<<"$out" || fail "no install hint"
assert_fails env PATH="$T/bin" "$ROOT/Vendor/check-tools.sh"
"$ROOT/Vendor/check-tools.sh" >/dev/null   # the dev Mac has every tool after index §2
echo "PASS test-check-tools"
```

### A2.2 Run, expect failure

`make vendor-test` → `Vendor/check-tools.sh: No such file or directory`.

### A2.3 Implement

Required: `cmake ≥ 3.25`, `meson ≥ 1.3`, `ninja`, `autoconf`, `automake`, `glibtoolize` (GNU libtool; macOS
`/usr/bin/libtool` is Apple's archiver), `pkg-config` (pkgconf), `cargo` and `rustc` equal to the version recorded in
`Vendor/rust-toolchain.txt` (`1.96.0`, D-M4-7), `xcrun clang` from `DEVELOPER_DIR`. Not required on arm64:
`nasm`/`yasm` (x264, libvpx, dav1d and SVT-AV1 use clang's integrated AArch64 assembler; the prototype built with
`nasm` installed but never invoked it — check `logs/*.log` contain no `nasm` call). Message format: `missing: cmake
(brew install cmake)`; final line `Install the missing tools with: brew install <list>`.

### A2.4 Verify green / A2.5 Commit

`make vendor-test` → `PASS test-check-tools`. Commit `chore(vendor): check build tools before building`.

---

## Task A3 — `Vendor/build-media.sh`: FFmpeg 9.0.2 GPLv3 with codecs folded into shared libav* (P0-36)

| Field | Value |
|---|---|
| Goal | Static codec libraries into `Vendor/prefix`, then FFmpeg as shared `libav*` (install name `@rpath/…`) plus `ffmpeg` and `ffprobe` executables with `LC_RPATH @executable_path/../Frameworks`, arm64, minos 26.0, no build paths in any binary |
| 05 rows | P0-36, P1-50 (input), G-1 |
| Sources | 11a §6.3 (recipe), 05 P0-36 (demuxers to disable), D-M4-1…D-M4-4 |
| Verified | Prototype run 2026-10-21 (index §3): clean build 181 s, all 104 media pairs and 15 smoke cases green |

**Files:** create `Vendor/build-media.sh`, `Vendor/encoders.txt` (the encoder allow-list, D-M4-2),
`Vendor/tests/test-build-media-args.sh`; modify `Makefile` (`vendor-media`).

### A3.1 Failing test first

The build itself is too slow for `make vendor-test`; the test checks the script's decisions with `--print-config`,
which prints the FFmpeg configure line and exits without building.

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cfg=$("$ROOT/Vendor/build-media.sh" --print-config)
for flag in --enable-gpl --enable-version3 --enable-shared --disable-static "--install-name-dir=@rpath" \
  --disable-network --disable-autodetect --enable-videotoolbox --enable-audiotoolbox --enable-libx264 \
  --enable-libvpx --enable-libsvtav1 --enable-libdav1d --enable-libopus --enable-libvorbis --enable-libmp3lame \
  --enable-libwebp --enable-libzimg --disable-devices --enable-indev=lavfi --disable-ffplay \
  "--disable-demuxer=hls,dash,webm_dash_manifest,sdp,rtsp,rtp" --disable-encoders --extra-libs=-liconv; do
  grep -qF -- "$flag" <<<"$cfg" || fail "configure line lacks $flag"
done
grep -qF -- "--enable-nonfree" <<<"$cfg" && fail "nonfree must never be enabled"
grep -qF -- "-ffile-prefix-map=" <<<"$cfg" || fail "no path map"
grep -qF -- "-mmacosx-version-min=26.0" <<<"$cfg" || fail "no deployment target"
# Every encoder name the planners emit (FFmpegRequirements) must be in the allow-list, by configure name.
for e in libx264 libvpx_vp9 libsvtav1 libopus libvorbis libmp3lame libwebp libwebp_anim h264_videotoolbox \
  hevc_videotoolbox aac_at alac flac wmav2 wmv2 mpeg4 gif png mjpeg movtext webvtt srt subrip ass ssa \
  pcm_s16le pcm_s16be pcm_s24le pcm_s24be pcm_s32le pcm_s32be pcm_f32le; do
  grep -qx "$e" "$ROOT/Vendor/encoders.txt" || fail "encoders.txt lacks $e"
done
grep -qx "opus" "$ROOT/Vendor/encoders.txt" && fail "native opus encoder must stay off (03b §5.4)"
grep -qx "vorbis" "$ROOT/Vendor/encoders.txt" && fail "native vorbis encoder must stay off"
echo "PASS test-build-media-args"
```

### A3.2 Run, expect failure

`make vendor-test` → `Vendor/build-media.sh: No such file or directory`.

### A3.3 Implement

The script below is the prototype that ran, with three changes: paths are repository-relative, the encoder line uses
`Vendor/encoders.txt`, and hostile demuxers are disabled (P0-36). In the prototype the encoder allow-list build lacked
`mov_text` because FFmpeg's configure name is `movtext` (one smoke case became a known issue) — `encoders.txt` uses
configure names and A4's `verify-media.sh` checks the runtime names.

```bash
#!/usr/bin/env bash
# Builds static codec libraries, then FFmpeg as shared libav* with them folded in (11a §6.3, D-M4-1…4).
# Usage: Vendor/build-media.sh [--print-config] [component...]   (default: all, in dependency order)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ZIVLET_VENDOR_WORK:-$ROOT/Vendor}
SRC=$WORK/src; BLD=$WORK/build; PREFIX=$WORK/prefix; OUT=$WORK/out/media; LOGS=$WORK/logs
MACOS_MIN=26.0; ARCH=arm64; JOBS=$(sysctl -n hw.ncpu)
SDK=$(xcrun --sdk macosx --show-sdk-path)
export MACOSX_DEPLOYMENT_TARGET=$MACOS_MIN SDKROOT=$SDK           # SDKROOT: FFmpeg's host-cc checks (D-M4-4)
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct)}
export ZERO_AR_DATE=1                                              # reproducible .a members (index §3.4)
CC=$(xcrun -f clang); CXX=$(xcrun -f clang++); export CC CXX
BASE="-arch $ARCH -mmacosx-version-min=$MACOS_MIN -isysroot $SDK"
export CFLAGS="$BASE -O2 -fPIC -ffile-prefix-map=$WORK=/zivlet-media"
export CXXFLAGS="$CFLAGS" LDFLAGS="$BASE"
export PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig PKG_CONFIG_PATH=   # never see Homebrew .pc files
export LIBTOOLIZE=glibtoolize
CMAKE_COMMON=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="$PREFIX"
  -DCMAKE_OSX_ARCHITECTURES=$ARCH -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_MIN -DCMAKE_POSITION_INDEPENDENT_CODE=ON)
# --build = --host: a native build, so autoconf runs its test programs (lame's STDC check, D-M4-4).
AUTO_COMMON=(--prefix="$PREFIX" --enable-static --disable-shared --build=aarch64-apple-darwin
  --host=aarch64-apple-darwin)
ENCODERS=$(grep -v '^#' "$ROOT/Vendor/encoders.txt" | paste -sd, -)

# Configure strings are compiled in (ffmpeg -buildconf, vpx_codec_build_config): replace build paths (D-M4-3).
scrub() { sed -i '' -e "s|$WORK|/zivlet-media|g" -e "s|$SDK|/SDK|g" -e "s|$(dirname "$CC")|/toolchain|g" "$1"; }
src() { ls -d "$SRC/$1"-* | head -1; }

b_x264() {
  local s; s=$(src x264); mkdir -p "$BLD/x264"; cd "$BLD/x264"
  "$s/configure" --prefix="$PREFIX" --host=aarch64-apple-darwin --enable-static --enable-pic --disable-cli \
    --disable-opencl --disable-lavf --disable-swscale --disable-ffms --disable-gpac --disable-lsmash \
    --extra-cflags="$CFLAGS" --extra-ldflags="$LDFLAGS"
  make -j"$JOBS" && make install
}
b_libvpx() {
  local s; s=$(src libvpx); mkdir -p "$BLD/vpx"; cd "$BLD/vpx"
  "$s/configure" --prefix="$PREFIX" --target=arm64-darwin25-gcc --enable-static --disable-shared --enable-pic \
    --enable-vp9-highbitdepth --disable-examples --disable-tools --disable-docs --disable-unit-tests \
    --extra-cflags="$CFLAGS"
  scrub vpx_config.c
  make -j"$JOBS" && make install
}
b_svtav1() {
  cmake -S "$(src svtav1)" -B "$BLD/svtav1" "${CMAKE_COMMON[@]}" -DBUILD_APPS=OFF -DBUILD_TESTING=OFF
  cmake --build "$BLD/svtav1" && cmake --install "$BLD/svtav1"
}
b_dav1d() {
  meson setup "$BLD/dav1d" "$(src dav1d)" --prefix="$PREFIX" --libdir=lib --buildtype=release \
    --default-library=static -Denable_tools=false -Denable_tests=false
  ninja -C "$BLD/dav1d" install
}
b_opus() {
  cmake -S "$(src opus)" -B "$BLD/opus" "${CMAKE_COMMON[@]}" -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF
  cmake --build "$BLD/opus" && cmake --install "$BLD/opus"
}
b_libogg() { cd "$(src libogg)" && ./configure "${AUTO_COMMON[@]}" && make -j"$JOBS" install; }
b_libvorbis() {   # 1.3.7 passes -force_cpusubtype_ALL, which clang rejects on arm64
  cd "$(src libvorbis)" && sed -i '' 's/-force_cpusubtype_ALL//g' configure
  ./configure "${AUTO_COMMON[@]}" --with-ogg="$PREFIX" && make -j"$JOBS" install
}
b_lame() {        # export list names the removed lame_init_old; STDC check fails under modern clang (D-M4-4)
  cd "$(src lame)" && sed -i '' '/lame_init_old/d' include/libmp3lame.sym
  ./configure "${AUTO_COMMON[@]}" --disable-frontend --disable-decoder --disable-gtktest ac_cv_header_stdc=yes
  make -j"$JOBS" install
}
b_libwebp() {
  cmake -S "$(src libwebp)" -B "$BLD/webp" "${CMAKE_COMMON[@]}" -DWEBP_BUILD_ANIM_UTILS=OFF \
    -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF \
    -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF \
    -DWEBP_BUILD_LIBWEBPMUX=ON
  cmake --build "$BLD/webp" && cmake --install "$BLD/webp"
}
b_zimg() { cd "$(src zimg)" && ./autogen.sh && ./configure "${AUTO_COMMON[@]}" && make -j"$JOBS" install; }

ffmpeg_args() {
  FFARGS=(--prefix="$OUT" --arch=aarch64 --target-os=darwin --cc="$CC" --cxx="$CXX"
    --enable-gpl --enable-version3 --enable-shared --disable-static --install-name-dir=@rpath
    --pkg-config-flags=--static --extra-libs=-liconv
    "--extra-cflags=$CFLAGS -I$PREFIX/include" "--extra-ldflags=$LDFLAGS -L$PREFIX/lib -Wl,-dead_strip"
    "--extra-ldexeflags=-Wl,-rpath,@executable_path/../Frameworks"
    --disable-autodetect --enable-videotoolbox --enable-audiotoolbox --enable-zlib --enable-bzlib --enable-iconv
    --enable-libx264 --enable-libvpx --enable-libsvtav1 --enable-libdav1d --enable-libopus --enable-libvorbis
    --enable-libmp3lame --enable-libwebp --enable-libzimg
    --disable-encoders --enable-encoder="$ENCODERS"
    --disable-demuxer=hls,dash,webm_dash_manifest,sdp,rtsp,rtp
    --disable-network --disable-devices --enable-indev=lavfi --disable-ffplay --disable-doc --disable-debug
    --enable-ffmpeg --enable-ffprobe)
}
b_ffmpeg() {
  local s; s=$(src ffmpeg); mkdir -p "$BLD/ffmpeg"; cd "$BLD/ffmpeg"
  ffmpeg_args; "$s/configure" "${FFARGS[@]}"
  scrub config.h
  make -j"$JOBS" && make install
}

run() {
  local name=$1 t0; t0=$(date +%s); mkdir -p "$LOGS"
  if (set -x; "b_$name") >"$LOGS/$name.log" 2>&1; then echo "$name ok $(( $(date +%s) - t0 ))s"
  else echo "$name FAILED after $(( $(date +%s) - t0 ))s (log: Vendor/logs/$name.log)" >&2; return 1; fi
}

[[ "${1:-}" == "--print-config" ]] && { ffmpeg_args; printf '%s\n' "${FFARGS[@]}"; exit 0; }
"$ROOT/Vendor/check-tools.sh"
ALL=(x264 libvpx svtav1 dav1d opus libogg libvorbis lame libwebp zimg ffmpeg)
for c in "${@:-${ALL[@]}}"; do run "$c"; done
```

Notes for the implementer:
- The prototype passed the same flags inline (no `FFARGS` array, no encoder allow-list, no demuxer list); the array
  exists so `--print-config` and the real configure cannot drift apart.
- `Vendor/encoders.txt`: one configure encoder name per line (`libx264`, `libvpx_vp8`, `libvpx_vp9`, `libsvtav1`,
  `libopus`, `libvorbis`, `libmp3lame`, `libwebp`, `libwebp_anim`, `h264_videotoolbox`, `hevc_videotoolbox`,
  `prores_videotoolbox`, `aac_at`, `alac_at`, `aac`, `alac`, `flac`, `wmav2`, `wmv2`, `mpeg4`, `gif`, `png`, `apng`,
  `mjpeg`, `movtext`, `webvtt`, `srt`, `subrip`, `ass`, `ssa`, the `pcm_*` set the planners use plus `pcm_u8`/`pcm_s8`,
  `wrapped_avframe`, `rawvideo`). The prototype with this list (minus `movtext`) measured 29.0 MiB installed.

Makefile: `vendor-media: ; Vendor/build-media.sh` (depends on `vendor-fetch` having run; it does not fetch).

### A3.4 Verify green

1. `make vendor-test` → `PASS test-build-media-args`.
2. `make vendor-fetch vendor-media` → eleven `ok` lines; prototype timings on the M2 Pro (10 cores): x264 8 s, libvpx
   15 s, SVT-AV1 25 s, dav1d 4 s, opus 4 s, libogg 8 s, libvorbis 8 s, lame 13 s, libwebp 4 s, zimg 16 s, FFmpeg 76 s;
   **total 181 s**, work tree 451 MB (src 282 MB, build 119 MB).
3. `Vendor/out/media/bin/ffmpeg -hide_banner -version | head -1` → `ffmpeg version 9.0.2`.

### A3.5 Commit

`chore(vendor): build FFmpeg 9.0.2 GPLv3 with codecs folded into shared libav*`.

---

## Task A4 — `Vendor/verify-media.sh` and `Vendor/stage-media.sh` (P0-36 gate, 11a §6.4)

| Field | Value |
|---|---|
| Goal | `stage-media.sh` copies the real files (major-versioned names, no symlinks) into `Vendor/out/media-stage/{Helpers,Frameworks}`, writes dSYMs to `Vendor/out/media-dsym/`, strips with `strip -x`. `verify-media.sh <stage>` fails on: `nonfree` in `-buildconf`; licence not GPL v3; a dependency outside `@rpath/`, `/usr/lib/`, `/System/Library/`; a non-arm64 slice; minos ≠ 26.0; any of `/Users/`, `/private/tmp/`, `/var/folders/`, `/opt/homebrew` in `strings`; a missing runtime encoder or filter; hostile demuxers present; installed size > 30 MiB |
| 05 rows | P0-36 acceptance, P1-51 (licence check part), P1-52 (size input) |
| Sources | 11a §6.4, 05 P0-36 ("stripped size ≤ 30 MB") |

**Files:** create `Vendor/stage-media.sh`, `Vendor/verify-media.sh`, `Vendor/tests/test-verify-media.sh`.

### A4.1 Failing test first

The test builds a fake stage from system binaries so it runs in a second: a copy of `/usr/bin/true` named `ffmpeg`
must fail (no GPL licence output), and a shell-script `ffmpeg` that prints a `-buildconf` containing
`--enable-nonfree` must fail with `nonfree`.

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/s/Helpers" "$T/s/Frameworks"
cp /usr/bin/true "$T/s/Helpers/ffmpeg"; cp /usr/bin/true "$T/s/Helpers/ffprobe"
assert_fails "$ROOT/Vendor/verify-media.sh" "$T/s"
printf '#!/bin/sh\necho "  configuration: --enable-nonfree"\n' > "$T/s/Helpers/ffmpeg"; chmod +x "$T/s/Helpers/ffmpeg"
out=$("$ROOT/Vendor/verify-media.sh" "$T/s" 2>&1 || true)
grep -q "nonfree" <<<"$out" || fail "nonfree not reported"
if [[ -x "$ROOT/Vendor/out/media-stage/Helpers/ffmpeg" ]]; then   # after A3 on this machine
  "$ROOT/Vendor/verify-media.sh" "$ROOT/Vendor/out/media-stage"
fi
echo "PASS test-verify-media"
```

### A4.2 Run, expect failure

`make vendor-test` → `Vendor/verify-media.sh: No such file or directory`.

### A4.3 Implement

`verify-media.sh` follows 11a §6.4 with these runtime names: encoders `h264_videotoolbox hevc_videotoolbox
prores_videotoolbox libx264 libvpx libvpx-vp9 libsvtav1 libopus libvorbis libmp3lame aac_at alac_at flac wmav2 wmv2
mpeg4 gif libwebp libwebp_anim png mov_text`; filters `zscale tonemap palettegen paletteuse scale format`; demuxers
`hls dash webm_dash_manifest sdp rtsp rtp` must be **absent** (`ffmpeg -demuxers`); `ffmpeg -devices` lists only
`lavfi`; `ffmpeg -protocols` output side has no `http`, `tcp`, `udp`, `rtmp`. Size: `du -sk` of the stage ≤ 30,720.
`stage-media.sh` copies `ffmpeg`, `ffprobe`, and `libavcodec.63`, `libavformat.63`, `libavfilter.12`, `libavutil.61`,
`libswscale.10`, `libswresample.7`, `libavdevice.63` (`cp -L`), runs `dsymutil` then `strip -x` on each.

### A4.4 Verify green

`Vendor/stage-media.sh && Vendor/verify-media.sh Vendor/out/media-stage` → `media stage OK: 29.x MiB, 0 path leaks,
22 encoders, GPL v3`. Prototype values: full encoder set 30.07 MiB (over the line by 0.07 MiB), allow-list 29.0 MiB,
zip 14.1 MB, ULMO DMG of the stage 10.0 MB.

### A4.5 Commit

`chore(vendor): stage and verify the media helpers (licence, deps, paths, encoders, size)`.

---

## Task A5 — `Vendor/build-native.sh`: libwebp 1.6.0 → `CWebP.xcframework` (P1-25 vendor half)

| Field | Value |
|---|---|
| Goal | Merge `libwebp.a`, `libwebpmux.a`, `libwebpdemux.a`, `libsharpyuv.a` (from A3's prefix, same flags) into `libCWebP.a`; headers + `module.modulemap` (`module CWebP { header "webp/encode.h" … link "CWebP" }`); `xcodebuild -create-xcframework` → `Vendor/out/CWebP.xcframework`; write its SHA-256 to `Vendor/out/CWebP.sha256` |
| 05 rows | P1-25 |
| Verified | Prototype: xcframework 836 KB on disk, 2 s to package; a Swift executable using `.binaryTarget(path:)` encoded a still (with alpha, sharp YUV), added an ICCP chunk through `WebPMux`, and encoded a 5-frame `WebPAnimEncoder` animation; ImageIO read all three back (`org.webmproject.webp`, 1/1/5 frames, 320 × 200, alpha). Linked size of the stripped test executable 0.50 MB |

**Files:** create `Vendor/build-native.sh`, `Vendor/tests/test-build-native.sh`.

### A5.1 Failing test first

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
X=$ROOT/Vendor/out/CWebP.xcframework
[[ -d "$X" ]] || { "$ROOT/Vendor/build-native.sh" libwebp; }
assert_file "$X/Info.plist"
lib=$(find "$X" -name 'libCWebP.a' | head -1); assert_file "$lib"
nm -gU "$lib" | grep -q "_WebPAnimEncoderNew" || fail "anim encoder missing"
nm -gU "$lib" | grep -q "_WebPMuxSetChunk" || fail "mux missing"
nm -gU "$lib" | grep -q "_SharpYuvConvert" || fail "sharpyuv missing"
strings "$lib" | grep -E '/Users/|/private/tmp/' && fail "path leak"
grep -q 'module CWebP' "$(find "$X" -name module.modulemap | head -1)" || fail "no module map"
echo "PASS test-build-native"
```

### A5.2–A5.5

RED: script missing. GREEN: `make vendor-test` → `PASS test-build-native`. Commit `chore(vendor): libwebp 1.6.0 as
CWebP.xcframework`.

---

## Task A6 — `Vendor/rs/zivlet-svg` + `Vendor/build-rs.sh` → `CZivletSVG.xcframework` (SVG pull-forward, D-M4-6/7)

| Field | Value |
|---|---|
| Goal | Our own Rust crate (GPL-3.0-or-later) exposing a C ABI over resvg 0.47.0: `zivlet_svg_render(bytes, len, scale, max_edge, out)` → premultiplied RGBA8 + size, `zivlet_svg_free`. Only `data:` image hrefs resolve; `resources_dir = None`; system fonts loaded once per process. Static library, `panic = "abort"` (changed to unwind with the panic caught at the C boundary, D-M4-18), LTO, `--remap-path-prefix` for `$CARGO_HOME` and the crate dir |
| 05 rows | P2-10 subset (resvg only; krilla-svg, oxipng, imagequant stay in P2-10) pulled into M4 by the M4 brief |
| Verified | Prototype on 2026-10-21: clean compile 18 s (crates cached; first fetch + compile 32 s while FFmpeg built in parallel), `libzivlet_svg.a` 4.4 MB, linked into a C test and stripped: +2.15 MB. Gradient + Helvetica text rendered (240 × 160 at 2×); a 100,000 × 100,000 SVG capped to 8192 × 8192; non-SVG input → error 1; a `file` href was not drawn, a `data:` PNG was. `strings` found no `/Users/`, `/private/tmp` or `cargo-home` |

**Files:** create `Vendor/rs/zivlet-svg/Cargo.toml`, `Cargo.lock` (committed), `src/lib.rs`, `include/zivlet_svg.h`,
`Vendor/rust-toolchain.txt` (`1.96.0`), `Vendor/build-rs.sh`, `Vendor/tests/test-build-rs.sh`,
`Vendor/rs/zivlet-svg/tests/render.rs`.

### A6.1 Failing tests first

`Vendor/rs/zivlet-svg/tests/render.rs` (run by `cargo test` inside `build-rs.sh --test`):

```rust
use zivlet_svg::{zivlet_svg_free, zivlet_svg_render, ZivletSvgImage, ZIVLET_SVG_OK, ZIVLET_SVG_PARSE};

fn render(svg: &str, scale: f32, max_edge: u32) -> (i32, ZivletSvgImage) {
    let mut img = ZivletSvgImage { width: 0, height: 0, rgba: std::ptr::null_mut() };
    let rc = unsafe { zivlet_svg_render(svg.as_ptr(), svg.len(), scale, max_edge, &mut img) };
    (rc, img)
}
fn pixel(img: &ZivletSvgImage, x: u32, y: u32) -> [u8; 4] {
    let i = ((y * img.width + x) * 4) as usize;
    unsafe { [*img.rgba.add(i), *img.rgba.add(i + 1), *img.rgba.add(i + 2), *img.rgba.add(i + 3)] }
}

#[test]
fn renders_at_twice_the_intrinsic_size() {
    let (rc, mut img) = render(r##"<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80"><rect width="120" height="80" fill="#00f"/></svg>"##, 2.0, 8192);
    assert_eq!(rc, ZIVLET_SVG_OK);
    assert_eq!((img.width, img.height), (240, 160));
    assert_eq!(pixel(&img, 120, 80), [0, 0, 255, 255]);
    unsafe { zivlet_svg_free(&mut img) };
    assert!(img.rgba.is_null());
}

#[test]
fn caps_the_longest_edge() {
    let (rc, mut img) = render(r#"<svg xmlns="http://www.w3.org/2000/svg" width="100000" height="50000"/>"#, 2.0, 8192);
    assert_eq!(rc, ZIVLET_SVG_OK);
    assert_eq!((img.width, img.height), (8192, 4096));
    unsafe { zivlet_svg_free(&mut img) };
}

#[test]
fn refuses_non_svg_and_bad_arguments() {
    assert_eq!(render("not svg", 2.0, 8192).0, ZIVLET_SVG_PARSE);
    assert_ne!(render("<svg/>", 0.0, 8192).0, ZIVLET_SVG_OK);
    assert_ne!(render("<svg/>", 2.0, 0).0, ZIVLET_SVG_OK);
}

#[test]
fn loads_only_data_hrefs() {
    let dir = std::env::temp_dir().join(format!("zsvg-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let red_png = dir.join("red.png");
    std::fs::write(&red_png, include_bytes!("red-20.png")).unwrap();     // 20 × 20 red PNG fixture
    let b64 = include_str!("red-20.png.b64");
    let svg = format!(r##"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="40" height="20" fill="#fff"/><image href="{}" width="20" height="20"/><image href="data:image/png;base64,{}" x="20" width="20" height="20"/></svg>"##, red_png.display(), b64.trim());
    let (rc, mut img) = render(&svg, 1.0, 8192);
    assert_eq!(rc, ZIVLET_SVG_OK);
    assert_eq!(pixel(&img, 10, 10)[..3], [255, 255, 255]); // file href ignored
    assert!(pixel(&img, 30, 10)[0] > 240 && pixel(&img, 30, 10)[1] < 16); // data href drawn
    unsafe { zivlet_svg_free(&mut img) };
}
```

`Vendor/tests/test-build-rs.sh`: builds, then asserts the xcframework exists, `nm -gU` lists `_zivlet_svg_render` and
`_zivlet_svg_free`, `otool -l` on the objects shows `minos 26.0`, and `strings` has no `/Users/`, `/private/tmp`,
`cargo-home`.

### A6.2 Run, expect failure

`make vendor-test` → `Vendor/build-rs.sh: No such file or directory`.

### A6.3 Implement

`Cargo.toml` (as prototyped):

```toml
[package]
name = "zivlet_svg"
version = "0.1.0"
edition = "2021"
license = "GPL-3.0-or-later"
publish = false

[lib]
crate-type = ["staticlib", "rlib"]

[dependencies]
resvg = { version = "=0.47.0", default-features = false, features = ["text", "system-fonts", "memmap-fonts", "raster-images"] }

[profile.release]
opt-level = 3
lto = "fat"
codegen-units = 1
panic = "abort"
strip = "debuginfo"
```

`src/lib.rs`: the prototype file (index §3.3) — `OnceLock<Arc<fontdb::Database>>` loaded with system fonts,
`Options { resources_dir: None, fontdb, image_href_resolver: { resolve_data: default_data_resolver(), resolve_string:
Box::new(|_, _| None) } }`, scale clamp to `max_edge / max(w, h)`, `Pixmap::new` failure → `ZIVLET_SVG_ALLOC`,
ownership handed out with `Box<[u8]>` and reclaimed in `zivlet_svg_free`. Also reject inputs over 64 MiB
(`ZIVLET_SVG_SIZE`, 03b §6.4 limit) before parsing.

`build-rs.sh`: checks `rustc --version` equals `Vendor/rust-toolchain.txt`; `CARGO_HOME=Vendor/downloads/cargo-home`
(crate downloads stay under `Vendor/downloads`, checksummed by `Cargo.lock`); `MACOSX_DEPLOYMENT_TARGET=26.0`;
`RUSTFLAGS="--remap-path-prefix=$CARGO_HOME=/cargo --remap-path-prefix=$CRATE=/zivlet-svg -C target-cpu=apple-m1"`;
`cargo build --locked --release --target aarch64-apple-darwin`; `--test` runs `cargo test --locked`; packages
`libzivlet_svg.a` + `include/zivlet_svg.h` + modulemap `module CZivletSVG` into `Vendor/out/CZivletSVG.xcframework`.

### A6.4 Verify green / A6.5 Commit

`make vendor-test` → `PASS test-build-rs` (cargo: 4 tests passed). Commit `feat(vendor): zivlet-svg, a resvg 0.47
static library with a data:-only resolver`.

---

## Task A7 — `make vendor` and the vendor artifact cache (P0-37 local half)

| Field | Value |
|---|---|
| Goal | `make vendor` = check-tools → fetch → media → stage → verify → native → rs, idempotent (skips a component whose output hash file matches the lock + script hash). Cache key = `sha256(versions.lock + build-*.sh + encoders.txt + rust-toolchain.txt + Cargo.lock + xcodebuild -version)`, written to `Vendor/out/KEY`; `Vendor/pack.sh` writes `Vendor/out/zivlet-vendor-<key>.tar.xz` (stage + xcframeworks + dSYMs) and `Vendor/unpack.sh <tarball>` restores it, so app builds never compile FFmpeg |
| 05 rows | P0-37 (local part; the hosted `vendor.yml` job is F1) |
| Sources | 11a §6.6 |

**Files:** create `Vendor/pack.sh`, `Vendor/unpack.sh`, `Vendor/cache-key.sh`, `Vendor/tests/test-cache-key.sh`;
modify `Makefile` (`vendor`, `vendor-pack`, `vendor-unpack`).

### A7.1 Failing test first

`test-cache-key.sh`: the key is 64 hex chars; it changes when any input file changes (copy the inputs to a temp tree,
touch one byte in `encoders.txt`, compare); it does not change when an unrelated file changes; `unpack.sh` refuses a
tarball whose embedded `KEY` differs from the current key unless `--force`.

### A7.2–A7.5

RED: scripts missing. GREEN: `make vendor-test`; `make vendor` twice → the second run prints `up to date` for every
component in under 5 s. Commit `chore(vendor): cache key, pack and unpack for vendor outputs`.

---

## Task A8 — Reproducibility check (P0-37 acceptance, index §3.4)

| Field | Value |
|---|---|
| Goal | `Vendor/repro-check.sh` builds the media stage twice in two clean work directories (`ZIVLET_VENDOR_WORK`) and compares SHA-256 of every stripped Mach-O; prints a table; exits 1 on a difference unless the file is in `Vendor/repro-known.txt` with a reason |
| Prototype finding | Two clean builds in different directories: `ffmpeg`, `ffprobe`, `libavformat`, `libavutil` identical; **`libavcodec` differed** (after `strip -x`: 49 bytes, the `LC_UUID` and the linker's ad-hoc signature plus a few code bytes). The prototype did not set `ZERO_AR_DATE`, so static archive members carried timestamps (every `.a` differed). A3 now exports `ZERO_AR_DATE=1`; A8 proves whether that suffices |

**Files:** create `Vendor/repro-check.sh`, `Vendor/repro-known.txt` (empty, header comment only).

Steps: write the script; run it (≈ 6 min, 2 × 181 s); if `libavcodec` still differs, bisect by comparing the static
libraries first (`shasum Vendor/prefix/lib/*.a` across both trees), fix the source of the difference, or record it in
`repro-known.txt` with the evidence. No unit test: the script is the test. Commit `chore(vendor): reproducibility
check for the media stage`.
