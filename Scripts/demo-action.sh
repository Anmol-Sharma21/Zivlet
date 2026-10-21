#!/usr/bin/env bash
# Debug-build end-to-end check without a drag (C7): run one action on one item, then check its effect.
# Usage: Scripts/demo-action.sh /abs/path <copyTo|copyFilePath|openInTerminal> [YES]
# The third argument holds Option (shell-quoted Copy Path). Needs `make app` first. Copy and Copy Path replace
# what is on the clipboard; Terminal opens a window in the item's folder.
source "$(dirname "$0")/env.sh"
USAGE="usage: demo-action.sh /abs/path <copyTo|copyFilePath|openInTerminal> [YES]"
ITEM="${1:?$USAGE}"
ACTION="${2:?$USAGE}"
OPTION="${3:-NO}"
APP="$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app"
if [[ ! -d "$APP" ]]; then echo "error: $APP not found; run make app" >&2; exit 1; fi
if [[ ! -e "$ITEM" ]]; then echo "error: $ITEM does not exist" >&2; exit 1; fi
pkill -x Zivlet || true
START="$(date '+%Y-%m-%d %H:%M:%S')"
open -n "$APP" --args -ZivletDemoAction "$ITEM" "$ACTION" -ZivletDemoOption "$OPTION"
LINE=""
for _ in $(seq 1 60); do
    LINE="$(/usr/bin/log show --start "$START" --style compact \
        --predicate 'subsystem == "app.zivlet.Zivlet" AND eventMessage BEGINSWITH "Action finished"' |
        grep -o 'Action finished: .*' | tail -1 || true)"
    if [[ -n "$LINE" ]]; then break; fi
    sleep 0.5
done
pkill -x Zivlet || true
if [[ -z "$LINE" ]]; then echo "error: no 'Action finished' log line within 30 s" >&2; exit 1; fi
echo "$LINE"
if [[ "$LINE" != *" done: "* ]]; then echo "error: the action did not succeed" >&2; exit 1; fi
case "$ACTION" in
    copyFilePath)
        EXPECTED="$ITEM"
        if [[ "$OPTION" == "YES" ]]; then EXPECTED="'$(printf '%s' "$ITEM" | sed "s/'/'\\\\''/g")'"; fi
        GOT="$(pbpaste)"
        if [[ "$GOT" != "$EXPECTED" ]]; then echo "error: pasteboard holds '$GOT', expected '$EXPECTED'" >&2; exit 1; fi
        echo "OK: pasteboard holds $GOT"
        ;;
    copyTo)
        GOT="$(osascript -e 'POSIX path of (the clipboard as «class furl»)')"
        if [[ "${GOT%/}" != "${ITEM%/}" ]]; then echo "error: pasteboard file is '$GOT'" >&2; exit 1; fi
        echo "OK: pasteboard holds the file $GOT"
        ;;
    *) echo "OK: $ACTION ran" ;;
esac
