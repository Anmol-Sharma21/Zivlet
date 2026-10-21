#!/usr/bin/env bash
# licence-gate.sh matches Vendor/licenses.json to Vendor/versions.lock, allows only listed licences, needs every
# licence file and refuses a nonfree ffmpeg; collect-licences.sh and source-bundle.sh produce what ships.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
gate() { "$ROOT/Scripts/licence-gate.sh" --lock "$T/versions.lock" --manifest "$T/licenses.json" "$@" 2>&1; }
reset() { cp "$ROOT/Vendor/versions.lock" "$ROOT/Vendor/licenses.json" "$T/"; }

reset
out=$(gate) || fail "the real lock and manifest must pass: $out"
assert_contains "$out" "Licences OK: 13 components"

reset; jq 'del(.components[] | select(.name == "zimg"))' "$ROOT/Vendor/licenses.json" > "$T/licenses.json"
assert_contains "$(gate || true)" "no licence entry for zimg"
assert_fails gate

reset; jq '(.components[] | select(.name == "lame") | .spdx) = "LicenseRef-Proprietary"' \
    "$ROOT/Vendor/licenses.json" > "$T/licenses.json"
assert_contains "$(gate || true)" "licence not allowed"
assert_fails gate

reset; jq '(.components[] | select(.name == "opus") | .files) = ["NO-SUCH-FILE"]' \
    "$ROOT/Vendor/licenses.json" > "$T/licenses.json"
assert_contains "$(gate || true)" "NO-SUCH-FILE"

reset; printf '#!/bin/sh\necho "  configuration: --enable-gpl --enable-nonfree"\n' > "$T/ffmpeg"; chmod +x "$T/ffmpeg"
assert_contains "$(gate --ffmpeg "$T/ffmpeg" || true)" "nonfree"
assert_fails gate --ffmpeg "$T/ffmpeg"

# Licence texts collected for Contents/Resources/Licenses.
LICENSES_OUT=$T/licenses "$ROOT/Scripts/collect-licences.sh" >/dev/null
for name in ffmpeg x264 svtav1 libwebp resvg rust-crates; do assert_file "$T/licenses/$name.txt"; done
grep -q "GNU GENERAL PUBLIC LICENSE" "$T/licenses/ffmpeg.txt" || fail "ffmpeg.txt lacks the GPL text"
grep -q "tiny-skia" "$T/licenses/rust-crates.txt" || fail "crate licences lack tiny-skia"
grep -q 'href="zimg.txt"' "$T/licenses/index.html" || fail "index.html lacks zimg"

# Corresponding source: the repository, every pinned tarball, the crates and a rebuild guide.
ZIVLET_RELEASE_DIR=$T/release "$ROOT/Scripts/source-bundle.sh" 0.0.0-test >/dev/null
listing=$(tar -tf "$T/release/zivlet-0.0.0-test-source.tar.xz")
for entry in ffmpeg-9.0.2.tar.xz "x264-b35605ace3ddf7c1a5d67a2eb553f034aef41d55.tar.bz2" Vendor/build-media.sh \
    Vendor/rs/zivlet-svg/Cargo.lock vendor/resvg-0.47.0/ SOURCES.md; do
    grep -qF -- "$entry" <<<"$listing" || fail "source bundle lacks $entry"
done
echo "PASS test-licence-gate"
