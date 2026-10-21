#!/usr/bin/env bash
# Deterministic test fixtures (05 P1-60, D-M4-15): media with ffmpeg's lavfi sources (Fixtures/media-recipes.txt),
# images with the zivlet-fixtures tool (ImageIO, libwebp), and SVG text written here. Nothing binary is committed:
# Fixtures/manifest-<set>.sha256 holds the hashes the vendored ffmpeg must reproduce.
#
#   generate.sh [--set small|full] [--out <abs dir>] [--ffmpeg <abs dir>]   make <out>/<set> and its manifest.sha256
#   generate.sh --check [--set …] [--out …]   compare <out>/<set> (made first if missing) with the committed manifest
#   generate.sh --update [--set …]            make the set with the vendored ffmpeg and rewrite the committed manifest
#
# The check compares hashes only when the set was made by the vendored ffmpeg; image hashes also need the macOS
# build the manifest was made on (ImageIO's encoders belong to the OS). `probe` entries are opened, not hashed.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/Scripts/env.sh"
STAGE_FFMPEG=$ROOT/Vendor/out/media-stage/Helpers/ffmpeg
MANIFESTS=${ZIVLET_FIXTURES_MANIFESTS:-$ROOT/Fixtures}
SUFFIX=(-fflags +bitexact -flags:v +bitexact -flags:a +bitexact -metadata creation_time=2026-01-01T00:00:00Z)

die() { echo "generate.sh: $*" >&2; exit 1; }
is_safe_dir() { [[ "$1" == /* && "/$1/" != */../* ]]; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

SET=small OUT=$ROOT/build/fixtures MODE=generate TOOLS=
while (($#)); do
    case "$1" in
    --set) SET=${2:-}; shift 2 ;;
    --out) OUT=${2:-}; shift 2 ;;
    --ffmpeg) TOOLS=${2:-}; shift 2 ;;
    --check) MODE=check; shift ;;
    --update) MODE=update; shift ;;
    *) die "unknown argument $1" ;;
    esac
done
case "$SET" in
small) W=160 H=120 D=1 R=10 ;;
full) W=1280 H=720 D=5 R=30 ;;
*) die "--set must be small or full" ;;
esac
is_safe_dir "$OUT" || die "--out must be an absolute path without '..'"
DIR=$OUT/$SET

# ffmpeg: --ffmpeg, then the vendored stage, then ZIVLET_FFMPEG_DIR, then Homebrew.
resolve_tools() {
    local candidate
    if [[ -n "$TOOLS" ]]; then
        is_safe_dir "$TOOLS" && [[ -x "$TOOLS/ffmpeg" && -x "$TOOLS/ffprobe" ]] ||
            die "--ffmpeg must be an absolute directory with ffmpeg and ffprobe"
    fi
    for candidate in "$TOOLS" "$(dirname "$STAGE_FFMPEG")" "${ZIVLET_FFMPEG_DIR:-}" /opt/homebrew/bin; do
        [[ -n "$candidate" && -x "$candidate/ffmpeg" && -x "$candidate/ffprobe" ]] || continue
        is_safe_dir "$candidate" || continue
        FFMPEG=$candidate/ffmpeg FFPROBE=$candidate/ffprobe
        return 0
    done
    die "no ffmpeg found (make vendor, or pass --ffmpeg <dir>)"
}

is_vendored() { [[ -x "$STAGE_FFMPEG" && "$(sha "$FFMPEG")" == "$(sha "$STAGE_FFMPEG")" ]]; }

# SVG fixtures and the subtitle/chapter inputs: text written by Zivlet; the svgz is gzip without a name or date.
write_text() {
    mkdir -p "$DIR/.inputs"
    cat >"$DIR/drawing.svg" <<'SVG'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="0 0 120 80">
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#2a6fdb"/>
      <stop offset="1" stop-color="#7fd1ae"/>
    </linearGradient>
  </defs>
  <rect width="120" height="80" fill="url(#sky)"/>
  <circle cx="30" cy="40" r="18" fill="#f2c14e"/>
  <path d="M60 64 L84 20 L108 64 Z" fill="#e4572e" fill-opacity="0.85"/>
  <text x="8" y="74" font-family="Helvetica" font-size="10" fill="#ffffff">fixture</text>
</svg>
SVG
    gzip -n -9 -c "$DIR/drawing.svg" >"$DIR/drawing.svgz"
    printf '1\n00:00:00,000 --> 00:00:00,500\nFirst line\n\n2\n00:00:00,500 --> 00:00:01,000\nSecond line\n' \
        >"$DIR/.inputs/subs.srt"
    printf '%s\n' "[Script Info]" "ScriptType: v4.00+" "PlayResX: 160" "PlayResY: 120" "" "[V4+ Styles]" \
        "Format: Name, Fontname, Fontsize, PrimaryColour, BackColour, Bold, Italic, Alignment, MarginL, MarginR, MarginV" \
        "Style: Default,Helvetica,12,&H00FFFFFF,&H00000000,0,0,2,10,10,10" "" "[Events]" \
        "Format: Layer, Start, End, Style, Text" "Dialogue: 0,0:00:00.00,0:00:01.00,Default,Styled line" \
        >"$DIR/.inputs/subs.ass"
    printf ';FFMETADATA1\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=0\nEND=500\ntitle=Opening\n[CHAPTER]\nTIMEBASE=1/1000\nSTART=500\nEND=1000\ntitle=Closing\n' \
        >"$DIR/.inputs/chapters.txt"
    printf 'text hash drawing.svg\ntext hash drawing.svgz\n' >>"$DIR/.entries"
}

expand() {
    local text=$1
    text=${text//\{W\}/$W} text=${text//\{H\}/$H} text=${text//\{D\}/$D} text=${text//\{R\}/$R}
    text=${text//\{IN\}/$DIR/.inputs} text=${text//\{OUT\}/$DIR}
    printf '%s' "$text"
}

# A recipe that fails stops the run with the vendored ffmpeg; another ffmpeg may lack an encoder, so it is skipped.
make_media() {
    local name check rest args
    while read -r name check rest; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        read -r -a args <<<"$(expand "$rest")"
        if "$FFMPEG" -hide_banner -nostdin -loglevel error -y "${args[@]}" "${SUFFIX[@]}" "$DIR/$name" 2>"$DIR/.err"; then
            printf 'media %s %s\n' "$check" "$name" >>"$DIR/.entries"
        elif is_vendored; then
            die "$name failed: $(tail -3 "$DIR/.err")"
        else
            echo "note: skipped $name: this ffmpeg cannot make it" >&2
        fi
    done <"$ROOT/Fixtures/media-recipes.txt"
}

make_images() {
    "$ROOT/Vendor/ensure-native.sh" >/dev/null
    (cd "$KIT" && swift build --product zivlet-fixtures >"$DIR/.err" 2>&1) || die "zivlet-fixtures did not build: $(tail -5 "$DIR/.err")"
    local tool line
    tool="$(cd "$KIT" && swift build --show-bin-path)/zivlet-fixtures"
    "$tool" --set "$SET" --out "$DIR" >"$DIR/.images" || die "zivlet-fixtures failed"
    while read -r line; do printf 'image %s %s\n' "${line#* }" "${line%% *}" >>"$DIR/.entries"; done <"$DIR/.images"
}

write_manifest() {
    local kind check name origin=other
    is_vendored && origin=vendored
    {
        echo "# zivlet fixtures, set $SET"
        echo "# ffmpeg $(sha "$FFMPEG") $origin"
        echo "# macos $(sw_vers -buildVersion)"
        while read -r kind check name; do
            if [[ "$check" == hash ]]; then echo "$(sha "$DIR/$name")  $kind  $name"; else echo "probe-only  $kind  $name"; fi
        done < <(LC_ALL=C sort -k3 "$DIR/.entries")
    } >"$DIR/manifest.sha256"
}

generate() {
    resolve_tools
    mkdir -p "$DIR"
    : >"$DIR/.entries"
    write_text
    make_media
    make_images
    write_manifest
    echo "fixtures made: $SET $(grep -vc '^#' "$DIR/manifest.sha256") files in $DIR"
}

# Prints one line per problem; image hashes are skipped when the macOS build differs.
compare() {
    local committed=$1 same_os=$2 hash kind name expected
    while read -r hash kind name; do
        [[ "$hash" == \#* ]] && continue
        [[ -f "$DIR/$name" ]] || { echo "missing: $name"; continue; }
        if [[ "$hash" == probe-only ]]; then
            [[ "$kind" != media ]] || "$FFPROBE" -v error -show_format "$DIR/$name" >/dev/null 2>&1 ||
                echo "does not open: $name"
            continue
        fi
        [[ "$kind" == image && "$same_os" != yes ]] && continue
        expected=$(awk -v n="$name" '$3 == n { print $1 }' "$committed")
        [[ -n "$expected" ]] || { echo "not in the committed manifest: $name"; continue; }
        [[ "$(sha "$DIR/$name")" == "$expected" ]] || echo "changed: $name"
    done <"$DIR/manifest.sha256"
}

check() {
    [[ -f "$DIR/manifest.sha256" ]] || generate >/dev/null
    resolve_tools
    local committed=$MANIFESTS/manifest-$SET.sha256 count problems same_os=no
    count=$(grep -vc '^#' "$DIR/manifest.sha256")
    if ! grep -q '^# ffmpeg [0-9a-f]* vendored$' "$DIR/manifest.sha256"; then
        echo "hash check skipped: not the vendored ffmpeg"
        echo "fixtures OK: $SET $count files (not hash-checked)"
        return 0
    fi
    [[ -f "$committed" ]] || die "no committed manifest $committed (run generate.sh --update --set $SET)"
    [[ "$(grep '^# macos' "$committed")" == "$(grep '^# macos' "$DIR/manifest.sha256")" ]] && same_os=yes
    [[ $same_os == yes ]] || echo "note: image hashes skipped: the manifest was made on another macOS build"
    problems=$(compare "$committed" "$same_os")
    [[ -z "$problems" ]] || { echo "$problems" >&2; die "fixtures differ from $committed"; }
    echo "fixtures OK: $SET $count files"
}

case "$MODE" in
generate) generate ;;
check) check ;;
update)
    generate
    is_vendored || die "--update needs the vendored ffmpeg (make vendor)"
    cp "$DIR/manifest.sha256" "$ROOT/Fixtures/manifest-$SET.sha256"
    echo "updated Fixtures/manifest-$SET.sha256"
    ;;
esac
