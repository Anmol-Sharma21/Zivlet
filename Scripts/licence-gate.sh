#!/usr/bin/env bash
# Licence gate (P1-51, 10 §10.2). Fails when a lock entry has no manifest entry or the reverse (cargo crates live
# only in the manifest), a version differs, a licence is not on the allow-list, a licence file is missing, a crate
# in zivlet-svg's tree has a licence off the list, or the built ffmpeg reports a nonfree configuration.
# Usage: Scripts/licence-gate.sh [--lock F] [--manifest F] [--src DIR] [--downloads DIR] [--ffmpeg PATH]
set -euo pipefail
source "$(dirname "$0")/env.sh"
LOCK=$REPO_ROOT/Vendor/versions.lock; MANIFEST=$REPO_ROOT/Vendor/licenses.json
SRC=$REPO_ROOT/Vendor/src; DOWNLOADS=$REPO_ROOT/Vendor/downloads
FFMPEG=$REPO_ROOT/Vendor/out/media-stage/Helpers/ffmpeg
CARGO_HOME=${ZIVLET_CARGO_HOME:-$REPO_ROOT/Vendor/downloads/cargo-home}
ALLOWED=" GPL-2.0-or-later GPL-3.0-or-later LGPL-2.0-or-later LGPL-2.1-or-later BSD-2-Clause BSD-3-Clause
BSD-3-Clause-Clear ISC MIT Apache-2.0 Zlib WTFPL MPL-2.0 LicenseRef-AOM-Patent-1.0 "
ALLOWED=" ${ALLOWED//$'\n'/ } " # one line, so every id is surrounded by spaces
while (($#)); do
    case "$1" in
        --lock) LOCK=$2 ;; --manifest) MANIFEST=$2 ;; --src) SRC=$2 ;; --downloads) DOWNLOADS=$2 ;;
        --ffmpeg) FFMPEG=$2 ;;
        *) echo "error: unknown argument $1" >&2; exit 2 ;;
    esac
    shift 2
done
problems=0
problem() { echo "licence-gate: $*" >&2; problems=1; }

# An SPDX expression is allowed when every AND term has at least one allowed OR alternative ("/" is an old OR).
allowed() {
    local term alternative ok
    local expression=${1//\// OR }
    while IFS= read -r term; do
        ok=0
        for alternative in ${term// OR / }; do
            alternative=${alternative//[()]/}
            [[ "$ALLOWED" == *" $alternative "* ]] && ok=1
        done
        ((ok)) || return 1
    done <<<"${expression// AND /$'\n'}"
}

lock_entries() { awk '!/^[[:space:]]*(#|$)/ { print $1, $2 }' "$LOCK"; }
manifest_field() { jq -r --arg n "$1" ".components[] | select(.name == \$n) | .$2" "$MANIFEST"; }

# The licence file of one component, wherever its source keeps it.
has_licence_file() {
    local name=$1 version=$2 source=$3 file=$4
    case "$source" in
        src) [[ -s "$SRC/$name-$version/$file" ]] ;;
        tarball) tar -tf "$(ls "$DOWNLOADS/$name-$version"/* | head -1)" 2>/dev/null | grep -qE "(^|/)$file\$" ;;
        crate) ls "$CARGO_HOME"/registry/src/*/"$name-$version/$file" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

check_component() {
    local name=$1 version=$2 spdx source file
    if [[ -z "$(manifest_field "$name" name)" ]]; then problem "no licence entry for $name"; return; fi
    [[ "$(manifest_field "$name" version)" == "$version" ]] || problem "version of $name differs from the lock"
    spdx=$(manifest_field "$name" spdx); source=$(manifest_field "$name" source)
    allowed "$spdx" || problem "licence not allowed: $name ($spdx)"
    while IFS= read -r file; do
        has_licence_file "$name" "$version" "$source" "$file" || problem "licence file missing for $name: $file"
    done < <(jq -r --arg n "$name" '.components[] | select(.name == $n) | .files[]' "$MANIFEST")
}

check_crates() {
    local line count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        allowed "${line#* * }" || problem "crate licence not allowed: $line"
        count=$((count + 1))
    done < <("$REPO_ROOT/Scripts/crates.sh" 2>/dev/null)
    ((count > 0)) || problem "cargo tree listed no crates (run Vendor/build-rs.sh once to fetch them)"
    CRATES=$count
}

CRATES=0
while read -r name version; do check_component "$name" "$version"; done < <(lock_entries)
while IFS=$'\t' read -r name version; do
    lock_entries | grep -qx "$name $version" || problem "no lock entry for $name $version"
done < <(jq -r '.components[] | select(.source != "crate") | [.name, .version] | @tsv' "$MANIFEST")
components=$(jq '.components | length' "$MANIFEST")
for crate in $(jq -r '.components[] | select(.source == "crate") | .name' "$MANIFEST"); do
    check_component "$crate" "$(manifest_field "$crate" version)"
done
check_crates
if [[ -x "$FFMPEG" ]]; then
    if "$FFMPEG" -hide_banner -buildconf 2>&1 | grep -q nonfree; then problem "ffmpeg was configured with nonfree"; fi
else
    problem "no built ffmpeg at $FFMPEG (run make vendor)"
fi
if ((problems)); then exit 1; fi
echo "Licences OK: $components components, $CRATES crates in zivlet-svg's tree"
