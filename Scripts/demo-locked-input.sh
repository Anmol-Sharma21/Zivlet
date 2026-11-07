#!/usr/bin/env bash
# Exit row V10 (plan 20g F3, P2-107): a locked PDF in COPY TEXT through the drop path of the Debug app. The test
# bundle draws Locked.pdf (two pages of our own words, AES-128) and the text Copy Text must copy; the app
# (-ZivletLockedInputDemo <folder>) runs Copy Text on it, a scripted prompter answers the one Open sheet from a
# 0600 file it deletes once read, and the text goes to a private pasteboard. The check: exactly one Open sheet was asked
# for, the result is text, the copied text is within 1 % CER of the expected text (Scripts/cer.swift), and every
# secret file is gone. With the screen locked it runs nothing and says "skipped: screen locked". It deletes only its
# default folder or one it made (marked by .zivlet-locked-input-demo); the app quits itself after the run.
# Usage: Scripts/demo-locked-input.sh [folder]   (default build/locked-input-demo; needs `make app`)
#        ZIVLET_CER replaces the CER tool (script tests).
set -euo pipefail
source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/app-process.sh"
source "$(dirname "$0")/demo-lib.sh"
DEFAULT_OUT=$REPO_ROOT/build/locked-input-demo
OUT=${1:-$DEFAULT_OUT}
CER=${ZIVLET_CER:-xcrun swift $REPO_ROOT/Scripts/cer.swift}
MAX_CER=0.01

check() {
    local report=$OUT/locked.json asked kind rate status=0
    [[ -f "$report" ]] || { echo "FAIL locked: no report"; return 1; }
    asked=$(json_value "$report" asked json)
    kind=$(json_value "$report" kind)
    json_value "$report" clipboard >"$OUT/clipboard.txt"
    rate=$($CER "$OUT/expected.txt" "$OUT/clipboard.txt")
    if [[ "$asked" == '["open"]' && "$kind" == text ]] && awk -v c="$rate" -v m="$MAX_CER" 'BEGIN { exit !(c <= m) }'
    then
        echo "PASS locked: one sheet, then the text with CER $rate"
    else
        echo "FAIL locked: sheets $asked, kind $kind, CER $rate (need <= $MAX_CER)"
        status=1
    fi
    secrets_gone "$OUT" || status=1
    return "$status"
}

if demo_screen_locked; then
    echo "skipped: screen locked (nothing run)"
    exit 0
fi
[[ -d "$DEMO_APP" ]] || { echo "error: $DEMO_APP not found; run make app" >&2; exit 1; }
demo_folder "$OUT" "$DEFAULT_OUT" .zivlet-locked-input-demo
PASSWORD=$(new_password)
write_secret "$OUT/inputs-secret" "$PASSWORD"
echo "rendering the input into $OUT"
render_inputs ToolDemoInputTests ZIVLET_LOCKED_TEXT_DUMP "$OUT"
write_secret "$OUT/secret" "$PASSWORD"
trap quit_launched EXIT
launch_app "$DEMO_APP" -ZivletRevealResults NO -ZivletLockedInputDemo "$OUT"
wait_done "$OUT"
check
