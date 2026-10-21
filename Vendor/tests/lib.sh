#!/usr/bin/env bash
# Minimal assertions for Vendor/tests/*.sh and Scripts/tests/*.sh. Each test file runs in its own temp dir.
set -euo pipefail
fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1] ${3:-}"; }
assert_file() { [[ -s "$1" ]] || fail "missing file $1"; }
assert_no_file() { [[ ! -e "$1" ]] || fail "unexpected file $1"; }
assert_fails() { if "$@" >/dev/null 2>&1; then fail "command succeeded: $*"; fi; }
assert_contains() { grep -qF -- "$2" <<<"$1" || fail "output lacks [$2]: $1"; }
tmpdir() { mktemp -d "${TMPDIR:-/tmp}/zivlet-vendor-test.XXXXXX"; }
