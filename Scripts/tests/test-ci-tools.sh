#!/usr/bin/env bash
# ci-tools.sh installs build tools on GitHub's runner only: the formulas for missing tools and the pinned Rust
# toolchain. On a developer Mac it installs nothing; it always ends with the tool check.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
for tool in brew rustup; do
    printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\n' "$tool" "$T" >"$T/bin/$tool"
    chmod +x "$T/bin/$tool"
done
printf '#!/bin/sh\necho check >>"%s/calls"\n' "$T" >"$T/check"; chmod +x "$T/check"
run() { env -i HOME="$HOME" PATH="$T/bin:/usr/bin:/bin" ZIVLET_CHECK_TOOLS="$T/check" "$@" "$ROOT/Scripts/ci-tools.sh"; }

# Off GitHub: no install, only the check.
: >"$T/calls"; run || fail "ci-tools.sh failed off GitHub"
assert_eq "$(cat "$T/calls")" "check" "off GitHub, only the tool check runs"

# On GitHub, with none of the tools on PATH: every formula, then the pinned Rust as the default, then the check.
: >"$T/calls"; run GITHUB_ACTIONS=true || fail "ci-tools.sh failed on GitHub"
calls=$(cat "$T/calls")
rust=$(tr -d '[:space:]' <"$ROOT/Vendor/rust-toolchain.txt")
for formula in xcodegen meson autoconf automake libtool pkgconf cmake ninja; do
    assert_contains "$calls" "brew install --quiet $formula"
done
assert_contains "$calls" "rustup toolchain install $rust --profile minimal"
assert_contains "$calls" "rustup default $rust"
assert_eq "$(tail -1 <<<"$calls")" "check" "the tool check runs last"

# A failing check fails the script.
printf '#!/bin/sh\nexit 1\n' >"$T/check"
assert_fails run
echo "PASS test-ci-tools"
