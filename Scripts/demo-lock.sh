#!/usr/bin/env bash
# Exit row V8 (plan 20g F3): LOCK · UNLOCK through the drop path of the Debug app. The test bundle draws Report.pdf in
# our own words; the app (-ZivletProtectDemo <folder>) locks it, unlocks the locked copy, changes its password, and
# tries a wrong password then Cancel, with a scripted prompter that reads the made-up passwords from a 0600 file it
# deletes once read. The check: each step asked for the right sheets and wrote the right file, and PDFKit
# (Scripts/pdf-check.swift, passwords on stdin) opens each output with the right password and refuses the wrong one;
# the unlocked copy has no encryption; after Change the new password opens it and the old one does not; every secret
# file is gone. With the screen locked it runs nothing and says "skipped: screen locked". It deletes only its default
# folder or one it made (marked by .zivlet-lock-demo), and quits only the app it launched.
# Usage: Scripts/demo-lock.sh [folder]        (default build/lock-demo; needs `make app`)
#        ZIVLET_PDF_CHECK replaces the checker (script tests).
set -euo pipefail
source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/app-process.sh"
source "$(dirname "$0")/demo-lib.sh"
DEFAULT_OUT=$REPO_ROOT/build/lock-demo
OUT=${1:-$DEFAULT_OUT}
PDF_CHECK=${ZIVLET_PDF_CHECK:-xcrun swift $REPO_ROOT/Scripts/pdf-check.swift}

STEPS='[
 {"name": "lock", "files": ["Report.pdf"], "answers": [{"newUser": 1}]},
 {"name": "unlock", "files": ["Report Locked.pdf"], "answers": [{"input": 1}]},
 {"name": "change", "files": ["Report Locked.pdf"], "answers": [{"input": 1, "newUser": 2}]},
 {"name": "wrong", "files": ["Report Locked.pdf"], "answers": [{"input": 0}, {"cancel": true}]}
]'

# One step's report: the sheets asked for and the new files, as JSON arrays.
expect_step() {
    local step=$1 asked=$2 outputs=$3 file=$OUT/$1.json got
    [[ -f "$file" ]] || { echo "FAIL $step: no report"; return 1; }
    got="$(json_value "$file" asked json) $(json_value "$file" outputs json)"
    if [[ "$got" == "$asked $outputs" ]]; then echo "PASS $step: $got"; else
        echo "FAIL $step: $got, expected $asked $outputs"
        return 1
    fi
}

check() {
    local status=0 changed
    expect_step lock '["lock"]' '["Report Locked.pdf"]' || status=1
    expect_step unlock '["unlock"]' '["Report Unlocked.pdf"]' || status=1
    changed=$(json_value "$OUT/change.json" outputs.0)
    expect_step change '["unlock"]' "[\"${changed:-none}\"]" || status=1
    expect_step wrong '["unlock","retry"]' '[]' || status=1
    [[ -n "$changed" ]] || return 1
    {
        printf '%s\n' "$PASSWORD" "$NEW_PASSWORD" ''
        printf '%s\t%s\t%s\n' opens "$OUT/Report Locked.pdf" 1 refuses "$OUT/Report Locked.pdf" 0 \
            opens "$OUT/$changed" 2 refuses "$OUT/$changed" 1 refuses "$OUT/$changed" 0
        printf '%s\t%s\n' plain "$OUT/Report Unlocked.pdf"
    } | $PDF_CHECK || status=1
    secrets_gone "$OUT" || status=1
    return "$status"
}

if demo_screen_locked; then
    echo "skipped: screen locked (nothing run)"
    exit 0
fi
[[ -d "$DEMO_APP" ]] || { echo "error: $DEMO_APP not found; run make app" >&2; exit 1; }
demo_folder "$OUT" "$DEFAULT_OUT" .zivlet-lock-demo
PASSWORD=$(new_password)
NEW_PASSWORD=$(new_password)
write_secret "$OUT/inputs-secret" "$PASSWORD"
echo "rendering the input into $OUT"
render_inputs ProtectDemoInputTests ZIVLET_PDF_DEMO_DUMP "$OUT"
printf '%s\n' "$STEPS" >"$OUT/steps.json"
write_secret "$OUT/secret" "$PASSWORD" "$NEW_PASSWORD"
trap quit_launched EXIT
launch_app "$DEMO_APP" -ZivletRevealResults NO -ZivletProtectDemo "$OUT" -ZivletProtectDemoPause 300
wait_done "$OUT"
check
