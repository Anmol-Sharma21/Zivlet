#!/usr/bin/env bash
# demo-lock.sh (plan 20g F3, exit row V8): LOCK · UNLOCK through the drop path of the Debug app. Here the app, the
# input renderer and the PDF checker are stand-ins: a run whose steps and checks pass passes; a missing step, a
# failed check or a secret file left behind fails; a locked screen is skipped with nothing run; and no password is
# ever on a command line (the checker gets them on stdin).
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
source "$(dirname "$0")/demo-stubs.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$ROOT/Scripts/demo-lock.sh
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
grep -q '^lock-demo:' "$ROOT/Makefile" || fail "Makefile has no lock-demo target"
stub_bin "$T"
# The app: keeps a copy of the secret file for the test, deletes it (unless FAKE_KEEP_SECRET), writes each step's
# report and its new file, then done.
cat >"$T/fake-app" <<'EOF'
#!/usr/bin/env bash
source "$(dirname "$0")/stubs-lib.sh"
folder=$(flag_value -ZivletProtectDemo "$@")
[[ "$(stat -f %Lp "$folder/secret")" == 600 ]] || exit 1
cp "$folder/secret" "$(dirname "$0")/seen-secret"
[[ -n "${FAKE_KEEP_SECRET:-}" ]] || rm -f "$folder/secret"
report() { printf '{"asked":%s,"outputs":%s}' "$2" "$3" >"$folder/$1.json"; }
report lock '["lock"]' '["Report Locked.pdf"]'
report unlock '["unlock"]' '["Report Unlocked.pdf"]'
[[ -n "${FAKE_NO_CHANGE:-}" ]] || report change '["unlock"]' '["Report Locked 2.pdf"]'
report wrong '["unlock","retry"]' '[]'
touch "$folder/done"
EOF
cp "$(dirname "$0")/demo-stubs.sh" "$T/stubs-lib.sh"
cat >"$T/checker" <<EOF
#!/usr/bin/env bash
cat >"$T/checker-stdin"
echo "PASS checks"
[[ -z "\${FAKE_CHECK_FAIL:-}" ]]
EOF
chmod +x "$T/fake-app" "$T/checker"
run() {
    PATH=$T/bin:$PATH ZIVLET_DEMO_APP=$T/Zivlet.app ZIVLET_DEMO_SWIFT=$T/bin/swift ZIVLET_SCREEN_LOCKED=0 \
        ZIVLET_APP_PID_POLLS=1 ZIVLET_DEMO_TIMEOUT=5 ZIVLET_PDF_CHECK=$T/checker FAKE_INPUTS=Report.pdf \
        "$SCRIPT" "$@"
}

out=$(run "$T/good" 2>&1) || fail "a good run must pass: $out"
assert_contains "$out" "PASS lock"
assert_contains "$out" "PASS change"
assert_contains "$out" "PASS wrong"
assert_contains "$out" "PASS secrets"
assert_no_file "$T/good/secret"
assert_no_file "$T/good/inputs-secret"
# The checker had both passwords on stdin, and neither was on any command line.
assert_eq "$(head -2 "$T/checker-stdin" | awk 'length($0) == 24' | wc -l | tr -d ' ')" "2" "two passwords on stdin"
assert_eq "$(head -2 "$T/checker-stdin")" "$(cat "$T/seen-secret")" "the checker got the app's passwords"
assert_contains "$(cat "$T/checker-stdin")" "opens	$T/good/Report Locked 2.pdf	2"
assert_no_password_in_argv "$T/seen-secret" "$T/argv.log"
assert_contains "$(cat "$T/argv.log")" "-ZivletProtectDemo $T/good"

out=$(FAKE_NO_CHANGE=1 run "$T/nochange" 2>&1 || true)
assert_contains "$out" "FAIL change"
assert_fails env PATH="$T/bin:$PATH" ZIVLET_DEMO_APP="$T/Zivlet.app" ZIVLET_DEMO_SWIFT="$T/bin/swift" \
    ZIVLET_SCREEN_LOCKED=0 ZIVLET_APP_PID_POLLS=1 ZIVLET_DEMO_TIMEOUT=5 ZIVLET_PDF_CHECK="$T/checker" \
    FAKE_INPUTS=Report.pdf FAKE_CHECK_FAIL=1 "$SCRIPT" "$T/badcheck"
out=$(FAKE_KEEP_SECRET=1 run "$T/kept" 2>&1 || true)
assert_contains "$out" "FAIL secrets: secret was left"

# A folder with files the script did not make is refused and left alone.
mkdir -p "$T/foreign"
echo "keep me" >"$T/foreign/notes.txt"
assert_fails run "$T/foreign"
assert_eq "$(cat "$T/foreign/notes.txt")" "keep me" "a foreign folder is left alone"

out=$(PATH=$T/bin:$PATH ZIVLET_SCREEN_LOCKED=1 "$SCRIPT" "$T/locked" 2>&1) || fail "a locked screen is skipped, not failed"
assert_contains "$out" "skipped: screen locked"
assert_no_file "$T/locked/steps.json"
echo "PASS test-lock-demo"
