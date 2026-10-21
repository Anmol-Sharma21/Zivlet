#!/usr/bin/env bash
# Downloads every source named in Vendor/versions.lock, verifies its SHA-256 and extracts it (P0-36, 04 §6).
# Usage: Vendor/fetch.sh [--lock FILE] [--downloads DIR] [--src DIR] [--only NAME]
# Each tarball lands in its own directory <downloads>/<name>-<version>/ and is extracted into a fresh
# <src>/<name>-<version>/. Nothing downloaded is executed here; bsdtar refuses absolute and `..` member paths.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOCK=$ROOT/Vendor/versions.lock; DOWNLOADS=$ROOT/Vendor/downloads; SRC=$ROOT/Vendor/src; ONLY=""
NOT_EXTRACTED=" sparkle "   # the app uses Sparkle's SwiftPM binary; the tarball only provides release tools

while (( $# )); do
    case "$1" in
        --lock) LOCK=$2; shift 2 ;;
        --downloads) DOWNLOADS=$2; shift 2 ;;
        --src) SRC=$2; shift 2 ;;
        --only) ONLY=$2; shift 2 ;;
        *) echo "error: unknown argument $1" >&2; exit 2 ;;
    esac
done

sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

# Exits 2 naming the line when a lock line is malformed, so a typo can never select another path or URL.
validate_line() {
    local n=$1 name=$2 version=$3 url=$4 hash=$5 extra=$6
    [[ -z "$extra" && -n "$hash" ]] || { echo "error: $LOCK:$n: expected 4 fields" >&2; exit 2; }
    [[ "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { echo "error: $LOCK:$n: bad name [$name]" >&2; exit 2; }
    [[ "$version" =~ ^[A-Za-z0-9._-]+$ && "$version" != *..* ]] ||
        { echo "error: $LOCK:$n: bad version [$version]" >&2; exit 2; }
    [[ "$url" =~ ^(https|file)://[^[:space:]]+$ ]] || { echo "error: $LOCK:$n: URL must be https" >&2; exit 2; }
    [[ "$hash" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "error: $LOCK:$n: bad hash [$hash]" >&2; exit 2; }
}

# Downloads into a partial file and keeps it only when the hash matches.
download() {
    local name=$1 version=$2 url=$3 want=$4 dir file
    dir=$DOWNLOADS/$name-$version; file=$dir/$(basename "${url%%\?*}")
    mkdir -p "$dir"
    if [[ -f "$file" && "$(sha256_of "$file")" == "$want" ]]; then echo "$name $version cached"; return; fi
    rm -f "$file" "$file.part"
    curl -fsSL --retry 3 --proto '=https,file' -o "$file.part" "$url" ||
        { rm -f "$file.part"; echo "error: download failed for $name $version" >&2; exit 1; }
    local got; got=$(sha256_of "$file.part")
    if [[ "$got" != "$want" ]]; then
        rm -f "$file.part"
        echo "error: SHA-256 mismatch for $name $version: expected $want, got $got" >&2
        exit 1
    fi
    mv "$file.part" "$file"
    echo "$name $version verified"
}

# Extracts into a temporary sibling, then renames, so a half-extracted tree never looks complete.
extract() {
    local name=$1 version=$2 file=$3 want=$4 dest tmp
    dest=$SRC/$name-$version
    if [[ -f "$dest/.zivlet-sha256" && "$(cat "$dest/.zivlet-sha256")" == "$want" ]]; then return; fi
    mkdir -p "$SRC"; rm -rf "$dest"
    tmp=$(mktemp -d "$SRC/.extract.XXXXXX")
    tar -xf "$file" -C "$tmp" --strip-components 1 || { rm -rf "$tmp"; echo "error: cannot extract $file" >&2; exit 1; }
    echo "$want" > "$tmp/.zivlet-sha256"
    mv "$tmp" "$dest"
}

[[ -f "$LOCK" ]] || { echo "error: lock file $LOCK not found" >&2; exit 2; }
n=0; count=0
while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    read -r name version url hash extra <<<"$line"
    validate_line "$n" "$name" "$version" "$url" "${hash:-}" "${extra:-}"
    [[ -n "$ONLY" && "$name" != "$ONLY" ]] && continue
    want=${hash#sha256:}
    download "$name" "$version" "$url" "$want"
    count=$((count + 1))
    [[ "$NOT_EXTRACTED" == *" $name "* ]] && continue
    extract "$name" "$version" "$DOWNLOADS/$name-$version/$(basename "${url%%\?*}")" "$want"
done <"$LOCK"
echo "fetch: $count component(s) verified"
