#!/usr/bin/env bash
# Gate for a staged media tree <stage>/{Helpers,Frameworks} (P0-36, 11a §6.4). Fails on: nonfree in -buildconf,
# a licence other than GPL v3, a dependency outside @rpath/ /usr/lib/ /System/Library/, a non-arm64 slice,
# minos != 26.0, a build path in any binary, a missing runtime encoder or filter, a hostile demuxer, a device
# other than lavfi, a network protocol, or more than 30 MiB installed.
# Usage: Vendor/verify-media.sh <stage>
set -euo pipefail
STAGE=${1:?usage: verify-media.sh <stage>}
MAX_KB=30720 # 05 P0-36: stripped size <= 30 MiB
MACOS_MIN=26.0
# Runtime names (configure names differ: movtext -> mov_text, libvpx_vp9 -> libvpx-vp9).
ENCODERS="h264_videotoolbox hevc_videotoolbox prores_videotoolbox libx264 libvpx libvpx-vp9 libsvtav1 libopus
libvorbis libmp3lame aac_at alac_at aac alac flac wmav2 wmv2 mpeg4 gif libwebp libwebp_anim png apng mjpeg mov_text
webvtt srt subrip ass ssa pcm_s16le pcm_s16be pcm_s24le pcm_s24be pcm_s32le pcm_s32be pcm_f32le"
FILTERS="zscale tonemap palettegen paletteuse scale format"
HOSTILE_DEMUXERS="hls dash webm_dash_manifest sdp rtsp rtp"
NETWORK_PROTOCOLS="http https tcp udp rtmp tls"
LEAK_PATTERN='/Users/|/private/tmp/|/var/folders/|/opt/homebrew'
problems=0
problem() { echo "verify-media: $*" >&2; problems=1; }

[[ -d "$STAGE/Helpers" && -d "$STAGE/Frameworks" ]] || { echo "verify-media: $STAGE is not a stage" >&2; exit 1; }
FFMPEG=$STAGE/Helpers/ffmpeg
[[ -x "$FFMPEG" && -x "$STAGE/Helpers/ffprobe" ]] || { echo "verify-media: ffmpeg or ffprobe missing" >&2; exit 1; }

# Second column of the rows after the dashed header of `ffmpeg -encoders/-filters/-demuxers/-devices`.
listing() { "$FFMPEG" -hide_banner "$1" 2>/dev/null | awk 'seen { print $2 } /^ *-+ *$/ { seen = 1 }' | tr ',' '\n'; }

check_licence() {
    if "$FFMPEG" -hide_banner -buildconf 2>&1 | grep -q nonfree; then problem "nonfree in -buildconf"; fi
    "$FFMPEG" -hide_banner -L 2>&1 | grep -q "version 3" || problem "licence is not GPL v3 (ffmpeg -L)"
}

check_machos() {
    local file deps archs
    while IFS= read -r -d '' file; do
        file -b "$file" | grep -q "Mach-O" || continue
        deps=$(otool -L "$file" | tail -n +2 | awk '{print $1}' | grep -v -E '^(@rpath/|/usr/lib/|/System/Library/)' || true)
        [[ -z "$deps" ]] || problem "dependency outside the bundle or the OS in ${file#"$STAGE/"}: $deps"
        archs=$(lipo -archs "$file" 2>/dev/null || true)
        [[ "$archs" == "arm64" ]] || problem "architectures [$archs] in ${file#"$STAGE/"} (want arm64 only)"
        otool -l "$file" | grep -A4 LC_BUILD_VERSION | grep -q "minos $MACOS_MIN" ||
            problem "minos is not $MACOS_MIN in ${file#"$STAGE/"}"
    done < <(find "$STAGE" -type f -print0)
}

check_leaks() {
    local file leaks=0
    while IFS= read -r -d '' file; do
        if strings -a "$file" | grep -qE "$LEAK_PATTERN"; then problem "build path in ${file#"$STAGE/"}"; leaks=1; fi
    done < <(find "$STAGE" -type f -print0)
    LEAKS=$leaks
}

check_components() {
    local name have
    have=$(listing -encoders)
    for name in $ENCODERS; do grep -qx -- "$name" <<<"$have" || problem "missing encoder $name"; done
    have=$(listing -filters)
    for name in $FILTERS; do grep -qx -- "$name" <<<"$have" || problem "missing filter $name"; done
    have=$(listing -demuxers)
    for name in $HOSTILE_DEMUXERS; do if grep -qx -- "$name" <<<"$have"; then problem "demuxer $name present"; fi; done
    have=$(listing -devices | sort -u | tr '\n' ' ')
    [[ "$have" == "lavfi " ]] || problem "devices [$have] (want lavfi only)"
    have=$("$FFMPEG" -hide_banner -protocols 2>/dev/null | awk 'NF == 1 && $1 !~ /:$/ { print $1 }')
    for name in $NETWORK_PROTOCOLS; do if grep -qx -- "$name" <<<"$have"; then problem "protocol $name present"; fi; done
}

LEAKS=0
check_licence
check_machos
check_leaks
check_components
size_kb=$(du -sk "$STAGE" | cut -f1)
((size_kb <= MAX_KB)) || problem "stage is ${size_kb} KB (limit $MAX_KB KB)"
if ((problems)); then echo "verify-media: FAILED for $STAGE" >&2; exit 1; fi
encoder_count=$(wc -w <<<"$ENCODERS" | tr -d ' ')
printf 'media stage OK: %s MiB, %d path leaks, %s encoders, GPL v3\n' \
    "$(awk -v k="$size_kb" 'BEGIN { printf "%.2f", k / 1024 }')" "$LEAKS" "$encoder_count"
