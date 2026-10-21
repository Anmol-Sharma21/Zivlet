#!/usr/bin/env bash
# Builds Vendor/rs/zivlet-svg (resvg 0.47.0 behind a C ABI, D-M4-7) and packages it as
# Vendor/out/CZivletSVG.xcframework with a content hash in CZivletSVG.sha256.
# Usage: Vendor/build-rs.sh [--test]     --test runs the crate's tests first.
# Crates download into Vendor/downloads/cargo-home and are checked against the committed Cargo.lock (--locked).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ZIVLET_VENDOR_WORK:-$ROOT/Vendor}
OUT=$WORK/out; CRATE=$WORK/rs/zivlet-svg; STAGING=$WORK/build/native/CZivletSVG
TARGET=aarch64-apple-darwin
RUST_WANT=$(tr -d '[:space:]' <"$ROOT/Vendor/rust-toolchain.txt")
export CARGO_HOME=${ZIVLET_CARGO_HOME:-$ROOT/Vendor/downloads/cargo-home}
export CARGO_TARGET_DIR=$CRATE/target
export MACOSX_DEPLOYMENT_TARGET=26.0
export ZERO_AR_DATE=1
# Build paths must not reach the archive: map the crate registry, the crate and the toolchain sysroot.
SYSROOT=$(rustc --print sysroot 2>/dev/null || true)
export RUSTFLAGS="--remap-path-prefix=$CARGO_HOME=/cargo --remap-path-prefix=$CRATE=/zivlet-svg \
--remap-path-prefix=${SYSROOT:-/nonexistent}=/rust -C target-cpu=apple-m1"

source "$ROOT/Vendor/xcframework.sh"

have=$(rustc --version 2>/dev/null | awk '{print $2}')
if [[ "$have" != "$RUST_WANT" ]]; then
    echo "error: rustc ${have:-missing}; Vendor/rust-toolchain.txt pins $RUST_WANT (brew install rust)" >&2
    exit 1
fi
[[ -f "$CRATE/Cargo.lock" ]] || { echo "error: $CRATE/Cargo.lock missing" >&2; exit 1; }

if [[ "${1:-}" == "--test" ]]; then
    # Tests run on the host with the default (unwinding) test profile; the release archive aborts on panic.
    cargo test --locked --manifest-path "$CRATE/Cargo.toml" 2>&1
fi
# staticlib alone: with the rlib type also requested (for the tests) rustc skips fat LTO and leaves the C entry
# points out of the archive's objects.
cargo rustc --locked --release --lib --crate-type staticlib --target "$TARGET" --manifest-path "$CRATE/Cargo.toml"

rm -rf "$STAGING"
mkdir -p "$STAGING/Headers"
cp "$CARGO_TARGET_DIR/$TARGET/release/libzivlet_svg.a" "$STAGING/libCZivletSVG.a"
cp "$CRATE/include/zivlet_svg.h" "$STAGING/Headers/"
cat >"$STAGING/Headers/module.modulemap" <<'MAP'
module CZivletSVG {
    header "zivlet_svg.h"
    link "CZivletSVG"
    export *
}
MAP
package_xcframework CZivletSVG "$STAGING/libCZivletSVG.a" "$STAGING/Headers"
