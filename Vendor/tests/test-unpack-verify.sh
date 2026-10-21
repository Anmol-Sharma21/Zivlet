#!/usr/bin/env bash
# unpack.sh trusts nothing a restored archive says about itself: every xcframework must match its tree hash, each
# component stamp must equal that component's current key, and a media stage must pass verify-media.sh. A refused
# archive leaves out/ as it was.
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$ROOT/Vendor/xcframework.sh" # tree_hash
T=$(tmpdir); trap 'rm -rf "$T"' EXIT

# A verifier stand-in that records the stage it was asked about and exits with $VERIFY_EXIT.
cat >"$T/verify" <<'SH'
#!/usr/bin/env bash
echo "$1" >>"$VERIFY_LOG"
exit "${VERIFY_EXIT:-0}"
SH
chmod +x "$T/verify"

# Packs an archive with the current keys, one xcframework, and a media stage.
make_archive() {
    local dir=$T/pack-$1 name=$1
    rm -rf "$dir"; mkdir -p "$dir/out/CWebP.xcframework" "$dir/out/media-stage/Helpers"
    echo lib >"$dir/out/CWebP.xcframework/libCWebP.a"
    tree_hash "$dir/out/CWebP.xcframework" >"$dir/out/CWebP.sha256"
    "$ROOT/Vendor/cache-key.sh" CWebP >"$dir/out/CWebP.key"
    "$ROOT/Vendor/cache-key.sh" media >"$dir/out/media-stage/KEY"
    echo bin >"$dir/out/media-stage/Helpers/ffmpeg"
    "$ROOT/Vendor/cache-key.sh" >"$dir/out/KEY"
    COPYFILE_DISABLE=1 tar -C "$dir" -cJf "$T/$name.tar.xz" out
}
unpack() { VERIFY_LOG=$T/log ZIVLET_VERIFY_MEDIA=$T/verify ZIVLET_VENDOR_WORK=$T/work "$ROOT/Vendor/unpack.sh" "$@"; }

# A sound archive unpacks, and the stage was verified where it was extracted.
make_archive good
out=$(unpack "$T/good.tar.xz" 2>&1) || fail "a sound archive was refused: $out"
assert_file "$T/work/out/CWebP.xcframework/libCWebP.a"
assert_contains "$(cat "$T/log")" "media-stage"

# A library swapped after hashing is refused, and the earlier outputs stay.
make_archive swapped
echo evil >"$T/pack-swapped/out/CWebP.xcframework/libCWebP.a"
COPYFILE_DISABLE=1 tar -C "$T/pack-swapped" -cJf "$T/swapped.tar.xz" out
assert_fails unpack "$T/swapped.tar.xz"
assert_eq "$(cat "$T/work/out/CWebP.xcframework/libCWebP.a")" "lib" "after a refused archive"

# A stage the verifier rejects is refused.
make_archive bad-stage
assert_fails env VERIFY_EXIT=1 VERIFY_LOG="$T/log" ZIVLET_VERIFY_MEDIA="$T/verify" ZIVLET_VENDOR_WORK="$T/work" \
    "$ROOT/Vendor/unpack.sh" "$T/bad-stage.tar.xz"

# A component stamp from other inputs is refused even when out/KEY was rewritten to match.
make_archive stamp
echo "0000000000000000000000000000000000000000000000000000000000000000" >"$T/pack-stamp/out/CWebP.key"
COPYFILE_DISABLE=1 tar -C "$T/pack-stamp" -cJf "$T/stamp.tar.xz" out
assert_fails unpack "$T/stamp.tar.xz"
echo "PASS test-unpack-verify"
