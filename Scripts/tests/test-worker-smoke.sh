#!/usr/bin/env bash
# worker-smoke.sh (plan 18c C12, exit row Z5): runs the app's -ZivletWorkerSmoke mode on a folder it creates, prints
# each step, fails on a failed or missing step and on a new ZivletWorker crash report, and removes only its folder.
# Here a fake app writes canned lines, so no real worker runs.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/Fake.app/Contents/MacOS" "$T/reports"
cat >"$T/Fake.app/Contents/MacOS/Zivlet" <<'EOF'
#!/usr/bin/env bash
# Fake: -ZivletWorkerSmoke <folder> -ZivletWorkerIdleSeconds <n>
folder=$2
out=$folder/worker-smoke.jsonl
step() { printf '{"step":"%s","ok":%s,"ms":%s,"detail":"%s"}\n' "$1" "$2" "$3" "$4" >>"$out"; }
step worker true 31 "pid 999, app pid 998"
step convert true 120 "photo.png to JPEG in the worker"
if [[ "${FAKE_MODE:-pass}" == fail ]]; then step cancel false 400 "cancel took 400 ms"; else step cancel true 3 "visible in 3 ms"; fi
step crash-retry true 900 "retried once, relaunch 35 ms"
if [[ "${FAKE_MODE:-pass}" == crash ]]; then touch "$ZIVLET_REPORTS_DIR/ZivletWorker-2026-10-27-000000.ips"; fi
if [[ "${FAKE_MODE:-pass}" != short ]]; then step crash-twice true 1500 "This file made the engine crash; next job saved"; fi
step idle-exit true 5100 "pid 999 gone after 5.1 s"
step done true 0 ""
echo "$folder" >"$ZIVLET_FAKE_SEEN"
EOF
chmod +x "$T/Fake.app/Contents/MacOS/Zivlet"
export ZIVLET_REPORTS_DIR=$T/reports ZIVLET_FAKE_SEEN=$T/seen

out=$("$ROOT/Scripts/worker-smoke.sh" "$T/Fake.app" 2>&1) || fail "a passing run must pass: $out"
for step in worker convert cancel crash-retry crash-twice idle-exit; do assert_contains "$out" "PASS $step"; done
assert_contains "$out" "relaunch 35 ms"
assert_contains "$out" "no worker crash report"
assert_no_file "$(cat "$T/seen")"  # the run's folder is removed

out=$(FAKE_MODE=fail "$ROOT/Scripts/worker-smoke.sh" "$T/Fake.app" 2>&1 || true)
assert_contains "$out" "FAIL cancel: cancel took 400 ms"
assert_fails env FAKE_MODE=fail "$ROOT/Scripts/worker-smoke.sh" "$T/Fake.app"

out=$(FAKE_MODE=short "$ROOT/Scripts/worker-smoke.sh" "$T/Fake.app" 2>&1 || true)
assert_contains "$out" "MISSING crash-twice"

out=$(FAKE_MODE=crash "$ROOT/Scripts/worker-smoke.sh" "$T/Fake.app" 2>&1 || true)
assert_contains "$out" "crash report"
assert_fails env FAKE_MODE=crash "$ROOT/Scripts/worker-smoke.sh" "$T/Fake.app"

assert_fails "$ROOT/Scripts/worker-smoke.sh" "$T/Missing.app"
echo "PASS test-worker-smoke"
