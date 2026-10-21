#!/usr/bin/env bash
# Size gate (P1-52): prints the installed size of the app with its parts, and the DMG size when given. Fails above
# SIZE_HARD_MB (85) installed or DMG_HARD_MB (40); warns above SIZE_WARN_MB (70) or DMG_WARN_MB (32). MB = 10^6
# bytes of apparent size (what a copy out of the DMG occupies).
# Usage: Scripts/size-gate.sh <Zivlet.app> [Zivlet.dmg]
set -euo pipefail
APP=${1:?usage: size-gate.sh <app> [dmg]}
DMG=${2:-}
SIZE_HARD_MB=${SIZE_HARD_MB:-85}; SIZE_WARN_MB=${SIZE_WARN_MB:-70}
DMG_HARD_MB=${DMG_HARD_MB:-40}; DMG_WARN_MB=${DMG_WARN_MB:-32}
[[ -d "$APP/Contents" ]] || { echo "size-gate: $APP is not an app bundle" >&2; exit 1; }
status=0

# Apparent size in bytes of a file or directory (0 when absent).
bytes() { if [[ -e "$1" ]]; then echo $(($(du -skA "$1" | cut -f1) * 1024)); else echo 0; fi; }
mb() { awk -v b="$1" 'BEGIN { printf "%.1f", b / 1000000 }'; }

# Compares against the limits: exit status 1 above hard, a warning above warn.
judge() {
    local label=$1 size=$2 hard=$3 warn=$4
    if ((size > hard * 1000000)); then
        echo "size-gate: $label $(mb "$size") MB is over the $hard MB limit" >&2
        status=1
    elif ((size > warn * 1000000)); then
        echo "warning: $label $(mb "$size") MB is over the $warn MB warning line"
    fi
}

total=$(bytes "$APP")
libav=0
for lib in "$APP"/Contents/Frameworks/lib*.dylib; do [[ -f "$lib" ]] && libav=$((libav + $(bytes "$lib"))); done
printf '%-28s %8s MB\n' "Zivlet.app (installed)" "$(mb "$total")" \
    "  Contents/MacOS" "$(mb "$(bytes "$APP/Contents/MacOS")")" \
    "  Contents/Helpers" "$(mb "$(bytes "$APP/Contents/Helpers")")" \
    "  Frameworks/libav*" "$(mb "$libav")" \
    "  Frameworks/Sparkle" "$(mb "$(bytes "$APP/Contents/Frameworks/Sparkle.framework")")" \
    "  Contents/Resources" "$(mb "$(bytes "$APP/Contents/Resources")")"
judge "installed size" "$total" "$SIZE_HARD_MB" "$SIZE_WARN_MB"
if [[ -n "$DMG" ]]; then
    [[ -f "$DMG" ]] || { echo "size-gate: $DMG not found" >&2; exit 1; }
    dmg_size=$(stat -f %z "$DMG")
    printf '%-28s %8s MB\n' "$(basename "$DMG")" "$(mb "$dmg_size")"
    judge "DMG size" "$dmg_size" "$DMG_HARD_MB" "$DMG_WARN_MB"
fi
if ((status)); then exit 1; fi
echo "Size OK (limits: ${SIZE_HARD_MB} MB installed, ${DMG_HARD_MB} MB DMG)"
