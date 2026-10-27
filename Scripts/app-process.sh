#!/usr/bin/env bash
# Sourced by the M6 demo scripts: launches the Debug app as a new instance and quits only that instance, never a
# Zivlet the owner (or another run) has open. `launch_app <app> <args...>` runs `open -n` and records the new
# process in APP_PID (the app's executable before and after the launch); `quit_launched` sends that process
# SIGTERM and waits for it to end. When no new process shows (a stand-in `open` in the script tests), APP_PID stays
# empty and quitting does nothing. ZIVLET_APP_PID_POLLS sets how many 0.1 s polls the launch waits (default 30).
APP_PID=""

app_pids() { pgrep -f "$1/Contents/MacOS/" 2>/dev/null | sort || true; }

launch_app() {
    local app=$1 before after
    shift
    before=$(app_pids "$app")
    open -n "$app" --args "$@"
    for _ in $(seq 1 "${ZIVLET_APP_PID_POLLS:-30}"); do
        after=$(app_pids "$app")
        APP_PID=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep -m1 . || true)
        [[ -n "$APP_PID" ]] && return 0
        sleep 0.1
    done
    return 0
}

quit_launched() {
    [[ -n "$APP_PID" ]] || return 0
    kill -TERM "$APP_PID" 2>/dev/null || true
    for _ in $(seq 1 30); do
        kill -0 "$APP_PID" 2>/dev/null || break
        sleep 0.1
    done
    APP_PID=""
}
