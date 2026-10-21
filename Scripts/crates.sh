#!/usr/bin/env bash
# Every Rust crate linked into CZivletSVG (normal dependencies for aarch64-apple-darwin), one sorted
# "name vVERSION LICENCE-EXPRESSION" line each, including zivlet_svg itself. Offline: the crates come from
# Vendor/downloads/cargo-home (Vendor/build-rs.sh fetches them). Used by the licence gate, the acknowledgements and
# the SBOM, so all three see the same tree.
# Usage: Scripts/crates.sh
set -euo pipefail
source "$(dirname "$0")/env.sh"
CARGO_HOME=${ZIVLET_CARGO_HOME:-$REPO_ROOT/Vendor/downloads/cargo-home}
cd "$REPO_ROOT/Vendor/rs/zivlet-svg"
CARGO_HOME=$CARGO_HOME cargo tree --locked --offline -e normal --target aarch64-apple-darwin --prefix none \
    --format '{p} {l}' | sed -e 's/ (\*)$//' -e 's/ (\/[^)]*)//' | sort -u
