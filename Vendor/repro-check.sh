#!/usr/bin/env bash
# Reproducibility check for the media stage (P0-37, 11a §6.6): builds it twice in two clean work trees at
# different paths, compares the SHA-256 of every staged Mach-O and prints a table. Exits 1 on a difference unless
# the file is listed in Vendor/repro-known.txt with a reason. Takes about two clean media builds (~5 min).
# Usage: Vendor/repro-check.sh [--keep]     --keep leaves both work trees under Vendor/build for inspection.
set -euo pipefail
source "$(dirname "$0")/../Scripts/env.sh" # DEVELOPER_DIR: the same Xcode for every build and key
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KNOWN=$ROOT/Vendor/repro-known.txt
KEEP=${1:-}
mkdir -p "$ROOT/Vendor/build"
A=$(mktemp -d "$ROOT/Vendor/build/repro-a.XXXXXX")
B=$(mktemp -d "$ROOT/Vendor/build/repro-second-tree.XXXXXX") # a different path length on purpose
cleanup() { if [[ "$KEEP" != "--keep" ]]; then rm -rf "$A" "$B"; fi; }
trap cleanup EXIT

build_tree() {
    local work=$1
    "$ROOT/Vendor/fetch.sh" --src "$work/src" >/dev/null
    ZIVLET_VENDOR_WORK=$work "$ROOT/Vendor/build-media.sh" >/dev/null
    ZIVLET_VENDOR_WORK=$work "$ROOT/Vendor/stage-media.sh" >/dev/null
}

# A listed file needs a reason: "<path relative to the stage> <reason...>".
known_reason() { awk -v f="$1" '$1 == f { $1 = ""; sub(/^ /, ""); print; exit }' "$KNOWN"; }

echo "building tree 1 in $A"; build_tree "$A"
echo "building tree 2 in $B"; build_tree "$B"

status=0
printf '%-36s %-16s %-16s %s\n' FILE TREE-1 TREE-2 RESULT
while IFS= read -r rel; do
    one=$(shasum -a 256 "$A/out/media-stage/$rel" | cut -c1-16)
    two=$(shasum -a 256 "$B/out/media-stage/$rel" 2>/dev/null | cut -c1-16 || echo missing)
    result=identical
    if [[ "$one" != "$two" ]]; then
        reason=$(known_reason "$rel")
        if [[ -n "$reason" ]]; then result="differs (known: $reason)"; else result=DIFFERS; status=1; fi
    fi
    printf '%-36s %-16s %-16s %s\n' "$rel" "$one" "$two" "$result"
done < <(cd "$A/out/media-stage" && find Helpers Frameworks -type f | LC_ALL=C sort)
if ((status)); then echo "repro-check: unexplained differences (compare with --keep, then fix or list in $KNOWN)" >&2; fi
exit "$status"
