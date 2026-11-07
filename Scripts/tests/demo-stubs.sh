#!/usr/bin/env bash
# Sourced by the M7 demo script tests (plan 20g F3): stand-ins on PATH for `open` (the app), `swift` (the input
# renderer), `screencapture` and the log reader, each recording its command line in $T/argv.log, so a test can show
# that no password was ever on a command line. The app's behaviour is the test's own script, $T/fake-app, run with
# the launch arguments; FAKE_NO_PNG=1 makes screencapture write nothing.
# Usage: T=$(tmpdir); stub_bin "$T"; then run the demo with PATH=$T/bin:$PATH ZIVLET_DEMO_APP=$T/Zivlet.app
#        ZIVLET_DEMO_SWIFT=$T/bin/swift ZIVLET_SCREEN_LOCKED=0.
stub_bin() {
    local T=$1
    mkdir -p "$T/bin" "$T/Zivlet.app/Contents/MacOS"
    : >"$T/argv.log"
    cat >"$T/bin/open" <<EOF
#!/usr/bin/env bash
echo "open \$*" >>"$T/argv.log"
shift 3  # -n <app> --args
exec "$T/fake-app" "\$@"
EOF
    # The renderer: deletes the inputs' secret file as the suites do, writes the files FAKE_INPUTS names, and the
    # expected result FAKE_EXPECTED_TEXT as FAKE_EXPECTED_NAME.
    cat >"$T/bin/swift" <<EOF
#!/usr/bin/env bash
echo "swift \$*" >>"$T/argv.log"
folder=\${ZIVLET_PDF_DEMO_DUMP:-\${ZIVLET_QR_DUMP:-\${ZIVLET_LOCKED_TEXT_DUMP:-}}}
[[ -n "\$folder" ]] || exit 1
rm -f "\$folder/inputs-secret"
for name in \${FAKE_INPUTS:-}; do mkdir -p "\$(dirname "\$folder/\$name")"; echo input >"\$folder/\$name"; done
[[ -z "\${FAKE_EXPECTED_NAME:-}" ]] || printf '%s\n' "\$FAKE_EXPECTED_TEXT" >"\$folder/\$FAKE_EXPECTED_NAME"
exit 0
EOF
    cat >"$T/bin/screencapture" <<EOF
#!/usr/bin/env bash
echo "screencapture \$*" >>"$T/argv.log"
[[ "\${FAKE_NO_PNG:-}" == 1 ]] && exit 0
printf 'png' >"\${@: -1}"
EOF
    cat >"$T/bin/fake-log" <<EOF
#!/usr/bin/env bash
echo "log \$*" >>"$T/argv.log"
printf '%s\n' "\${FAKE_LOG_OUTPUT:-}"
EOF
    chmod +x "$T/bin/"*
}

# The value after a flag in the fake app's arguments: `flag_value <flag> "$@"`.
flag_value() {
    local flag=$1
    shift
    while (($#)); do
        [[ "$1" == "$flag" ]] && { echo "$2"; return 0; }
        shift
    done
    return 1
}

# Fails when any line of the secret file (kept by the test before the app deletes it) is in a recorded command line.
assert_no_password_in_argv() {
    local secrets=$1 log=$2 line
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        if grep -qF -- "$line" "$log"; then fail "a password was on a command line: $(grep -F -- "$line" "$log")"; fi
    done <"$secrets"
}
