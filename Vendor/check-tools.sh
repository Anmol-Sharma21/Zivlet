#!/usr/bin/env bash
# Fails fast, one line per missing or outdated build tool, before any configure runs (11a §6.1).
# Reads versions only; it never installs anything. nasm/yasm are not needed on arm64: x264, libvpx, dav1d and
# SVT-AV1 use clang's integrated AArch64 assembler.
set -euo pipefail
ROOT=$(cd "${0%/*}/.." && pwd)   # no dirname: this must run with a bare PATH
RUST_WANT=$(tr -d '[:space:]' <"$ROOT/Vendor/rust-toolchain.txt")
missing=(); problems=0

# Homebrew formula for each tool (glibtoolize is GNU libtool; /usr/bin/libtool is Apple's archiver).
formula() {
    case "$1" in
        glibtoolize) echo libtool ;;
        pkg-config) echo pkgconf ;;
        cargo | rustc) echo rust ;;
        *) echo "$1" ;;
    esac
}

# First dotted version number in a line of text, e.g. "cmake version 4.4.4" -> 4.4.4.
version_in() { grep -oE '[0-9]+(\.[0-9]+)+' <<<"$1" | head -1; }

# True when dotted version $1 >= $2 (major, then minor, then patch).
at_least() {
    local IFS=. i; local -a have=($1) need=($2)
    for i in 0 1 2; do
        local h=${have[i]:-0} n=${need[i]:-0}
        if ((h > n)); then return 0; fi
        if ((h < n)); then return 1; fi
    done
    return 0
}

report_missing() { echo "missing: $1 (brew install $(formula "$1"))" >&2; missing+=("$(formula "$1")"); problems=1; }

check() {
    local tool=$1 min=${2:-} exact=${3:-} line version
    if ! command -v "$tool" >/dev/null 2>&1; then report_missing "$tool"; return; fi
    [[ -z "$min" && -z "$exact" ]] && return
    line=$("$tool" --version 2>&1 | head -1); version=$(version_in "$line")
    if [[ -n "$min" ]] && ! at_least "$version" "$min"; then
        echo "too old: $tool $version (need $min; brew upgrade $(formula "$tool"))" >&2; problems=1
    fi
    if [[ -n "$exact" && "$version" != "$exact" ]]; then
        echo "wrong version: $tool $version (Vendor/rust-toolchain.txt pins $exact)" >&2; problems=1
    fi
}

check cmake 3.25
check meson 1.3
check ninja
check autoconf
check automake
check glibtoolize
check pkg-config
check cargo "" "$RUST_WANT"
check rustc "" "$RUST_WANT"
if ! command -v xcrun >/dev/null 2>&1 || ! xcrun -f clang >/dev/null 2>&1; then
    echo "missing: clang (install Xcode and set DEVELOPER_DIR)" >&2; problems=1
fi

if ((${#missing[@]})); then
    echo "Install the missing tools with: brew install $(printf '%s\n' "${missing[@]}" | awk '!seen[$0]++' | tr '\n' ' ')" >&2
fi
exit "$problems"
