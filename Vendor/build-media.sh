#!/usr/bin/env bash
# Builds static codec libraries, then FFmpeg 9.0.2 as shared libav* with them folded in (11a §6.3, D-M4-1...4).
# Usage: Vendor/build-media.sh [--print-config] [component...]   (default: all, in dependency order)
# Sources come from Vendor/fetch.sh (verified tarballs); this script never downloads. ZIVLET_VENDOR_WORK moves the
# whole work tree (src, build, prefix, out, logs) elsewhere, as the reproducibility check does.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ZIVLET_VENDOR_WORK:-$ROOT/Vendor}
SRC=$WORK/src; BLD=$WORK/build; PREFIX=$WORK/prefix; OUT=$WORK/out/media; LOGS=$WORK/logs
MACOS_MIN=26.0; ARCH=arm64; JOBS=$(sysctl -n hw.ncpu)
ALL=(x264 libvpx svtav1 dav1d opus libogg libvorbis lame libwebp zimg ffmpeg)
SDK=$(xcrun --sdk macosx --show-sdk-path)
export MACOSX_DEPLOYMENT_TARGET=$MACOS_MIN SDKROOT=$SDK # SDKROOT: FFmpeg's host-cc checks (D-M4-4)
# A date that only moves when the pinned sources move, so rebuilding at a later commit gives the same bytes.
LOCK_EPOCH=$(git -C "$ROOT" log -1 --format=%ct -- Vendor/versions.lock 2>/dev/null || true)
export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-${LOCK_EPOCH:-1761004800}}
export ZERO_AR_DATE=1 # reproducible .a members (index §3.4)
CC=$(xcrun -f clang); CXX=$(xcrun -f clang++); export CC CXX
BASE="-arch $ARCH -mmacosx-version-min=$MACOS_MIN -isysroot $SDK"
export CFLAGS="$BASE -O2 -fPIC -ffile-prefix-map=$WORK=/zivlet-media"
export CXXFLAGS="$CFLAGS" LDFLAGS="$BASE"
export PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig PKG_CONFIG_PATH= # never see Homebrew .pc files
export LIBTOOLIZE=glibtoolize
CMAKE_COMMON=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_INSTALL_PREFIX="$PREFIX"
    -DCMAKE_OSX_ARCHITECTURES=$ARCH -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_MIN -DCMAKE_POSITION_INDEPENDENT_CODE=ON)
# --build = --host: a native build, so autoconf runs its test programs (lame's STDC check, D-M4-4).
AUTO_COMMON=(--prefix="$PREFIX" --enable-static --disable-shared --build=aarch64-apple-darwin
    --host=aarch64-apple-darwin)
ENCODERS=$(grep -v -e '^#' -e '^[[:space:]]*$' "$ROOT/Vendor/encoders.txt" | paste -sd, -)

# Configure strings are compiled in (ffmpeg -buildconf, vpx_codec_build_config): replace build paths (D-M4-3).
scrub() { sed -i '' -e "s|$WORK|/zivlet-media|g" -e "s|$SDK|/SDK|g" -e "s|$(dirname "$CC")|/toolchain|g" "$1"; }
src() {
    local dir; dir=$(ls -d "$SRC/$1"-* 2>/dev/null | head -1)
    [[ -n "$dir" ]] || { echo "error: no source for $1 in $SRC (run make vendor-fetch)" >&2; return 1; }
    echo "$dir"
}

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
    meson setup --reconfigure "$BLD/dav1d" "$(src dav1d)" --prefix="$PREFIX" --libdir=lib --buildtype=release \
        --default-library=static -Denable_tools=false -Denable_tests=false
    ninja -C "$BLD/dav1d" install
}
b_opus() {
    cmake -S "$(src opus)" -B "$BLD/opus" "${CMAKE_COMMON[@]}" -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF
    cmake --build "$BLD/opus" && cmake --install "$BLD/opus"
}
b_libogg() { cd "$(src libogg)" && ./configure "${AUTO_COMMON[@]}" && make -j"$JOBS" install; }
b_libvorbis() { # 1.3.7 passes -force_cpusubtype_ALL, which clang rejects on arm64
    cd "$(src libvorbis)" && sed -i '' 's/-force_cpusubtype_ALL//g' configure
    ./configure "${AUTO_COMMON[@]}" --with-ogg="$PREFIX" && make -j"$JOBS" install
}
b_lame() { # export list names the removed lame_init_old; STDC check fails under modern clang (D-M4-4)
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

# One array for --print-config and the real configure, so the test and the build cannot drift apart.
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
    if (set -x; "b_$name") >"$LOGS/$name.log" 2>&1; then
        echo "$name ok $(($(date +%s) - t0))s"
    else
        echo "$name FAILED after $(($(date +%s) - t0))s (log: $LOGS/$name.log)" >&2
        return 1
    fi
}

if [[ "${1:-}" == "--print-config" ]]; then ffmpeg_args; printf '%s\n' "${FFARGS[@]}"; exit 0; fi
for c in "$@"; do
    [[ " ${ALL[*]} " == *" $c "* ]] || { echo "error: unknown component $c (known: ${ALL[*]})" >&2; exit 2; }
done
"$ROOT/Vendor/check-tools.sh"
for c in "${@:-${ALL[@]}}"; do run "$c"; done
