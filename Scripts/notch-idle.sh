#!/usr/bin/env bash
# M5a exit row X6: the app's idle CPU per island state, as a difference from a baseline (plan 12 §6, plan 14 D1). Each
# state is one launch: wait for it to settle, sample with idle-cpu.sh, quit. Baseline: "Near the drop" and no job
# (it includes the trigger host, Sparkle and the rest of the app). Then: the island hidden, collapsed and still,
# collapsed with progress input at 10 Hz (drawn at most 4 Hz, D-N7), the stepped glyph, and since the design pass
# (19b §6.3) the working card open and still on glass, and the glass pill with progress; since the design review,
# progress fast enough that the 250 ms floor holds ring steps back, and the pill with the same progress on the solid
# finish. WindowServer's CPU over the same window is printed beside each row, for information (glass is drawn
# there, not in the app); it has no limit. A toast lingers 4 s
# (D-N11), so no still toast can be measured for 120 s; the still card stands in for still glass. These numbers are taken on
# whatever else the Mac is doing; the record says so.
# CONFIG=debug (default) measures make app's Debug build. CONFIG=release builds an optimised app into
# build/NotchIdleRelease with one extra compile condition, ZIVLET_ISLAND_PREVIEW, so the made-up jobs of
# -ZivletIslandPreview exist in it (D-ND3); the shipped Release build never has them (make release-check scans for it).
# Usage: Scripts/notch-idle.sh      ZIVLET_IDLE_SECONDS (default 120) and ZIVLET_IDLE_SETTLE (default 10) override;
#        ZIVLET_IDLE_DRY_RUN=1 prints the plan without building or launching anything. Every line starts with the
#        configuration.
set -euo pipefail
source "$(dirname "$0")/env.sh"
CONFIG=${CONFIG:-debug}
SECONDS_PER_STATE=${ZIVLET_IDLE_SECONDS:-120}
SETTLE=${ZIVLET_IDLE_SETTLE:-10}
DRY_RUN=${ZIVLET_IDLE_DRY_RUN:-0}
RELEASE_DERIVED="$REPO_ROOT/build/NotchIdleRelease"
# shellcheck disable=SC2016 # $(inherited) is for xcodebuild, not the shell
CONDITIONS='$(inherited) ZIVLET_ISLAND_PREVIEW'
case "$CONFIG" in
    debug) APP="$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app" ;;
    release) APP="$RELEASE_DERIVED/Build/Products/Release/Zivlet.app" ;;
    *) echo "error: CONFIG must be debug or release, not $CONFIG" >&2; exit 2 ;;
esac

# name | launch arguments | limit over the baseline in percent (none for the baseline)
STATES=(
    "baseline|-ZivletHUDPlacement nearDrop|"
    "hidden|-ZivletHUDPlacement notch|0.1"
    "collapsed|-ZivletHUDPlacement notch -ZivletIslandPreview collapsed|0.1"
    "progress|-ZivletHUDPlacement notch -ZivletIslandPreview progress|1"
    "indeterminate|-ZivletHUDPlacement notch -ZivletIslandPreview indeterminate|1"
    "card-still|-ZivletHUDPlacement notch -ZivletIslandPreview expanded|0.1"
    "pill-progress|-ZivletHUDPlacement notch -ZivletIslandPreview progress -ZivletIslandPill YES|1"
    "fast-progress|-ZivletHUDPlacement notch -ZivletIslandPreview fastProgress|1"
    "pill-progress-solid|-ZivletHUDPlacement notch -ZivletIslandPreview progress -ZivletIslandPill YES -ZivletIslandFinish solid|1"
)

say() { echo "$CONFIG $*"; }

BUILD=(xcodebuild -project Zivlet.xcodeproj -scheme Zivlet -configuration Release -derivedDataPath "$RELEASE_DERIVED"
    CODE_SIGN_IDENTITY=- "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$CONDITIONS" build)

if [[ "$DRY_RUN" == 1 ]]; then
    if [[ "$CONFIG" == release ]]; then say "build ${BUILD[*]}"; fi
    say "app $APP"
    say "also samples WindowServer over each window (information, no limit)"
    for state in "${STATES[@]}"; do
        IFS='|' read -r name arguments limit <<<"$state"
        say "state $name ${limit:-baseline} $arguments"
    done
    exit 0
fi

# The Release measurement build: its own derived data, never the shipped app's (release-check uses build/ReleaseCheck).
build_release() {
    local log="$RELEASE_DERIVED/xcodebuild.log"
    mkdir -p "$RELEASE_DERIVED"
    cd "$REPO_ROOT"
    /opt/homebrew/bin/xcodegen generate --spec project.yml >/dev/null
    say "building the Release measurement app (log: $log)"
    if ! nice -n 10 "${BUILD[@]}" >"$log" 2>&1; then
        grep -E "error:" "$log" | grep -v -e DVTPlugIn -e CoreSimulator >&2 || true
        echo "error: Release measurement build failed (full log: $log)" >&2
        exit 1
    fi
    # Without the preview the states would all measure an empty island; refuse instead of reporting a false pass.
    if ! LC_ALL=C grep -qaF -- "-ZivletIslandPreview" "$APP/Contents/MacOS/Zivlet"; then
        echo "error: the Release measurement app has no island preview (was ZIVLET_ISLAND_PREVIEW set?)" >&2
        exit 1
    fi
}

if [[ "$CONFIG" == release ]]; then build_release; fi
if [[ ! -d "$APP" ]]; then echo "error: $APP not found; run make app" >&2; exit 1; fi

quit_app() {
    osascript -e 'quit app "Zivlet"' >/dev/null 2>&1 || true
    sleep 2
    pkill -x Zivlet || true
}

# One launch: prints the app's CPU percentage of the state, then WindowServer's over the same window (or "n/a").
sample_state() {
    local pid server app server_file
    quit_app
    # shellcheck disable=SC2086 # the arguments are words on purpose
    open -n "$APP" --args -ZivletRevealResults NO $1
    sleep "$SETTLE"
    pid=$(pgrep -nx Zivlet) || { echo "error: Zivlet did not start" >&2; return 1; }
    server_file=$(mktemp)
    if server=$(pgrep -x WindowServer); then
        "$REPO_ROOT/Scripts/idle-cpu.sh" "$server" "$SECONDS_PER_STATE" >"$server_file" 2>/dev/null &
    fi
    app=$("$REPO_ROOT/Scripts/idle-cpu.sh" "$pid" "$SECONDS_PER_STATE")
    wait || true
    echo "$app $(cat "$server_file" 2>/dev/null || true)"
    rm -f "$server_file"
}

trap quit_app EXIT
say "load average at start: $(sysctl -n vm.loadavg)"
status=0
baseline=""
for state in "${STATES[@]}"; do
    IFS='|' read -r name arguments limit <<<"$state"
    result=$(sample_state "$arguments")
    read -r value server <<<"$result"
    server="WindowServer ${server:-n/a} %"
    if [[ -z "$limit" ]]; then
        baseline=$value
        say "$name $value % ($server)"
        continue
    fi
    verdict=$(awk -v v="$value" -v b="$baseline" -v l="$limit" \
        'BEGIN { d = v - b; printf "%.3f %s", d, (d <= l ? "pass" : "FAIL") }')
    say "$name $value % (over baseline ${verdict% *} %, limit $limit %) ${verdict#* } ($server)"
    [[ "$verdict" == *pass ]] || status=1
done
say "load average at end: $(sysctl -n vm.loadavg)"
exit "$status"
