#!/usr/bin/env bash
# demo-copy-text.sh (plan 18d D15, exit row Z7): the Debug app runs Copy Text through the drop path on a rendered
# image and PDF, plainly and with Option, then on a blank image, and writes one JSON file per step. Here the check
# runs on canned folders (no app): a good run passes; a high CER, a BOM, a CR, a missing "No text found" and a
# missing .txt fail; a locked screen is skipped, not passed.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$ROOT/Scripts/demo-copy-text.sh
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
grep -q '^copy-text-demo:' "$ROOT/Makefile" || fail "Makefile has no copy-text-demo target"

# A canned run: what the app and the input renderer would leave in the folder.
canned() {
    local dir=$1 clipboard=$2 option_text=$3 blank_toast=$4
    mkdir -p "$dir"
    printf 'Train का टिकट book कर दिया है,\nplatform नंबर 4 पर मिलना।\n' >"$dir/expected-1.txt"
    printf 'Train का टिकट book कर दिया है,\nplatform नंबर 4 पर मिलना।\n' >"$dir/expected-2.txt"
    printf '%s' "$clipboard" >"$dir/expected.txt"
    printf '%s' "$option_text" >"$dir/05_mixed Text.txt"
    printf '%s' "$option_text" >"$dir/mixed Text.txt"
    json() { printf '{"kind":"%s","toast":"%s","clipboard":"%s","saved":[%s]}' "$1" "$2" "$3" "$4"; }
    json text "Text copied" "$(sed 's/$/\\n/' <"$dir/expected.txt" | tr -d '\n')" "" >"$dir/plain.json"
    json text "Text copied" "" "\"$dir/05_mixed Text.txt\",\"$dir/mixed Text.txt\"" >"$dir/option.json"
    json done "$blank_toast" "" "" >"$dir/blank.json"
    touch "$dir/done"
}
good_text=$'Train का टिकट book कर दिया है,\nplatform नंबर 4 पर मिलना।\n'
combined=$'— 05_mixed.png —\nTrain का टिकट book कर दिया है,\nplatform नंबर 4 पर मिलना।\n\n— mixed.pdf —\nTrain का टिकट book कर दिया है,\nplatform नंबर 4 पर मिलना।\n'

canned "$T/good" "$combined" "$good_text" "No text found"
out=$("$SCRIPT" --check "$T/good" 2>&1) || fail "a good run must pass: $out"
assert_contains "$out" "PASS plain"
assert_contains "$out" "PASS option"
assert_contains "$out" "PASS blank"

canned "$T/cer" "$combined" "$good_text" "No text found"
printf '{"kind":"text","toast":"Text copied","clipboard":"Tran ka tikat","saved":[]}' >"$T/cer/plain.json"
assert_fails "$SCRIPT" --check "$T/cer"

canned "$T/bom" "$combined" $'\xEF\xBB\xBF'"$good_text" "No text found"
out=$("$SCRIPT" --check "$T/bom" 2>&1 || true)
assert_contains "$out" "byte-order mark"

canned "$T/cr" "$combined" $'Train का टिकट book कर दिया है,\r\nplatform नंबर 4 पर मिलना।\r\n' "No text found"
out=$("$SCRIPT" --check "$T/cr" 2>&1 || true)
assert_contains "$out" "carriage return"

canned "$T/blank" "$combined" "$good_text" "Text copied"
assert_fails "$SCRIPT" --check "$T/blank"

canned "$T/missing" "$combined" "$good_text" "No text found"
rm "$T/missing/mixed Text.txt"
assert_fails "$SCRIPT" --check "$T/missing"

# A folder with files the script did not make is refused and left as it was (the script deletes only its own).
mkdir -p "$T/foreign"
echo "keep me" >"$T/foreign/notes.txt"
assert_fails "$SCRIPT" "$T/foreign"
assert_eq "$(cat "$T/foreign/notes.txt")" "keep me" "a foreign folder is left alone"
grep -q 'osascript' "$SCRIPT" && fail "the demo must not quit every Zivlet by name"

out=$(ZIVLET_SCREEN_LOCKED=1 "$SCRIPT" "$T/locked" 2>&1) || fail "a locked screen is skipped, not failed"
assert_contains "$out" "skipped: screen locked"
assert_no_file "$T/locked/plain.json"
echo "PASS test-copy-text-demo"
