#!/usr/bin/env bash
# Build tools for a CI job on GitHub's hosted `xcode-27` image (P0-07, OWN-CI-1). On GitHub (GITHUB_ACTIONS=true) it
# installs, with Homebrew, each tool Vendor/check-tools.sh needs that the image lacks, and the Rust toolchain that
# Vendor/rust-toolchain.txt pins (the image's own Rust is newer). Anywhere else it installs nothing. Either way it ends
# with Vendor/check-tools.sh, so a missing or wrong tool fails here, before any build.
# Usage: Scripts/ci-tools.sh
set -euo pipefail
source "$(dirname "$0")/env.sh"
CHECK=${ZIVLET_CHECK_TOOLS:-$REPO_ROOT/Vendor/check-tools.sh}
# tool:formula; `make app` runs /opt/homebrew/bin/xcodegen, so XcodeGen must come from Homebrew.
TOOLS=(xcodegen:xcodegen meson:meson autoconf:autoconf automake:automake glibtoolize:libtool pkg-config:pkgconf
    cmake:cmake ninja:ninja)

if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1
    for entry in "${TOOLS[@]}"; do
        command -v "${entry%%:*}" >/dev/null 2>&1 || brew install --quiet "${entry#*:}"
    done
    rust=$(tr -d '[:space:]' <"$REPO_ROOT/Vendor/rust-toolchain.txt")
    rustup toolchain install "$rust" --profile minimal
    rustup default "$rust"
fi
"$CHECK"
