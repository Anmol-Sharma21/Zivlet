#!/usr/bin/env bash
# vm-smoke.sh exits 3 naming owner step O-4 without Tart or an image, runs the guest checks over ssh in a fresh clone,
# fails when they fail, and always deletes the clone. tart and ssh are fakes on PATH.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/rel"
touch "$T/rel/Zivlet-0.1.0.dmg"
cat >"$T/bin/tart" <<'EOF'
#!/bin/sh
echo "tart $*" >>"$FAKE_CALLS"
case "$1" in
    ip) echo 192.0.2.10 ;;
    run) sleep 30 ;;
esac
EOF
cat >"$T/bin/ssh" <<'EOF'
#!/bin/sh
echo "ssh $*" >>"$FAKE_CALLS"
cat >"$FAKE_GUEST_SCRIPT"
[ "$FAKE_GUEST" = ok ] && echo "ZIVLET-SMOKE-OK"
[ "$FAKE_GUEST" = ok ]
EOF
chmod +x "$T/bin/tart" "$T/bin/ssh"
export FAKE_CALLS=$T/calls FAKE_GUEST_SCRIPT=$T/guest.sh
SMOKE=$ROOT/Scripts/vm-smoke.sh

set +e; out=$(env -u ZIVLET_TART_IMAGE PATH="$T/bin:$PATH" "$SMOKE" "$T/rel/Zivlet-0.1.0.dmg" 2>&1); code=$?; set -e
assert_eq "$code" "3" "exit code without an image"
assert_contains "$out" "(owner step O-4)"
set +e; ZIVLET_TART_IMAGE=img PATH=/usr/bin:/bin "$SMOKE" "$T/rel/Zivlet-0.1.0.dmg" >/dev/null 2>&1; code=$?; set -e
assert_eq "$code" "3" "exit code without tart"

: >"$FAKE_CALLS"
out=$(ZIVLET_TART_IMAGE=zivlet-26.0 FAKE_GUEST=ok PATH="$T/bin:$PATH" "$SMOKE" "$T/rel/Zivlet-0.1.0.dmg" 2>&1) ||
    fail "a passing guest failed: $out"
calls=$(cat "$FAKE_CALLS")
assert_contains "$calls" "tart clone zivlet-26.0 zivlet-smoke-"
assert_contains "$calls" "--dir=release:$(cd "$T/rel" && pwd):ro"
assert_contains "$calls" "tart delete zivlet-smoke-"
assert_contains "$(cat "$FAKE_GUEST_SCRIPT")" "spctl"
assert_contains "$(cat "$FAKE_GUEST_SCRIPT")" "Contents/Helpers/ffmpeg"

: >"$FAKE_CALLS"
assert_fails env ZIVLET_TART_IMAGE=zivlet-26.0 FAKE_GUEST=fail PATH="$T/bin:$PATH" "$SMOKE" "$T/rel/Zivlet-0.1.0.dmg"
assert_contains "$(cat "$FAKE_CALLS")" "tart delete zivlet-smoke-"
assert_fails env ZIVLET_TART_IMAGE=zivlet-26.0 PATH="$T/bin:$PATH" "$SMOKE" "$T/rel/missing.dmg"
echo "PASS test-vm-smoke"
