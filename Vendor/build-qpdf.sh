#!/usr/bin/env bash
# Sourced by Vendor/build-native.sh (needs ROOT, WORK, OUT, STAGING and package_xcframework): builds CQPDF.
# libjpeg-turbo installs into its own prefix under build/native, so the media build's prefix never sees it.
# Nothing from Homebrew takes part: pkg-config sees only that prefix, CMake ignores /opt/homebrew and /usr/local,
# and zlib is the SDK's. Build paths are mapped away with -ffile-prefix-map; dates come from the pins' commit.
QPDF_SOURCES=(libjpeg-turbo qpdf)

qpdf_source() {
    local dir; dir=$(ls -d "$WORK/src/$1"-* 2>/dev/null | head -1)
    if [[ -z "$dir" ]]; then
        "$ROOT/Vendor/fetch.sh" --only "$1" --src "$WORK/src" >/dev/null
        dir=$(ls -d "$WORK/src/$1"-* | head -1)
    fi
    echo "$dir"
}

# Builds libjpeg-turbo into <prefix>, then libqpdf in <build>/qpdf; every step's output goes to <log>. Steps are
# chained with || return because set -e does not apply inside a function called from an || list.
build_qpdf_libraries() {
    local sdk=$1 bld=$2 prefix=$3 log=$4 jpeg qpdf flags
    jpeg=$(qpdf_source libjpeg-turbo) || return 1
    qpdf=$(qpdf_source qpdf) || return 1
    flags="-arch arm64 -mmacosx-version-min=26.0 -O2 -ffile-prefix-map=$WORK/src=/zivlet/src"
    flags+=" -ffile-prefix-map=$bld=/zivlet/build -ffile-prefix-map=$prefix=/zivlet/prefix"
    # The find settings below keep Homebrew's libraries out and also hide PATH from find_program, so Ninja (a build
    # tool, not linked in) is named outright.
    local ninja; ninja=$(command -v ninja) || { echo "error: ninja not found" >>"$log"; return 1; }
    local -a common=(-G Ninja "-DCMAKE_MAKE_PROGRAM=$ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64
        -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 "-DCMAKE_OSX_SYSROOT=$sdk" "-DCMAKE_C_COMPILER=$(xcrun -f clang)"
        "-DCMAKE_CXX_COMPILER=$(xcrun -f clang++)" "-DCMAKE_INSTALL_PREFIX=$prefix"
        "-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local" -DCMAKE_FIND_USE_SYSTEM_ENVIRONMENT_PATH=OFF
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON "-DCMAKE_C_FLAGS=$flags" "-DCMAKE_CXX_FLAGS=$flags")
    cmake -S "$jpeg" -B "$bld/jpeg" "${common[@]}" -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF \
        -DWITH_TOOLS=OFF -DWITH_TESTS=OFF -DCMAKE_INSTALL_LIBDIR=lib >>"$log" 2>&1 || return 1
    cmake --build "$bld/jpeg" >>"$log" 2>&1 || return 1
    cmake --install "$bld/jpeg" >>"$log" 2>&1 || return 1
    cmake -S "$qpdf" -B "$bld/qpdf" "${common[@]}" -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON \
        -DREQUIRE_CRYPTO_NATIVE=ON -DUSE_IMPLICIT_CRYPTO=OFF -DBUILD_DOC=OFF -DINSTALL_EXAMPLES=OFF \
        -DSTATIC_JPEG=ON "-DLIBJPEG_H_PATH=$prefix/include" "-DLIBJPEG_LIB_PATH=$prefix/lib/libjpeg.a" \
        "-DZLIB_H_PATH=$sdk/usr/include" "-DZLIB_LIB_PATH=$sdk/usr/lib/libz.tbd" >>"$log" 2>&1 || return 1
    cmake --build "$bld/qpdf" --target libqpdf_static >>"$log" 2>&1 || return 1
}

build_qpdf() {
    local sdk bld=$STAGING/qpdf-build prefix=$STAGING/qpdf-prefix dir=$STAGING/CQPDF log start archive
    sdk=$(xcrun --sdk macosx --show-sdk-path)
    mkdir -p "$WORK/logs"; log=$WORK/logs/qpdf-build-$(date +%Y%m%d-%H%M%S).log
    local pins_re="^($(IFS='|'; echo "${QPDF_SOURCES[*]}"))[[:space:]]"
    SOURCE_DATE_EPOCH=$(git -C "$ROOT" log -1 --format=%ct -G"$pins_re" -- Vendor/versions.lock 2>/dev/null || true)
    export SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-1761004800}
    export PKG_CONFIG_LIBDIR=$prefix/lib/pkgconfig PKG_CONFIG_PATH=
    echo "start $(date -u +%FT%TZ), load average $(sysctl -n vm.loadavg)" >"$log"
    start=$SECONDS
    rm -rf "$bld" "$prefix" "$dir"
    build_qpdf_libraries "$sdk" "$bld" "$prefix" "$log" ||
        { echo "error: the qpdf build failed; see $log" >&2; return 1; }
    archive=$(find "$bld/qpdf/libqpdf" -name 'libqpdf*.a' | head -1)
    [[ -f "$archive" ]] || { echo "error: no libqpdf archive in $bld/qpdf; see $log" >&2; return 1; }
    mkdir -p "$dir/Headers/CQPDF/qpdf"
    xcrun libtool -static -o "$dir/libCQPDF.a" "$archive" "$prefix/lib/libjpeg.a"
    cp "$(qpdf_source qpdf)"/include/qpdf/*.h "$(qpdf_source qpdf)"/include/qpdf/*.hh "$dir/Headers/CQPDF/qpdf/"
    package_xcframework CQPDF "$dir/libCQPDF.a" "$dir/Headers"
    echo "done in $((SECONDS - start)) s, load average $(sysctl -n vm.loadavg)" >>"$log"
}
