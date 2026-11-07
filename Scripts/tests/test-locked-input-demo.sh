#!/usr/bin/env bash
# demo-locked-input.sh (plan 20g F3, exit row V10): a locked PDF in Copy Text. Here the app, the renderer and the CER
# tool are stand-ins: one Unlock sheet and the text within 1 % CER pass; a second sheet, a text too far off or a
# secret file left behind fail; the password is never on a command line; a locked screen is skipped with nothing run.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
source "$(dirname "$0")/demo-stubs.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$ROOT/Scripts/demo-locked-input.sh
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
grep -q '^locked-input-demo:' "$ROOT/Makefile" || fail "Makefile has no locked-input-demo target"
stub_bin "$T"
cp "$(dirname "$0")/demo-stubs.sh" "$T/stubs-lib.sh"
cat >"$T/fake-app" <<'EOF'
#!/usr/bin/env bash
source "$(dirname "$0")/stubs-lib.sh"
folder=$(flag_value -ZivletLockedInputDemo "$@")
[[ "$(stat -f %Lp "$folder/secret")" == 600 ]] || exit 1
cp "$folder/secret" "$(dirname "$0")/seen-secret"
[[ -n "${FAKE_KEEP_SECRET:-}" ]] || rm -f "$folder/secret"
printf '{"asked":%s,"kind":"text","clipboard":"Zivlet keeps this page private"}' "${FAKE_ASKED:-[\"unlock\"]}" \
    >"$folder/locked.json"
touch "$folder/done"
EOF
printf '#!/usr/bin/env bash\necho "${FAKE_CER:-0.000}"\n' >"$T/cer"
chmod +x "$T/fake-app" "$T/cer"
run() {
    PATH=$T/bin:$PATH ZIVLET_DEMO_APP=$T/Zivlet.app ZIVLET_DEMO_SWIFT=$T/bin/swift ZIVLET_SCREEN_LOCKED=0 \
        ZIVLET_APP_PID_POLLS=1 ZIVLET_DEMO_TIMEOUT=5 ZIVLET_CER=$T/cer FAKE_INPUTS=Locked.pdf \
        FAKE_EXPECTED_NAME=expected.txt FAKE_EXPECTED_TEXT="Zivlet keeps this page private" "$SCRIPT" "$@"
}

out=$(run "$T/good" 2>&1) || fail "a good run must pass: $out"
assert_contains "$out" "PASS locked: one sheet"
assert_contains "$out" "PASS secrets"
assert_no_file "$T/good/secret"
assert_no_file "$T/good/inputs-secret"
assert_no_password_in_argv "$T/seen-secret" "$T/argv.log"

out=$(FAKE_ASKED='["unlock","retry"]' run "$T/twice" 2>&1 || true)
assert_contains "$out" "FAIL locked"
out=$(FAKE_CER=0.200 run "$T/far" 2>&1 || true)
assert_contains "$out" "FAIL locked"
status=0; out=$(FAKE_KEEP_SECRET=1 run "$T/kept" 2>&1) || status=$?
assert_eq "$status" "1" "a secret file left behind fails the run"
assert_contains "$out" "FAIL secrets"

out=$(PATH=$T/bin:$PATH ZIVLET_SCREEN_LOCKED=1 "$SCRIPT" "$T/locked" 2>&1) || fail "a locked screen is skipped, not failed"
assert_contains "$out" "skipped: screen locked"
assert_no_file "$T/locked/locked.json"
echo "PASS test-locked-input-demo"
