#!/usr/bin/env bash
# fetch.sh verifies SHA-256 before extracting, keeps one directory per component and refuses bad lock lines.
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/srv/pkg-1.0" && echo hello > "$T/srv/pkg-1.0/README"
tar -C "$T/srv" -czf "$T/pkg-1.0.tar.gz" pkg-1.0
GOOD=$(shasum -a 256 "$T/pkg-1.0.tar.gz" | cut -d' ' -f1)

echo "pkg 1.0 file://$T/pkg-1.0.tar.gz sha256:$GOOD" > "$T/good.lock"
"$ROOT/Vendor/fetch.sh" --lock "$T/good.lock" --downloads "$T/dl" --src "$T/src"
assert_file "$T/dl/pkg-1.0/pkg-1.0.tar.gz"
assert_eq "$(cat "$T/src/pkg-1.0/README")" "hello"
# A second run reuses the verified download.
out=$("$ROOT/Vendor/fetch.sh" --lock "$T/good.lock" --downloads "$T/dl" --src "$T/src")
assert_contains "$out" "pkg 1.0 cached"

echo "pkg 1.0 file://$T/pkg-1.0.tar.gz sha256:$(printf '0%.0s' {1..64})" > "$T/bad.lock"
assert_fails "$ROOT/Vendor/fetch.sh" --lock "$T/bad.lock" --downloads "$T/dl2" --src "$T/src2"
assert_no_file "$T/src2/pkg-1.0"
assert_no_file "$T/dl2/pkg-1.0/pkg-1.0.tar.gz"

echo "pkg 1.0 file://$T/pkg-1.0.tar.gz" > "$T/nohash.lock"
assert_fails "$ROOT/Vendor/fetch.sh" --lock "$T/nohash.lock" --downloads "$T/dl3" --src "$T/src3"

echo "../evil 1.0 file://$T/pkg-1.0.tar.gz sha256:$GOOD" > "$T/evil.lock"
assert_fails "$ROOT/Vendor/fetch.sh" --lock "$T/evil.lock" --downloads "$T/dl4" --src "$T/src4"

echo "pkg ../1.0 file://$T/pkg-1.0.tar.gz sha256:$GOOD" > "$T/evilver.lock"
assert_fails "$ROOT/Vendor/fetch.sh" --lock "$T/evilver.lock" --downloads "$T/dl5" --src "$T/src5"

echo "pkg 1.0 http://example.invalid/pkg-1.0.tar.gz sha256:$GOOD" > "$T/http.lock"
assert_fails "$ROOT/Vendor/fetch.sh" --lock "$T/http.lock" --downloads "$T/dl6" --src "$T/src6"

# --only limits the run to one component; a sparkle line is downloaded but never extracted.
{ echo "# comment"; echo "pkg 1.0 file://$T/pkg-1.0.tar.gz sha256:$GOOD"
  echo "sparkle 1.0 file://$T/pkg-1.0.tar.gz sha256:$GOOD"; } > "$T/two.lock"
"$ROOT/Vendor/fetch.sh" --lock "$T/two.lock" --downloads "$T/dl7" --src "$T/src7" --only sparkle >/dev/null
assert_file "$T/dl7/sparkle-1.0/pkg-1.0.tar.gz"
assert_no_file "$T/src7/sparkle-1.0"
assert_no_file "$T/dl7/pkg-1.0"
echo "PASS test-fetch"
