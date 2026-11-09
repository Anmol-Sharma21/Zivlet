#!/usr/bin/env bash
# build-rs.sh runs the crate's tests, then packages zivlet-svg as CZivletSVG.xcframework: arm64, our object built for
# macOS 26.0 and nothing needing a newer one, both C entry points exported, and no build path in the archive.
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
# zivlet_svg's own object is built for macOS 26.0. Rust's prebuilt compiler_builtins objects keep the toolchain's
# minimum (26.0 from Homebrew's Rust, 11.0 from rustup's on GitHub's runner, OWN-CI-1); none may need a newer macOS.
minos=$(otool -l "$lib" | awk '/\(.*\):$/ { m = $0; sub(/.*\(/, "", m); sub(/\):$/, "", m) } $1 == "minos" { print m, $2 }')
own=$(awk '$1 ~ /^zivlet_svg-/ { print $2 }' <<<"$minos" | sort -u | tr '\n' ' ')
assert_eq "$own" "26.0 " "minos of zivlet_svg's own object"
newest=$(awk '{ print $2 }' <<<"$minos" | sort -V | tail -1)
assert_eq "$newest" "26.0" "newest minos of any object"
# rustup's prebuilt compiler_builtins name their sources under the Rust project's own release builder
# (/Users/runner/work/rust/rust/); that is upstream's path, not this build's, so it is counted and set aside.
paths=$(strings -a "$lib" | grep -E '/Users/|/private/tmp|/var/folders/|cargo-home|/opt/homebrew' || true)
upstream=$(grep -c '^/Users/runner/work/rust/rust/' <<<"$paths" || true)
((upstream == 0)) || echo "note: $upstream source paths of Rust's own release build set aside"
leaks=$(grep -v '^/Users/runner/work/rust/rust/' <<<"$paths" | grep -v '^$' | sort -u | head -5 || true)
[[ -z "$leaks" ]] || fail "path leak: $leaks"
grep -q 'module CZivletSVG' "$(find "$X" -name module.modulemap | head -1)" || fail "no module map"
# A toolchain other than the pinned one is refused.
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "rustc 1.0.0 (old)"\n' > "$T/bin/rustc"; chmod +x "$T/bin/rustc"
assert_fails env PATH="$T/bin:$PATH" "$ROOT/Vendor/build-rs.sh"
echo "PASS test-build-rs"
