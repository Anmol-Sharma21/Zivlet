#!/usr/bin/env bash
# pdf-smoke.sh (plan 20g, exit row V6): LOCK · UNLOCK in the real worker. Here the app is a stand-in that starts two
# short-lived processes named as the app and its worker, and the renderer and checker are stand-ins too: a run whose
# steps and checks pass passes; a password in the worker's command line fails; a child of the worker fails; a missing
# step fails; no password is ever on a command line of the script's own tools.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
source "$(dirname "$0")/demo-stubs.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$ROOT/Scripts/pdf-smoke.sh
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
grep -q '^pdf-smoke:' "$ROOT/Makefile" || fail "Makefile has no pdf-smoke target"
stub_bin "$T"
cp "$(dirname "$0")/demo-stubs.sh" "$T/stubs-lib.sh"
# The app: a process named as the app and one named as its worker (FAKE_WORKER=leak puts the first password in the
# worker's command line, =child gives it a child), every step's report, then done after a second.
cat >"$T/fake-app" <<'EOF'
#!/usr/bin/env bash
here=$(dirname "$0")
source "$here/stubs-lib.sh"
folder=$(flag_value -ZivletProtectDemo "$@")
cp "$folder/secret" "$here/seen-secret"
password=$(head -1 "$folder/secret")
rm -f "$folder/secret"
app=$here/Zivlet.app
worker=$app/Contents/XPCServices/ZivletWorker.xpc/Contents/MacOS/ZivletWorker
(exec -a "$app/Contents/MacOS/Zivlet" sleep 4) >/dev/null 2>&1 &
case "${FAKE_WORKER:-}" in
    leak) (exec -a "$worker --unlock=$password" sleep 3) >/dev/null 2>&1 & ;;
    child) (exec -a "$worker" bash -c 'sleep 3 & wait') >/dev/null 2>&1 & ;;
    *) (exec -a "$worker" sleep 3) >/dev/null 2>&1 & ;;
esac
report() { printf '{"asked":%s,"outputs":%s}' "$2" "$3" >"$folder/$1.json"; }
report lock '["lock"]' '["Report Locked.pdf"]'
report lock-restricted '["lock"]' '["Form Locked.pdf"]'
report unlock '["unlock"]' '["Report Unlocked.pdf"]'
report unlock-owner '["unlock","ownerNeeded"]' '["Form Unlocked.pdf"]'
report change '["unlock"]' '["Report Locked 2.pdf"]'
[[ -n "${FAKE_NO_WRONG:-}" ]] || report wrong '["unlock","retry"]' '[]'
report legacy-rc4 '["unlock"]' '["Legacy RC4 Unlocked.pdf"]'
report legacy-aes '["unlock"]' '["Legacy AES Locked.pdf"]'
(sleep 1.5 && touch "$folder/done") >/dev/null 2>&1 &
EOF
cat >"$T/checker" <<EOF
#!/usr/bin/env bash
cat >"$T/checker-stdin"
echo "PASS checks"
EOF
chmod +x "$T/fake-app" "$T/checker"
run() {
    PATH=$T/bin:$PATH ZIVLET_DEMO_APP=$T/Zivlet.app ZIVLET_DEMO_SWIFT=$T/bin/swift ZIVLET_DEMO_TIMEOUT=10 \
        ZIVLET_PDF_CHECK=$T/checker FAKE_INPUTS="Report.pdf Form.pdf" "$SCRIPT" "$@"
}

out=$(run "$T/good" 2>&1) || fail "a good run must pass: $out"
assert_contains "$out" "PASS watch"
assert_contains "$out" "PASS unlock-owner"
assert_contains "$out" "PASS legacy-aes"
assert_contains "$out" "PASS secrets"
assert_eq "$(head -3 "$T/checker-stdin")" "$(cat "$T/seen-secret")" "the checker got the three passwords on stdin"
assert_contains "$(cat "$T/checker-stdin")" "restricted	$T/good/Form Locked.pdf	1"
assert_no_password_in_argv "$T/seen-secret" "$T/argv.log"

status=0; out=$(FAKE_WORKER=leak run "$T/leak" 2>&1) || status=$?
assert_eq "$status" "1" "a password in the worker's command line fails the run"
assert_contains "$out" "FAIL watch: a password"
status=0; out=$(FAKE_WORKER=child run "$T/child" 2>&1) || status=$?
assert_eq "$status" "1" "a child of the worker fails the run"
assert_contains "$out" "started a child process"
out=$(FAKE_NO_WRONG=1 run "$T/nowrong" 2>&1 || true)
assert_contains "$out" "FAIL wrong: no report"
sleep 2  # the stand-in processes end on their own
echo "PASS test-pdf-smoke"
