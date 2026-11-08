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
assert_contains "$out" "Licences OK: 15 components"
# qpdf's MD5 code is under RSA's MD5 notice, which the owner accepted on 2026-11-08 (D-M7-63, OS-M7-15): nothing
# waits for a decision, and a release passes.
[[ "$out" != *"pending owner decision"* ]] || fail "no licence should wait for the owner: $out"
release=$(gate --release) || fail "a release must pass the gate: $release"
grep -q 'licence-gate.sh" --release' "$ROOT/Scripts/release-local.sh" || fail "the release does not run the gate with --release"

# A licence that asks for words in the product's documentation (IJG, RSA-MD) needs its acknowledgement.
reset; jq 'del(.components[] | select(.name == "libjpeg-turbo") | .acknowledgement)' \
    "$ROOT/Vendor/licenses.json" > "$T/licenses.json"
assert_contains "$(gate || true)" "no acknowledgement for libjpeg-turbo"
assert_fails gate

reset; jq 'del(.components[] | select(.name == "zimg"))' "$ROOT/Vendor/licenses.json" > "$T/licenses.json"
assert_contains "$(gate || true)" "no licence entry for zimg"
assert_fails gate

reset; jq 'del(.components[] | select(.name == "qpdf"))' "$ROOT/Vendor/licenses.json" > "$T/licenses.json"
assert_contains "$(gate || true)" "no licence entry for qpdf"
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
for name in ffmpeg x264 svtav1 libwebp resvg qpdf libjpeg-turbo rust-crates; do assert_file "$T/licenses/$name.txt"; done
# qpdf's Apache NOTICE is reproduced verbatim (10 §10); libjpeg-turbo carries the IJG README it requires.
notice=$(tar -xOf "$ROOT/Vendor/downloads/qpdf-12.4.2/qpdf-12.4.2.tar.gz" qpdf-12.4.2/NOTICE.md)
grep -qF -- "$(head -1 <<<"$notice")" "$T/licenses/qpdf.txt" || fail "qpdf.txt lacks NOTICE.md"
[[ "$(awk '/^===== NOTICE.md =====$/ { on = 1; getline; next } on && /^===== / { exit } on' "$T/licenses/qpdf.txt")" == \
    "$notice" ]] || fail "qpdf.txt does not reproduce NOTICE.md verbatim"
grep -q "Apache License" "$T/licenses/qpdf.txt" || fail "qpdf.txt lacks the Apache licence"
grep -q "Independent JPEG Group" "$T/licenses/libjpeg-turbo.txt" || fail "libjpeg-turbo.txt lacks README.ijg"
# The binary's documentation states the IJG sentence (README.ijg clause 2) and names qpdf's MD5 code as RSA's notice
# asks; qpdf.txt keeps that notice.
ijg="This software is based in part on the work of the Independent JPEG Group."
rsa="derived from the RSA Data Security, Inc. MD5 Message-Digest Algorithm"
grep -qF "$ijg" "$T/licenses/index.html" || fail "index.html lacks the IJG acknowledgement"
grep -qF "$rsa" "$T/licenses/index.html" || fail "index.html lacks the RSA MD5 identification"
grep -qF "$ijg" "$ROOT/THIRD_PARTY_NOTICES.md" || fail "THIRD_PARTY_NOTICES.md lacks the IJG acknowledgement"
grep -qF "$rsa" "$ROOT/THIRD_PARTY_NOTICES.md" || fail "THIRD_PARTY_NOTICES.md lacks the RSA MD5 identification"
grep -qF "Copyright (C) 1991-2, RSA Data Security, Inc." "$T/licenses/qpdf.txt" || fail "qpdf.txt lacks RSA's MD5 notice"
grep -qF "These notices must be retained" "$T/licenses/qpdf.txt" || fail "qpdf.txt cuts RSA's MD5 notice short"
grep -q "GNU GENERAL PUBLIC LICENSE" "$T/licenses/ffmpeg.txt" || fail "ffmpeg.txt lacks the GPL text"
grep -q "tiny-skia" "$T/licenses/rust-crates.txt" || fail "crate licences lack tiny-skia"
grep -q 'href="zimg.txt"' "$T/licenses/index.html" || fail "index.html lacks zimg"

# Corresponding source: the repository, every pinned tarball, the crates and a rebuild guide.
ZIVLET_RELEASE_DIR=$T/release "$ROOT/Scripts/source-bundle.sh" 0.0.0-test >/dev/null
listing=$(tar -tf "$T/release/zivlet-0.0.0-test-source.tar.xz")
for entry in ffmpeg-9.0.2.tar.xz "x264-b35605ace3ddf7c1a5d67a2eb553f034aef41d55.tar.bz2" Vendor/build-media.sh \
    qpdf-12.4.2.tar.gz libjpeg-turbo-3.2.0.tar.gz Vendor/build-qpdf.sh Vendor/rs/zivlet-svg/Cargo.lock \
    vendor/resvg-0.47.0/ SOURCES.md; do
    grep -qF -- "$entry" <<<"$listing" || fail "source bundle lacks $entry"
done
guide=$(tar -xOf "$T/release/zivlet-0.0.0-test-source.tar.xz" zivlet-0.0.0-test-source/SOURCES.md)
for word in qpdf libjpeg-turbo CQPDF ZivletWorker; do
    grep -qF -- "$word" <<<"$guide" || fail "SOURCES.md does not name $word"
done
echo "PASS test-licence-gate"
