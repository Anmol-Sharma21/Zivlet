# 11a. Media engine: reproducible build (§6)

Part of [11-media-engine](11-media-engine.md), split out to keep each file under 800 lines. Section numbers are unchanged, so a reference such as "11 §6" points to the matching section below. Bare section references to sections not in this file point to the parent document, whose header defines the evidence tags, `[challenge]` notes and **[OWNER]** markers used here.

---

## 6. Reproducible build (arm64, macOS 26 minimum)

### 6.1 Layout

```
scripts/media/
  media-versions.lock      # name, version/commit, URL, sha256 (one per line)
  build-media.sh           # builds deps (static .a) then FFmpeg (shared libav*, static codecs)
  verify-media.sh          # license, deps, encoder list, smoke encodes
  patches/                 # lame-3.100-sym.patch, vorbis-1.3.7-cpusubtype.patch, ...
.build/media/{src,build,prefix,out}   # gitignored
```

Build-only tools come from Homebrew: `pkgconf cmake meson ninja autoconf automake libtool`. **Nothing from Homebrew is linked.** `PKG_CONFIG_LIBDIR` points only at our prefix, so stray `/opt/homebrew/lib/pkgconfig/*.pc` files are invisible. arm64 needs no nasm: x264, libvpx and dav1d use clang's integrated assembler for AArch64.

### 6.2 `media-versions.lock` (example; fill sha256 when first fetched)

```
ffmpeg     9.0.2    https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz                          sha256:<...>
x264       b35605ace3ddf7c1a5d67a2eb553f034aef41d55  https://code.videolan.org/videolan/x264/-/archive/<commit>/x264-<commit>.tar.bz2  sha256:<...>
libvpx     1.17.0   https://github.com/webmproject/libvpx/archive/refs/tags/v1.17.0.tar.gz  sha256:<...>
svtav1     4.2.0    https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v4.2.0/SVT-AV1-v4.2.0.tar.bz2  sha256:<...>
dav1d      1.5.4    https://code.videolan.org/videolan/dav1d/-/archive/1.5.4/dav1d-1.5.4.tar.bz2  sha256:<...>
opus       1.6.1    https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz             sha256:<...>
libogg     1.3.6    https://downloads.xiph.org/releases/ogg/libogg-1.3.6.tar.xz            sha256:<...>
libvorbis  1.3.7    https://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.xz      sha256:<...>
lame       3.100    https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz  sha256:<...>
libwebp    1.6.0    https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz  sha256:<...>
zimg       3.0.6    https://github.com/sekrit-twc/zimg/archive/refs/tags/release-3.0.6.tar.gz  sha256:<...>
```

### 6.3 `build-media.sh` (essential parts)

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=${WORK:-$ROOT/.build/media}; SRC=$WORK/src; BLD=$WORK/build; PREFIX=$WORK/prefix; OUT=$WORK/out
MACOS_MIN=26.0; ARCH=arm64; JOBS=$(sysctl -n hw.ncpu)
SDK=$(xcrun --sdk macosx --show-sdk-path)
export MACOSX_DEPLOYMENT_TARGET=$MACOS_MIN
export SOURCE_DATE_EPOCH=$(git -C "$ROOT" log -1 --format=%ct)   # reproducible timestamps
export CC=$(xcrun -f clang) CXX=$(xcrun -f clang++)
BASE="-arch $ARCH -mmacosx-version-min=$MACOS_MIN -isysroot $SDK"
export CFLAGS="$BASE -O2 -fPIC -ffile-prefix-map=$WORK=/zivlet-media"   # no path leakage
export CXXFLAGS="$CFLAGS" LDFLAGS="$BASE"
export PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig PKG_CONFIG_PATH=           # never see Homebrew .pc
CMAKE_COMMON=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
  -DCMAKE_INSTALL_PREFIX=$PREFIX -DCMAKE_OSX_ARCHITECTURES=$ARCH
  -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_MIN -DCMAKE_POSITION_INDEPENDENT_CODE=ON)
AUTO_COMMON=(--prefix=$PREFIX --enable-static --disable-shared --host=aarch64-apple-darwin)

fetch_and_verify   # reads media-versions.lock, curl -L, shasum -a 256 -c, extract to $SRC

# --- x264 (8+10-bit in one lib, no CLI) ---
(cd $SRC/x264 && ./configure --prefix=$PREFIX --host=aarch64-apple-darwin --enable-static \
   --enable-pic --disable-cli --disable-opencl --disable-lavf --disable-swscale \
   --disable-ffms --disable-gpac --disable-lsmash --extra-cflags="$CFLAGS" --extra-ldflags="$LDFLAGS" \
 && make -j$JOBS && make install)

# --- libvpx (VP8/VP9, high bit depth) ---
(mkdir -p $BLD/vpx && cd $BLD/vpx && $SRC/libvpx/configure --prefix=$PREFIX \
   --target=arm64-darwin25-gcc --enable-static --disable-shared --enable-pic \
   --enable-vp9-highbitdepth --disable-examples --disable-tools --disable-docs \
   --disable-unit-tests --extra-cflags="$CFLAGS" && make -j$JOBS && make install)

# --- SVT-AV1 (encoder lib only) ---
cmake -S $SRC/svtav1 -B $BLD/svtav1 "${CMAKE_COMMON[@]}" -DBUILD_APPS=OFF -DBUILD_TESTING=OFF
cmake --build $BLD/svtav1 && cmake --install $BLD/svtav1

# --- dav1d ---
meson setup $BLD/dav1d $SRC/dav1d --prefix=$PREFIX --buildtype=release --default-library=static \
  -Denable_tools=false -Denable_tests=false -Db_pie=true
ninja -C $BLD/dav1d install

# --- Opus ---
cmake -S $SRC/opus -B $BLD/opus "${CMAKE_COMMON[@]}" -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF
cmake --build $BLD/opus && cmake --install $BLD/opus

# --- Ogg + Vorbis (vorbis 1.3.7 configure passes -force_cpusubtype_ALL, which clang rejects on arm64) ---
(cd $SRC/libogg && ./configure "${AUTO_COMMON[@]}" && make -j$JOBS install)
(cd $SRC/libvorbis && sed -i '' 's/-force_cpusubtype_ALL//g' configure \
   && ./configure "${AUTO_COMMON[@]}" --with-ogg=$PREFIX && make -j$JOBS install)

# --- LAME 3.100 (known: export list references removed lame_init_old; old config.sub) ---
(cd $SRC/lame && sed -i '' '/lame_init_old/d' include/libmp3lame.sym \
   && ./configure "${AUTO_COMMON[@]}" --disable-frontend --disable-decoder --disable-gtktest \
   && make -j$JOBS install)

# --- libwebp (libs only, incl. mux/demux for libwebp_anim) ---
cmake -S $SRC/libwebp -B $BLD/webp "${CMAKE_COMMON[@]}" -DWEBP_BUILD_ANIM_UTILS=OFF \
  -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF \
  -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF
cmake --build $BLD/webp && cmake --install $BLD/webp

# --- zimg ---
(cd $SRC/zimg && ./autogen.sh && ./configure "${AUTO_COMMON[@]}" && make -j$JOBS install)

# --- FFmpeg: shared libav* with codecs folded in, ffmpeg + ffprobe ---
(mkdir -p $BLD/ffmpeg && cd $BLD/ffmpeg && $SRC/ffmpeg/configure \
  --prefix=$OUT --arch=aarch64 --target-os=darwin --cc="$CC" \
  --enable-gpl --enable-version3 \
  --enable-shared --disable-static --install-name-dir='@rpath' \
  --pkg-config-flags=--static \
  --extra-cflags="$CFLAGS -I$PREFIX/include" \
  --extra-ldflags="$LDFLAGS -L$PREFIX/lib -Wl,-dead_strip" \
  --extra-ldexeflags="-Wl,-rpath,@executable_path/../Frameworks" \
  --disable-autodetect \
  --enable-videotoolbox --enable-audiotoolbox --enable-zlib --enable-bzlib --enable-iconv \
  --enable-libx264 --enable-libvpx --enable-libsvtav1 --enable-libdav1d \
  --enable-libopus --enable-libvorbis --enable-libmp3lame --enable-libwebp --enable-libzimg \
  --disable-encoder=opus,vorbis \
  --disable-network --disable-devices --disable-ffplay --disable-doc --disable-debug \
  --enable-ffmpeg --enable-ffprobe \
 && make -j$JOBS && make install)

# strip (keep dSYMs for crash symbolication)
for f in $OUT/bin/ffmpeg $OUT/bin/ffprobe $OUT/lib/lib*.[0-9]*.dylib; do
  [ -L "$f" ] && continue; dsymutil "$f" -o "$WORK/dsym/$(basename $f).dSYM"; strip -x "$f"; done
"$ROOT/scripts/media/verify-media.sh" "$OUT"
```

Notes:
- `--disable-encoder=opus,vorbis` stops the experimental native encoders from ever being picked. The native **decoders** stay.
- All decoders, demuxers, parsers and filters stay enabled, so input is robust. Trimming components with `--disable-everything` would save only a few MB and makes "unsupported file" bugs likely.
- x264's `stable` branch builds 8- and 10-bit into one library (current default `--bit-depth=all`).
- Keep the dSYMs out of the app. Upload them with the release for crash symbolication.

### 6.4 `verify-media.sh` (CI gate)

```bash
B=$1/bin; L=$1/lib
DYLD_LIBRARY_PATH= "$B/ffmpeg" -hide_banner -buildconf | grep -q nonfree && { echo "nonfree!"; exit 1; }
"$B/ffmpeg" -hide_banner -L | grep -q "version 3" || exit 1
for x in $B/ffmpeg $B/ffprobe $L/lib*.dylib; do
  otool -L "$x" | tail -n +2 | grep -v -E '@rpath/|/usr/lib/|/System/Library/' && { echo "bad dep in $x"; exit 1; }
  lipo -archs "$x" | grep -qx arm64 || exit 1
  otool -l "$x" | grep -A3 LC_BUILD_VERSION | grep -q "minos 26.0" || exit 1
done
strings "$B/ffmpeg" $L/lib*.dylib | grep -E '/Users/|/private/tmp/' && { echo "path leak"; exit 1; }
need="h264_videotoolbox hevc_videotoolbox prores_videotoolbox libx264 libvpx libvpx-vp9 libsvtav1 \
      libopus libvorbis libmp3lame aac_at alac_at flac wmav2 wmv2 mpeg4 gif libwebp libwebp_anim png"
enc=$("$B/ffmpeg" -hide_banner -encoders)
for e in $need; do echo "$enc" | grep -qw "$e" || { echo "missing encoder $e"; exit 1; }; done
# smoke: every advertised pair against tests/fixtures/media (see §14)
```

### 6.5 Size budget (INFERRED from Homebrew arm64 dylibs measured locally)

| Part | Size |
|---|---|
| libavcodec (9.2 MB base) + x264 1.2 + vpx 1.7 + SVT 2.8 + dav1d 0.8 + opus 0.4 + LAME 0.3 + webp 0.6 + vorbis/ogg 0.3 | about 17 MB |
| libavformat 2.2 + libavfilter 2.8 + zimg 0.4 + libavutil 0.6 + libswscale 0.6 + libswresample 0.1 | about 6.7 MB |
| ffmpeg + ffprobe executables | about 0.6 MB |
| **Total (uncompressed, stripped)** | **about 25 MB** (SPIKE S-1 measures the real number) |
| + x265 / + libaom (optional) | +7 / +4 MB |

Two separate *static* executables (ffmpeg + ffprobe) would roughly double our size, which is why we use shared libav\*. The shared layout also keeps a future in-process libavformat (XPC) possible with the same artifacts.

### 6.6 CI

- GitHub Actions, macOS 26 arm64 runner image (or self-hosted Apple silicon). Job `media` runs only when `scripts/media/**` changes.
- Cache key = `sha256(media-versions.lock + build-media.sh + patches/* + xcode-version)`. Output artifacts:
  - `zivlet-media-<key>.tar.zst` (bin + lib + dSYMs)
  - `zivlet-media-src-<key>.tar.xz` (GPL source)
- The app build downloads the artifact by key, so no app build compiles ffmpeg.
- Reproducibility check: build twice in clean directories and diff `shasum` of the stripped outputs. Expect identical results with the same Xcode. Mach-O UUIDs are content-derived when `SOURCE_DATE_EPOCH` and the path map are fixed. Remaining differences go into a known-issues list.
- Security cadence: a Renovate-style job opens a PR when a new FFmpeg point release appears on the pinned branch (and for libvpx/libwebp CVEs).

