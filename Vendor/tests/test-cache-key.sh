#!/usr/bin/env bash
# cache-key.sh hashes exactly the vendor build inputs; unpack.sh refuses an archive built from other inputs.
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
key() { "$ROOT/Vendor/cache-key.sh" --root "$T/repo" "$@"; }
mkdir -p "$T/repo"
(cd "$ROOT" && git ls-files Vendor | tar -cf - -T -) | tar -xf - -C "$T/repo"

base=$(key)
[[ "$base" =~ ^[0-9a-f]{64}$ ]] || fail "key is not 64 hex chars: $base"
for c in media CWebP CZivletSVG; do [[ "$(key "$c")" =~ ^[0-9a-f]{64}$ ]] || fail "no key for $c"; done
assert_fails "$ROOT/Vendor/cache-key.sh" --root "$T/repo" nonsense

# Unrelated files do not change any key.
media=$(key media); svg=$(key CZivletSVG)
echo "notes" > "$T/repo/Vendor/NOTES.txt"; echo "# more" >> "$T/repo/Vendor/tests/test-fetch.sh"
assert_eq "$(key)" "$base" "after an unrelated change"

# One byte in an input changes the keys that depend on it, and only those.
echo "pcm_s24le" >> "$T/repo/Vendor/encoders.txt"
[[ "$(key)" != "$base" ]] || fail "encoders.txt not in the key"
[[ "$(key media)" != "$media" ]] || fail "encoders.txt not in the media key"
assert_eq "$(key CZivletSVG)" "$svg" "the SVG key must not depend on encoders.txt"
echo "// x" >> "$T/repo/Vendor/rs/zivlet-svg/src/lib.rs"
[[ "$(key CZivletSVG)" != "$svg" ]] || fail "crate source not in the SVG key"

# unpack.sh: refuses an archive whose KEY differs from the current inputs unless --force.
mkdir -p "$T/w/out/media-stage/Helpers"; echo stub > "$T/w/out/media-stage/Helpers/ffmpeg"
echo "0000000000000000000000000000000000000000000000000000000000000000" > "$T/w/out/KEY"
ZIVLET_VENDOR_WORK=$T/w "$ROOT/Vendor/pack.sh" >/dev/null
tarball=$(ls "$T"/w/out/zivlet-vendor-*.tar.xz); assert_file "$tarball"
mkdir -p "$T/w2"
assert_fails env ZIVLET_VENDOR_WORK="$T/w2" "$ROOT/Vendor/unpack.sh" "$tarball"
assert_no_file "$T/w2/out/media-stage/Helpers/ffmpeg"
ZIVLET_VENDOR_WORK=$T/w2 "$ROOT/Vendor/unpack.sh" "$tarball" --force >/dev/null
assert_eq "$(cat "$T/w2/out/media-stage/Helpers/ffmpeg")" "stub"
# An archive with a member outside out/ is refused.
mkdir -p "$T/evil/x"; echo bad > "$T/evil/x/f"; tar -C "$T/evil" -cJf "$T/evil.tar.xz" x
assert_fails env ZIVLET_VENDOR_WORK="$T/w2" "$ROOT/Vendor/unpack.sh" "$T/evil.tar.xz" --force
echo "PASS test-cache-key"
