#!/usr/bin/env bash
# The hostile corpus (05 P1-62): files that try to make Zivlet read other files, run filter graphs, follow links,
# block, or allocate without bound. Every one must be refused with Zivlet's copy or converted without leaking the
# canary, a file holding a random 32-byte token that the playlist, the concat list and the SVG point at.
#
#   Fixtures/hostile/generate.sh [--out <abs dir>]     writes <dir> (default build/fixtures/hostile)
#
# Uses the vendored ffmpeg (or ZIVLET_FFMPEG_DIR, then Homebrew) for the truncated MP4 only.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$ROOT/Scripts/env.sh"
OUT=$ROOT/build/fixtures/hostile
die() { echo "hostile/generate.sh: $*" >&2; exit 1; }

while (($#)); do
    case "$1" in
    --out) OUT=${2:-}; shift 2 ;;
    *) die "unknown argument $1" ;;
    esac
done
[[ "$OUT" == /* && "/$OUT/" != */../* ]] || die "--out must be an absolute path without '..'"

ffmpeg_tool() {
    local dir
    for dir in "$ROOT/Vendor/out/media-stage/Helpers" "${ZIVLET_FFMPEG_DIR:-}" /opt/homebrew/bin; do
        [[ -n "$dir" && -x "$dir/ffmpeg" ]] && { echo "$dir/ffmpeg"; return 0; }
    done
    die "no ffmpeg found (make vendor)"
}

# Streams and lists that ask a demuxer to open other files.
write_redirections() {
    local canary=$1
    printf '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:1\n#EXTINF:1.0,\nfile:///etc/passwd\n#EXTINF:1.0,\nfile://%s\n#EXT-X-ENDLIST\n' \
        "$canary" >"$OUT/playlist.mp4"
    printf "ffconcat version 1.0\nfile '%s'\nfile '/etc/passwd'\n" "$canary" >"$OUT/concat.mkv"
    printf 'testsrc2=d=1:s=64x48,drawtext=textfile=%s\n' "$canary" >"$OUT/lavfi-graph.mp4"
}

# SVG: a billion-laughs entity block, and an image pointing at the canary outside the file.
write_svgs() {
    local canary=$1
    {
        echo '<?xml version="1.0"?>'
        echo '<!DOCTYPE svg ['
        echo '  <!ENTITY a0 "laugh">'
        local i
        for i in 1 2 3 4 5 6 7 8 9; do
            echo "  <!ENTITY a$i \"&a$((i - 1));&a$((i - 1));&a$((i - 1));&a$((i - 1));&a$((i - 1));&a$((i - 1));&a$((i - 1));&a$((i - 1));&a$((i - 1));&a$((i - 1));\">"
        done
        echo ']>'
        echo '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="48"><text y="20">&a9;</text></svg>'
    } >"$OUT/entities.svg"
    cat >"$OUT/external-href.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="64" height="48">
  <rect width="64" height="48" fill="#3a7"/>
  <image href="file://$canary" width="64" height="48"/>
  <image xlink:href="$canary" width="64" height="48"/>
</svg>
SVG
    # 80 MB of spaces inside an SVG element: about 80 KB compressed.
    { printf '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8">'; head -c 80000000 /dev/zero | tr '\0' ' '; printf '</svg>'; } |
        gzip -9 -n >"$OUT/bomb.svgz"
}

write_containers() {
    local work=$OUT/.work
    mkdir -p "$work"
    "$(ffmpeg_tool)" -hide_banner -nostdin -loglevel error -y -f lavfi -i testsrc2=d=2:s=320x240:r=25 \
        -c:v libx264 -pix_fmt yuv420p "$work/whole.mp4"
    head -c 4096 "$work/whole.mp4" >"$OUT/truncated.mp4"
    printf 'not a picture\n' >"$work/readme.txt"
    (cd "$work" && zip -q -X "$OUT/archive.tiff" readme.txt) || die "zip failed"
}

write_images() {
    "$ROOT/Vendor/ensure-native.sh" >/dev/null
    (cd "$KIT" && swift build --product zivlet-fixtures >/dev/null 2>&1) || die "zivlet-fixtures did not build"
    "$(cd "$KIT" && swift build --show-bin-path)/zivlet-fixtures" --set hostile --out "$OUT" >/dev/null
}

# A symlink to the canary named like a picture, and a FIFO named like a sound.
write_specials() {
    ln -sfn "$OUT/canary.txt" "$OUT/link.png"
    [[ -p "$OUT/stream.wav" ]] || mkfifo "$OUT/stream.wav"
}

mkdir -p "$OUT"
od -An -tx1 -N32 /dev/urandom | tr -d ' \n' >"$OUT/canary.txt"
canary=$OUT/canary.txt
write_redirections "$canary"
write_svgs "$canary"
write_containers
write_images
write_specials
echo "hostile corpus: $(find "$OUT" -maxdepth 1 ! -name '.*' ! -name canary.txt ! -path "$OUT" | wc -l | tr -d ' ') files in $OUT"
