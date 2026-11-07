#!/usr/bin/env bash
# Sourced by the M7 demo scripts (plan 20g F3): the locked-screen check, the demo's own folder, made-up passwords and
# their 0600 files, the inputs the test bundle renders, the wait for the app's `done`, and reading its JSON reports.
# Passwords live only in this shell's variables and in 0600 files inside the demo's own folder; they reach other
# programs only through those files or stdin (printf is a builtin, so no command line ever holds one).
# Seams for the script tests: ZIVLET_SCREEN_LOCKED=1 (a locked screen), ZIVLET_DEMO_APP (the app), ZIVLET_DEMO_SWIFT
# (the swift that renders the inputs), ZIVLET_DEMO_TIMEOUT (seconds to wait for `done`).
DEMO_APP=${ZIVLET_DEMO_APP:-$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app}
DEMO_SWIFT=${ZIVLET_DEMO_SWIFT:-swift}
DEMO_TIMEOUT=${ZIVLET_DEMO_TIMEOUT:-600}

# True when the screen is locked (or the seam says so): the demos then run nothing.
demo_screen_locked() {
    [[ "${ZIVLET_SCREEN_LOCKED:-}" == 1 ]] && return 0
    [[ -z "${ZIVLET_SCREEN_LOCKED:-}" ]] &&
        ioreg -n Root -d1 -a | grep -A1 -i 'CGSSessionScreenIsLocked' | grep -q '<true/>'
}

# Makes the demo's folder (0700): its default folder, or one it made earlier (marked), or a new or empty one. Any
# other folder with files is refused, so the script deletes only what it made.
demo_folder() {
    local out=$1 default=$2 marker=$3
    [[ "$out" == "$default" && -d "$out" ]] && touch "$out/$marker"
    if [[ -d "$out" && -n "$(ls -A "$out")" && ! -e "$out/$marker" ]]; then
        echo "error: $out holds files this script did not make; give it an empty or new folder" >&2
        return 1
    fi
    if [[ -e "$out/$marker" ]]; then rm -r -f "$out"; fi
    mkdir -p "$out"
    chmod 700 "$out"
    touch "$out/$marker"
}

# A made-up password of 24 letters and digits, new each call. A bounded read, so no reader in the pipe is cut off
# (SIGPIPE would stop a script running with pipefail).
new_password() {
    local raw=""
    while ((${#raw} < 24)); do raw+=$(head -c 256 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9'); done
    printf '%s' "${raw:0:24}"
}

# Writes the given lines to a 0600 file (umask 077, so it is never readable by others even for a moment).
write_secret() {
    local file=$1
    shift
    (umask 077 && printf '%s\n' "$@" >"$file")
    chmod 600 "$file"
}

# Renders a test suite's inputs into a folder: `render_inputs <suite> <VAR> <folder>`, the log in <folder>/inputs.log.
render_inputs() {
    local suite=$1 variable=$2 folder=$3
    (cd "$KIT" && env "$variable=$folder" "$DEMO_SWIFT" test --filter "$suite" >"$folder/inputs.log" 2>&1) ||
        { echo "error: the inputs were not rendered (see $folder/inputs.log)" >&2; return 1; }
}

# Waits for <folder>/done; fails after the timeout.
wait_done() {
    local folder=$1 started=$SECONDS
    until [[ -e "$folder/done" ]] || ((SECONDS - started > DEMO_TIMEOUT)); do sleep 1; done
    [[ -e "$folder/done" ]] || { echo "error: the demo did not finish within $DEMO_TIMEOUT s" >&2; return 1; }
    echo "demo finished in $((SECONDS - started)) s"
}

# A value of a JSON report: `json_value <file> <key path> [raw|json]`.
json_value() { plutil -extract "$2" "${3:-raw}" -o - "$1" 2>/dev/null || true; }

# Fails when a secret file is still in the folder (the app and the inputs suite delete theirs once read).
secrets_gone() {
    local folder=$1 file status=0
    for file in secret inputs-secret; do
        [[ ! -e "$folder/$file" ]] || { echo "FAIL secrets: $file was left in the folder"; status=1; }
    done
    ((status == 0)) && echo "PASS secrets: every secret file was deleted after reading"
    return "$status"
}
