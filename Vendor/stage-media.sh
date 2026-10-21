#!/usr/bin/env bash
# Copies the built media helpers into the app layout (11a §6.4): Vendor/out/media-stage/Helpers/{ffmpeg,ffprobe}
# and Frameworks/<seven libav* dylibs by major-versioned name, no symlinks>. Writes dSYMs to Vendor/out/media-dsym
# first, then strips local symbols (strip -x). Run Vendor/verify-media.sh on the result.
# Usage: Vendor/stage-media.sh
set -euo pipefail
source "$(dirname "$0")/../Scripts/env.sh" # DEVELOPER_DIR: the same Xcode for every build and key
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ZIVLET_VENDOR_WORK:-$ROOT/Vendor}
BUILT=$WORK/out/media; STAGE=$WORK/out/media-stage; DSYM=$WORK/out/media-dsym
HELPERS="ffmpeg ffprobe"
# FFmpeg 9.0.2 library majors (D-M4-1).
LIBRARIES="libavcodec.63 libavformat.63 libavfilter.12 libavutil.61 libswscale.10 libswresample.7 libavdevice.63"

[[ -x "$BUILT/bin/ffmpeg" ]] || { echo "error: $BUILT/bin/ffmpeg missing; run make vendor-media" >&2; exit 1; }
rm -rf "$STAGE" "$DSYM"
mkdir -p "$STAGE/Helpers" "$STAGE/Frameworks" "$DSYM"

# Copies one Mach-O, keeps its debug info as a dSYM, strips it and re-applies the ad-hoc signature strip removed.
stage_one() {
    local from=$1 to=$2
    [[ -f "$from" ]] || { echo "error: $from missing from the build" >&2; exit 1; }
    cp -L "$from" "$to"
    chmod 755 "$to"
    # --disable-debug builds carry symbol tables but no DWARF; dsymutil keeps the symbols and warns about DWARF.
    dsymutil "$to" -o "$DSYM/$(basename "$to").dSYM" 2>&1 | { grep -v "no debug symbols in executable" || true; } >&2
    strip -x "$to"
    local out
    if ! out=$(codesign --force --sign - "$to" 2>&1); then echo "error: cannot sign $to: $out" >&2; exit 1; fi
}

for h in $HELPERS; do stage_one "$BUILT/bin/$h" "$STAGE/Helpers/$h"; done
for l in $LIBRARIES; do stage_one "$BUILT/lib/$l.dylib" "$STAGE/Frameworks/$l.dylib"; done
echo "staged $(echo $HELPERS | wc -w | tr -d ' ') helpers and $(echo $LIBRARIES | wc -w | tr -d ' ') libraries in $STAGE"
