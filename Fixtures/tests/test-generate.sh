#!/usr/bin/env bash
# generate.sh makes the same fixtures twice (determinism), every media recipe opens in ffprobe, --check fails after a
# fixture changes, and a set made by another ffmpeg skips the hash check and says so (P1-60, D-M4-15).
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GEN=$ROOT/Fixtures/generate.sh
STAGE=$ROOT/Vendor/out/media-stage/Helpers
T=$(tmpdir); trap 'rm -rf "$T"' EXIT

[[ -x "$GEN" ]] || fail "Fixtures/generate.sh is missing"
[[ -x "$STAGE/ffmpeg" ]] || { echo "SKIP test-generate: no vendored ffmpeg (make vendor)"; exit 0; }

"$GEN" --set small --out "$T/a" >/dev/null || fail "first run failed"
"$GEN" --set small --out "$T/b" >/dev/null || fail "second run failed"
assert_file "$T/a/small/manifest.sha256"
assert_eq "$(cat "$T/a/small/manifest.sha256")" "$(cat "$T/b/small/manifest.sha256")" "(two runs differ)"

# Every media recipe produced a file that ffprobe opens.
while read -r name _; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    assert_file "$T/a/small/$name"
    "$STAGE/ffprobe" -v error -show_entries format=format_name -of csv=p=0 "$T/a/small/$name" >/dev/null ||
        fail "ffprobe cannot open $name"
done <"$ROOT/Fixtures/media-recipes.txt"

# Images and drawings are there too.
for name in srgb.jpg srgb.heic srgb.webp alpha.png animated.png pages.tiff cmyk.jpg orientation-8.jpg drawing.svgz; do
    assert_file "$T/a/small/$name"
done

# --check against a manifest of this run passes, and fails once one fixture changes.
mkdir -p "$T/manifests"
cp "$T/a/small/manifest.sha256" "$T/manifests/manifest-small.sha256"
out=$(ZIVLET_FIXTURES_MANIFESTS=$T/manifests "$GEN" --check --set small --out "$T/a" 2>&1) || fail "check failed: $out"
assert_contains "$out" "fixtures OK: small"
printf 'x' >>"$T/a/small/tone.wma"
assert_fails env ZIVLET_FIXTURES_MANIFESTS="$T/manifests" "$GEN" --check --set small --out "$T/a"
out=$(ZIVLET_FIXTURES_MANIFESTS=$T/manifests "$GEN" --check --set small --out "$T/a" 2>&1 || true)
assert_contains "$out" "tone.wma"

# A set made with another ffmpeg is not hash-checked, and the check says so.
if [[ -x /opt/homebrew/bin/ffmpeg && -x /opt/homebrew/bin/ffprobe ]]; then
    "$GEN" --set small --out "$T/c" --ffmpeg /opt/homebrew/bin >/dev/null 2>&1 || fail "Homebrew run failed"
    out=$(ZIVLET_FIXTURES_MANIFESTS=$T/manifests "$GEN" --check --set small --out "$T/c" 2>&1) ||
        fail "check of a non-vendored set must pass: $out"
    assert_contains "$out" "hash check skipped: not the vendored ffmpeg"
fi

# Bad arguments are refused.
assert_fails "$GEN" --set huge --out "$T/d"
assert_fails "$GEN" --out relative/path
echo "PASS test-generate"
