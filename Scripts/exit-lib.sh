#!/usr/bin/env bash
# Sourced by the exit runners (m5a-exit.sh, m5b-exit.sh, m6-exit.sh): the two lines that make a row a skip, and an
# earlier runner run inside one row of a later one. A skip is not a pass: every runner exits 1 when a row skipped.
SKIPPED_LINE="skipped: screen locked"  # a screenshot script found the screen locked
NOT_JUDGED_LINE="timing: not judged"   # Scripts/timing.sh found the Mac above the load limit (D-M7-3)

# Runs an earlier exit runner ("$@") to the end and prints its lines. Returns 0 when it passed, and also when it
# failed only by SKIP rows (their lines carry the reason, so the calling row is reported as a skip); else 1.
earlier_runner() {
    local out status=0
    out=$("$@" 2>&1) || status=1
    echo "$out"
    ((status == 0)) && return 0
    if grep -qE '^[A-Z][0-9]+ FAIL' <<<"$out" || ! grep -qE '^[A-Z][0-9]+ SKIP' <<<"$out"; then return 1; fi
    echo "an earlier row was skipped, so this row is too"
}
