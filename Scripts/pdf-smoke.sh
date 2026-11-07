#!/usr/bin/env bash
# Exit row V6 (plan 20g, D-M7-16): LOCK · UNLOCK in the real XPC worker of the Debug app, on PDFs the test bundle draws
# in our own words: lock, lock with restrictions (a form), unlock, an unlock that needs the owner password, change, a
# wrong password then Cancel, an RC4-40 input unlocked and an AES-128 input given a new password (upgraded to R6).
# The app (-ZivletProtectDemo <folder>) answers each sheet from a 0600 file of made-up passwords it deletes once read.
# While it runs, this script samples the app's and the worker's command lines (`ps -E -ww`) for any of the passwords
# and the worker for child processes (a PDF job spawns none). Then PDFKit (Scripts/pdf-check.swift, passwords on
# stdin) opens each output with the right password and refuses the wrong one, finds the restrictions and the form's
# fields kept, and finds no encryption on unlocked copies. With the screen locked it still runs (no capture). It
# deletes only its default folder or one it made (marked by .zivlet-pdf-smoke), and quits only the app it launched.
# Usage: Scripts/pdf-smoke.sh [folder]        (default build/pdf-smoke; needs `make app`)
#        ZIVLET_PDF_CHECK replaces the checker (script tests).
set -euo pipefail
source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/app-process.sh"
source "$(dirname "$0")/demo-lib.sh"
DEFAULT_OUT=$REPO_ROOT/build/pdf-smoke
OUT=${1:-$DEFAULT_OUT}
PDF_CHECK=${ZIVLET_PDF_CHECK:-xcrun swift $REPO_ROOT/Scripts/pdf-check.swift}
SAMPLE_SECONDS=0.2

STEPS='[
 {"name": "lock", "files": ["Report.pdf"], "answers": [{"newUser": 1}]},
 {"name": "lock-restricted", "files": ["Form.pdf"], "answers": [{"newUser": 1, "owner": 3, "restrict": true}]},
 {"name": "unlock", "files": ["Report Locked.pdf"], "answers": [{"input": 1}]},
 {"name": "unlock-owner", "files": ["Form Locked.pdf"], "answers": [{"input": 1}, {"input": 3}]},
 {"name": "change", "files": ["Report Locked.pdf"], "answers": [{"input": 1, "newUser": 2}]},
 {"name": "wrong", "files": ["Report Locked.pdf"], "answers": [{"input": 0}, {"cancel": true}]},
 {"name": "legacy-rc4", "files": ["Legacy RC4.pdf"], "answers": [{"input": 1}]},
 {"name": "legacy-aes", "files": ["Legacy AES.pdf"], "answers": [{"input": 1, "newUser": 2}]}
]'
# step | sheets asked for | new files
EXPECTED=(
    'lock|["lock"]|["Report Locked.pdf"]'
    'lock-restricted|["lock"]|["Form Locked.pdf"]'
    'unlock|["unlock"]|["Report Unlocked.pdf"]'
    'unlock-owner|["unlock","ownerNeeded"]|["Form Unlocked.pdf"]'
    'change|["unlock"]|*'
    'wrong|["unlock","retry"]|[]'
    'legacy-rc4|["unlock"]|["Legacy RC4 Unlocked.pdf"]'
    'legacy-aes|["unlock"]|["Legacy AES Locked.pdf"]'
)

# Samples the app's and the worker's processes until the demo is done: a password in a command line or a child of
# the worker fails the run. Writes what it saw to $OUT/watch.log.
watch_processes() {
    local samples=0 seen="" pids worker children
    until [[ -e "$OUT/done" ]] || ((SECONDS - WATCH_STARTED > DEMO_TIMEOUT)); do
        worker=$(pgrep -f "$DEMO_APP/Contents/XPCServices/ZivletWorker.xpc/Contents/MacOS/" 2>/dev/null | tr '\n' ' ' || true)
        pids=$(echo "${APP_PID:-} $worker" | xargs)
        if [[ -n "$pids" ]]; then
            samples=$((samples + 1))
            [[ -n "$worker" ]] && seen="$worker"
            if ps -E -ww -o command= -p "${pids// /,}" 2>/dev/null |
                grep -qF -f <(printf '%s\n' "$PASSWORD" "$NEW_PASSWORD" "$OWNER_PASSWORD"); then
                echo "FAIL watch: a password was in the command line or environment of the app or the worker"
                return 1
            fi
            for pid in $worker; do
                children=$(pgrep -P "$pid" 2>/dev/null || true)
                [[ -z "$children" ]] || { echo "FAIL watch: the worker $pid started a child process"; return 1; }
            done
        fi
        sleep "$SAMPLE_SECONDS"
    done
    ((samples > 0)) || { echo "FAIL watch: no app or worker process was seen to sample"; return 1; }
    [[ -n "$seen" ]] || { echo "FAIL watch: no worker process was seen (the jobs must run in ZivletWorker)"; return 1; }
    echo "PASS watch: $samples samples of the app and the worker ($seen): no password, no child process"
}

check_steps() {
    local entry step asked outputs file got status=0
    for entry in "${EXPECTED[@]}"; do
        IFS='|' read -r step asked outputs <<<"$entry"
        file=$OUT/$step.json
        [[ -f "$file" ]] || { echo "FAIL $step: no report"; status=1; continue; }
        got="$(json_value "$file" asked json)|$(json_value "$file" outputs json)"
        [[ "$outputs" != '*' ]] || outputs=$(json_value "$file" outputs json | grep -E '^\["[^"]+"\]$' || echo none)
        if [[ "$got" == "$asked|$outputs" ]]; then echo "PASS $step: $got"; else
            echo "FAIL $step: $got, expected $asked|$outputs"
            status=1
        fi
    done
    return "$status"
}

check_outputs() {
    local changed form=$OUT/Form\ Locked.pdf report=$OUT/Report\ Locked.pdf aes=$OUT/Legacy\ AES\ Locked.pdf
    changed=$OUT/$(json_value "$OUT/change.json" outputs.0)
    {
        printf '%s\n' "$PASSWORD" "$NEW_PASSWORD" "$OWNER_PASSWORD" ''
        printf '%s\t%s\t%s\n' opens "$report" 1 refuses "$report" 0 restricted "$form" 1 owner "$form" 3 \
            refuses "$form" 0 opens "$changed" 2 refuses "$changed" 1 opens "$aes" 2 refuses "$aes" 1
        printf '%s\t%s\t%s\t%s\n' fields "$form" 2 3
        printf '%s\t%s\n' plain "$OUT/Report Unlocked.pdf" plain "$OUT/Form Unlocked.pdf" \
            plain "$OUT/Legacy RC4 Unlocked.pdf"
        printf '%s\t%s\t%s\n' fields "$OUT/Form Unlocked.pdf" 2
    } | $PDF_CHECK
}

[[ -d "$DEMO_APP" ]] || { echo "error: $DEMO_APP not found; run make app" >&2; exit 1; }
demo_folder "$OUT" "$DEFAULT_OUT" .zivlet-pdf-smoke
PASSWORD=$(new_password)
NEW_PASSWORD=$(new_password)
OWNER_PASSWORD=$(new_password)
write_secret "$OUT/inputs-secret" "$PASSWORD"
echo "rendering the inputs into $OUT"
render_inputs ProtectDemoInputTests ZIVLET_PDF_DEMO_DUMP "$OUT"
printf '%s\n' "$STEPS" >"$OUT/steps.json"
write_secret "$OUT/secret" "$PASSWORD" "$NEW_PASSWORD" "$OWNER_PASSWORD"
trap quit_launched EXIT
launch_app "$DEMO_APP" -ZivletRevealResults NO -ZivletProtectDemo "$OUT"
WATCH_STARTED=$SECONDS
status=0
watch_processes || status=1
wait_done "$OUT" || status=1
check_steps || status=1
check_outputs || status=1
secrets_gone "$OUT" || status=1
exit "$status"
