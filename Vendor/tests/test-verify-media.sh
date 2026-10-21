#!/usr/bin/env bash
# verify-media.sh refuses a stage without a GPL v3 ffmpeg, reports nonfree builds, and passes the real stage.
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/s/Helpers" "$T/s/Frameworks"
cp /usr/bin/true "$T/s/Helpers/ffmpeg"; cp /usr/bin/true "$T/s/Helpers/ffprobe"
assert_fails "$ROOT/Vendor/verify-media.sh" "$T/s"
printf '#!/bin/sh\necho "  configuration: --enable-nonfree"\n' > "$T/s/Helpers/ffmpeg"; chmod +x "$T/s/Helpers/ffmpeg"
out=$("$ROOT/Vendor/verify-media.sh" "$T/s" 2>&1 || true)
grep -q "nonfree" <<<"$out" || fail "nonfree not reported"
assert_fails "$ROOT/Vendor/verify-media.sh" "$T/missing-stage"
if [[ -x "$ROOT/Vendor/out/media-stage/Helpers/ffmpeg" ]]; then   # after A3 and stage-media.sh on this machine
  "$ROOT/Vendor/verify-media.sh" "$ROOT/Vendor/out/media-stage" >/dev/null
  # A stage with an extra, path-leaking file must fail.
  cp -R "$ROOT/Vendor/out/media-stage" "$T/leaky"
  printf 'built in /Users/someone/src\n' > "$T/leaky/Frameworks/notes.txt"
  cp /usr/bin/true "$T/leaky/Frameworks/libextra.dylib"
  assert_fails "$ROOT/Vendor/verify-media.sh" "$T/leaky"
fi
echo "PASS test-verify-media"
