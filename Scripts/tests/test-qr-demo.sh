#!/usr/bin/env bash
# demo-qr.sh (plan 20g F3, exit row V9): READ QR through the drop path. Here the app, the renderer, the log reader and
# screencapture are stand-ins: the drawn payloads shown with Open for the web link only pass; a payload that differs
# or an Open on a text fails; a results window that was not captured (no PNG) fails; the capture is by window number,
# never a region of the screen; a locked screen is skipped with nothing run.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
source "$(dirname "$0")/demo-stubs.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$ROOT/Scripts/demo-qr.sh
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
grep -q '^qr-demo:' "$ROOT/Makefile" || fail "Makefile has no qr-demo target"
stub_bin "$T"
cp "$(dirname "$0")/demo-stubs.sh" "$T/stubs-lib.sh"
# The app: reports the rows FAKE_ROWS gives (JSON), then done.
cat >"$T/fake-app" <<'EOF'
#!/usr/bin/env bash
source "$(dirname "$0")/stubs-lib.sh"
folder=$(flag_value -ZivletQRDemo "$@")
printf '{"kind":"window","rows":%s}' "$FAKE_ROWS" >"$folder/qr.json"
touch "$folder/done"
EOF
chmod +x "$T/fake-app"
good='[{"payload":"https://zivlet.app/test","open":true},{"payload":"Table 12","open":false}]'
run() {
    PATH=$T/bin:$PATH ZIVLET_DEMO_APP=$T/Zivlet.app ZIVLET_DEMO_SWIFT=$T/bin/swift ZIVLET_SCREEN_LOCKED=0 \
        ZIVLET_APP_PID_POLLS=1 ZIVLET_DEMO_TIMEOUT=5 ZIVLET_DEMO_LOG=$T/bin/fake-log FAKE_INPUTS="inputs/Menu.png" \
        FAKE_EXPECTED_NAME=expected-codes.txt FAKE_EXPECTED_TEXT=$'https://zivlet.app/test\tyes\nTable 12\tno' \
        FAKE_LOG_OUTPUT="2026-11-07 10:00:00 Zivlet: QR demo: window 4242 frame 10 20 340 300" "$SCRIPT" "$@"
}

out=$(FAKE_ROWS=$good run "$T/good" 2>&1) || fail "a good run must pass: $out"
assert_contains "$out" "PASS qr: 2 codes"
assert_contains "$out" "PASS capture"
assert_file "$T/good/qr-results.png"
assert_contains "$(cat "$T/argv.log")" "screencapture -x -o -l 4242"
grep -q 'screencapture.* -R' "$T/argv.log" && fail "a capture must never be a region of the screen"

out=$(FAKE_ROWS='[{"payload":"https://zivlet.app/test","open":true},{"payload":"Table 12","open":true}]' \
    run "$T/opentext" 2>&1 || true)
assert_contains "$out" "FAIL qr"
out=$(FAKE_ROWS='[{"payload":"https://zivlet.app/other","open":true},{"payload":"Table 12","open":false}]' \
    run "$T/payload" 2>&1 || true)
assert_contains "$out" "FAIL qr"
status=0; out=$(FAKE_NO_PNG=1 FAKE_ROWS=$good run "$T/nopng" 2>&1) || status=$?
assert_eq "$status" "1" "a missing PNG fails the run"
assert_contains "$out" "qr-results.png was not written"

out=$(PATH=$T/bin:$PATH ZIVLET_SCREEN_LOCKED=1 "$SCRIPT" "$T/locked" 2>&1) || fail "a locked screen is skipped, not failed"
assert_contains "$out" "skipped: screen locked"
assert_no_file "$T/locked/qr-results.png"
echo "PASS test-qr-demo"
