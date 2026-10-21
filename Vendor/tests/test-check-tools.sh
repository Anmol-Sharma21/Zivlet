#!/usr/bin/env bash
# check-tools.sh names every missing build tool with an install hint and exits 1; it passes on a ready Mac.
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
# An empty PATH (plus coreutils) must name every missing tool and exit 1.
mkdir -p "$T/bin"; for c in bash env grep sed awk head cut tr uname cat; do ln -s "$(command -v $c)" "$T/bin/$c"; done
out=$(PATH="$T/bin" "$ROOT/Vendor/check-tools.sh" 2>&1 || true)
for tool in cmake meson ninja autoconf automake glibtoolize pkg-config cargo rustc; do
  grep -q "missing: $tool" <<<"$out" || fail "no message for $tool"
done
grep -q "brew install" <<<"$out" || fail "no install hint"
assert_fails env PATH="$T/bin" "$ROOT/Vendor/check-tools.sh"
# A too-old cmake is reported as such.
printf '#!/bin/sh\necho "cmake version 3.10.0"\n' > "$T/bin/cmake"; chmod +x "$T/bin/cmake"
out=$(PATH="$T/bin" "$ROOT/Vendor/check-tools.sh" 2>&1 || true)
assert_contains "$out" "too old: cmake 3.10.0 (need 3.25"
"$ROOT/Vendor/check-tools.sh" >/dev/null   # the dev Mac has every tool after index §2
echo "PASS test-check-tools"
