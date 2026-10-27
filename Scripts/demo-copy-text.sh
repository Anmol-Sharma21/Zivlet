#!/usr/bin/env bash
# Exit row Z7 (plan 18d D15): Copy Text through the drop path of the Debug app. The inputs are rendered by the test
# bundle's fixture renderer (fixture 05 as a PNG, the mixed sentence as a CoreText PDF, a blank PNG, and the expected
# texts); the app (-ZivletCopyTextDemo <folder>) runs COPY TEXT on the image and the PDF, then again with Option, then
# on the blank image, using a private pasteboard (the person's clipboard is left alone), writes one JSON file per
# step and quits. The check: the copied text within 1 % CER of the expected combined text (Scripts/cer.swift), each
# "<name> Text.txt" UTF-8 without a BOM and with LF only and within 1 % CER, and "No text found" for the blank image.
# With the screen locked it runs nothing and says "skipped: screen locked".
# Usage: Scripts/demo-copy-text.sh [folder]        (default build/copy-text-demo; needs `make app`)
#        Scripts/demo-copy-text.sh --check folder  only the check, on a finished folder (script tests)
set -euo pipefail
source "$(dirname "$0")/env.sh"
APP="$REPO_ROOT/build/DerivedData/Build/Products/Debug/Zivlet.app"
MAX_CER=0.01
TIMEOUT=${ZIVLET_TEXT_TIMEOUT:-900}  # seconds: a first recognition in a fresh worker may compile the model

value() { plutil -extract "$2" raw -o - "$1" 2>/dev/null || true; }
cer() { xcrun swift "$REPO_ROOT/Scripts/cer.swift" "$1" "$2"; }
within() { awk -v c="$1" -v m="$MAX_CER" 'BEGIN { exit !(c <= m) }'; }

check_text_file() {
    local file=$1 expected=$2 rate name
    name=$(basename "$file")
    [[ -s "$file" ]] || { echo "FAIL option: missing $name"; return 1; }
    if [[ "$(head -c 3 "$file" | xxd -p)" == efbbbf ]]; then
        echo "FAIL option: $name starts with a byte-order mark"
        return 1
    fi
    if LC_ALL=C grep -q $'\r' "$file"; then
        echo "FAIL option: $name has a carriage return"
        return 1
    fi
    iconv -f UTF-8 -t UTF-8 "$file" >/dev/null 2>&1 || { echo "FAIL option: $name is not UTF-8"; return 1; }
    rate=$(cer "$expected" "$file")
    within "$rate" || { echo "FAIL option: $name CER $rate > $MAX_CER"; return 1; }
    echo "  $name: UTF-8, no BOM, LF, CER $rate"
}

check_plain() {
    local dir=$1 rate hypothesis kind
    hypothesis=$(mktemp "${TMPDIR:-/tmp}/zivlet-cer.XXXXXX")
    value "$dir/plain.json" clipboard >"$hypothesis"
    rate=$(cer "$dir/expected.txt" "$hypothesis")
    rm -f "$hypothesis"
    kind=$(value "$dir/plain.json" kind)
    if [[ "$kind" == text ]] && within "$rate"; then
        echo "PASS plain: clipboard CER $rate"
    else
        echo "FAIL plain: kind $kind, clipboard CER $rate (need <= $MAX_CER)"
        return 1
    fi
}

check_option() {
    local dir=$1 first second
    first=$(value "$dir/option.json" saved.0)
    second=$(value "$dir/option.json" saved.1)
    if [[ "$(value "$dir/option.json" kind)" == text ]] && check_text_file "${first:-$dir/none}" "$dir/expected-1.txt" &&
        check_text_file "${second:-$dir/none}" "$dir/expected-2.txt"; then
        echo "PASS option: two text files"
    else
        echo "FAIL option"
        return 1
    fi
}

check_blank() {
    local toast
    toast=$(value "$1/blank.json" toast)
    if [[ "$toast" == "No text found" ]]; then echo "PASS blank: No text found"; else
        echo "FAIL blank: toast '$toast'"
        return 1
    fi
}

check() {
    local status=0
    check_plain "$1" || status=1
    check_option "$1" || status=1
    check_blank "$1" || status=1
    return "$status"
}

if [[ "${1:-}" == --check ]]; then
    check "${2:?--check needs a folder}"
    exit $?
fi
OUT=${1:-$REPO_ROOT/build/copy-text-demo}
locked=${ZIVLET_SCREEN_LOCKED:-}
if [[ -z "$locked" ]] && ioreg -n Root -d1 -a | grep -A1 -i 'CGSSessionScreenIsLocked' | grep -q '<true/>'; then
    locked=1
fi
if [[ "$locked" == 1 ]]; then
    echo "skipped: screen locked (nothing run)"
    exit 0
fi
[[ -d "$APP" ]] || { echo "error: $APP not found; run make app" >&2; exit 1; }
rm -rf "$OUT"
mkdir -p "$OUT"
echo "rendering the inputs into $OUT"
(cd "$KIT" && ZIVLET_OCR_DUMP="$OUT" swift test --filter OCRDemoInputTests >"$OUT/inputs.log" 2>&1) ||
    { echo "error: the inputs were not rendered (see $OUT/inputs.log)" >&2; exit 1; }
quit_app() { osascript -e 'quit app "Zivlet"' >/dev/null 2>&1 || true; }
trap quit_app EXIT
quit_app
started=$SECONDS
open -n "$APP" --args -ZivletRevealResults NO -ZivletCopyTextDemo "$OUT"
until [[ -e "$OUT/done" ]] || ((SECONDS - started > TIMEOUT)); do sleep 1; done
[[ -e "$OUT/done" ]] || { echo "error: the demo did not finish within $TIMEOUT s" >&2; exit 1; }
echo "demo finished in $((SECONDS - started)) s"
check "$OUT"
