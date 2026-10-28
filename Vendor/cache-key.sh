#!/usr/bin/env bash
# Prints the cache key of the vendor outputs (11a §6.6): SHA-256 over the build inputs and `xcodebuild -version`.
# Usage: Vendor/cache-key.sh [--root REPO] [all|media|CWebP|CZivletSVG]     (default: all)
#   media       FFmpeg stage: the pins of its sources, build-media.sh, encoders.txt, stage-media.sh
#   CWebP       the libwebp pin, build-media.sh, build-native.sh, xcframework.sh
#   CZivletSVG  build-rs.sh, xcframework.sh, rust-toolchain.txt, the zivlet-svg crate (manifest, lock, sources)
#   all         the three keys together (written to Vendor/out/KEY and into the pack tarball name)
# Every component key also covers the scripts that drive, verify, pack and restore the outputs (COMMON), so a change
# to one of them never yields outputs under the key of the code before it. A component's pins are its own lines of
# versions.lock, so a pin for another component never invalidates it.
set -euo pipefail
source "$(dirname "$0")/../Scripts/env.sh" # DEVELOPER_DIR: the same Xcode for every build and key
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [[ "${1:-}" == "--root" ]]; then ROOT=$(cd "$2" && pwd); shift 2; fi
COMPONENT=${1:-all}

COMMON="Vendor/vendor.sh Vendor/verify-media.sh Vendor/check-tools.sh Vendor/fetch.sh Vendor/pack.sh Vendor/unpack.sh
Vendor/cache-key.sh Vendor/ensure-media.sh Vendor/ensure-native.sh Scripts/env.sh Scripts/ci-vendor.sh"

MEDIA_SOURCES="ffmpeg x264 libvpx svtav1 dav1d opus libogg libvorbis lame libwebp zimg"

# The versions.lock lines of the named sources, in file order.
pins() { awk -v names=" $* " 'index(names, " " $1 " ") > 0' "$ROOT/Vendor/versions.lock"; }

sources_of() {
    case "$1" in
        media) echo "$MEDIA_SOURCES" ;;
        CWebP) echo libwebp ;;
    esac
}

inputs() {
    case "$1" in
        media) echo $COMMON Vendor/build-media.sh Vendor/encoders.txt Vendor/stage-media.sh ;;
        CWebP) echo $COMMON Vendor/build-media.sh Vendor/build-native.sh Vendor/xcframework.sh ;;
        CZivletSVG)
            echo $COMMON Vendor/build-rs.sh Vendor/xcframework.sh Vendor/rust-toolchain.txt
            (cd "$ROOT" && find Vendor/rs/zivlet-svg/Cargo.toml Vendor/rs/zivlet-svg/Cargo.lock \
                Vendor/rs/zivlet-svg/src Vendor/rs/zivlet-svg/include -type f | LC_ALL=C sort)
            ;;
        *) return 1 ;;
    esac
}

toolchain() { xcodebuild -version 2>/dev/null | tr '\n' ' '; }

key_of() {
    local files
    files=$(inputs "$1") || { echo "error: unknown component $1 (all, media, CWebP, CZivletSVG)" >&2; exit 2; }
    # shellcheck disable=SC2086 # the list is our own fixed relative paths
    local names; names=$(sources_of "$1")
    {
        (cd "$ROOT" && shasum -a 256 $files)
        # shellcheck disable=SC2086 # names are our own fixed words
        [[ -z "$names" ]] || echo "pins $(pins $names | shasum -a 256 | cut -d' ' -f1)"
        echo "toolchain $(toolchain)"
    } | shasum -a 256 | cut -d' ' -f1
}

if [[ "$COMPONENT" == "all" ]]; then
    printf '%s\n' "$(key_of media)" "$(key_of CWebP)" "$(key_of CZivletSVG)" | shasum -a 256 | cut -d' ' -f1
else
    key_of "$COMPONENT"
fi
