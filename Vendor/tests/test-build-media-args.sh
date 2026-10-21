#!/usr/bin/env bash
# build-media.sh's FFmpeg configure line (printed by --print-config, no build) keeps the licence, the confinement
# and the encoder allow-list decisions of D-M4-1...D-M4-4.
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cfg=$("$ROOT/Vendor/build-media.sh" --print-config)
for flag in --enable-gpl --enable-version3 --enable-shared --disable-static "--install-name-dir=@rpath" \
  --disable-network --disable-autodetect --enable-videotoolbox --enable-audiotoolbox --enable-libx264 \
  --enable-libvpx --enable-libsvtav1 --enable-libdav1d --enable-libopus --enable-libvorbis --enable-libmp3lame \
  --enable-libwebp --enable-libzimg --disable-devices --enable-indev=lavfi --disable-ffplay \
  "--disable-demuxer=hls,dash,webm_dash_manifest,sdp,rtsp,rtp" --disable-encoders --extra-libs=-liconv \
  "-Wl,-rpath,@executable_path/../Frameworks"; do
  grep -qF -- "$flag" <<<"$cfg" || fail "configure line lacks $flag"
done
if grep -qF -- "--enable-nonfree" <<<"$cfg"; then fail "nonfree must never be enabled"; fi
grep -qF -- "-ffile-prefix-map=" <<<"$cfg" || fail "no path map"
grep -qF -- "-mmacosx-version-min=26.0" <<<"$cfg" || fail "no deployment target"
grep -qF -- "--enable-encoder=libx264," <<<"$cfg" || fail "encoder allow-list not passed from encoders.txt"
# Every encoder name the planners emit (FFmpegRequirements) must be in the allow-list, by configure name.
for e in libx264 libvpx_vp9 libsvtav1 libopus libvorbis libmp3lame libwebp libwebp_anim h264_videotoolbox \
  hevc_videotoolbox aac_at alac flac wmav2 wmv2 mpeg4 gif png mjpeg movtext webvtt srt subrip ass ssa \
  pcm_s16le pcm_s16be pcm_s24le pcm_s24be pcm_s32le pcm_s32be pcm_f32le; do
  grep -qx "$e" "$ROOT/Vendor/encoders.txt" || fail "encoders.txt lacks $e"
done
if grep -qx "opus" "$ROOT/Vendor/encoders.txt"; then fail "native opus encoder must stay off (03b §5.4)"; fi
if grep -qx "vorbis" "$ROOT/Vendor/encoders.txt"; then fail "native vorbis encoder must stay off"; fi
if grep -qx "mov_text" "$ROOT/Vendor/encoders.txt"; then fail "mov_text is a runtime name; configure calls it movtext"; fi
# Unknown component names are refused before anything builds.
assert_fails "$ROOT/Vendor/build-media.sh" not-a-component
echo "PASS test-build-media-args"
