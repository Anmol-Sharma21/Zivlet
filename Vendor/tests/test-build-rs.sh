#!/usr/bin/env bash
# build-rs.sh runs the crate's tests, then packages zivlet-svg as CZivletSVG.xcframework: arm64, minos 26.0,
# both C entry points exported, and no build path in the archive.
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
X=$ROOT/Vendor/out/CZivletSVG.xcframework
out=$("$ROOT/Vendor/build-rs.sh" --test 2>&1) || { echo "$out" >&2; fail "build-rs.sh --test failed"; }
assert_contains "$out" "test result: ok. 6 passed"
assert_file "$X/Info.plist"
assert_file "$ROOT/Vendor/out/CZivletSVG.sha256"
lib=$(find "$X" -name 'libCZivletSVG.a' | head -1); assert_file "$lib"
# Rust's prebuilt compiler_builtins objects embed LLVM bitcode newer than Xcode's nm reads; nm still lists the
# Mach-O symbols but exits 1, so its status is ignored (the linker ignores the embedded bitcode).
syms=$(nm -gU "$lib" 2>/dev/null || true)
for s in _zivlet_svg_render _zivlet_svg_size _zivlet_svg_free; do grep -q " T $s\$" <<<"$syms" || fail "$s not exported"; done
lipo -archs "$lib" | grep -qx arm64 || fail "not arm64 only"
minos=$(otool -l "$lib" | awk '/minos/ { print $2 }' | sort -u | tr '\n' ' ')
assert_eq "$minos" "26.0 " "minos of every object"
if strings -a "$lib" | grep -qE '/Users/|/private/tmp|/var/folders/|cargo-home|/opt/homebrew'; then fail "path leak"; fi
grep -q 'module CZivletSVG' "$(find "$X" -name module.modulemap | head -1)" || fail "no module map"
# A toolchain other than the pinned one is refused.
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "rustc 1.0.0 (old)"\n' > "$T/bin/rustc"; chmod +x "$T/bin/rustc"
assert_fails env PATH="$T/bin:$PATH" "$ROOT/Vendor/build-rs.sh"
echo "PASS test-build-rs"
