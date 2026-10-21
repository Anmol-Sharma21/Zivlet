#!/usr/bin/env bash
# Collects the licence texts that ship in Contents/Resources/Licenses (P1-51): one <name>.txt per component in
# Vendor/licenses.json, rust-crates.txt for every crate in zivlet-svg's tree, and an index.html linking them.
# Usage: Scripts/collect-licences.sh        (output: Vendor/out/licenses, or LICENSES_OUT)
set -euo pipefail
source "$(dirname "$0")/env.sh"
MANIFEST=$REPO_ROOT/Vendor/licenses.json
SRC=$REPO_ROOT/Vendor/src; DOWNLOADS=$REPO_ROOT/Vendor/downloads
CARGO_HOME=${ZIVLET_CARGO_HOME:-$REPO_ROOT/Vendor/downloads/cargo-home}
CRATE=$REPO_ROOT/Vendor/rs/zivlet-svg
OUT=${LICENSES_OUT:-$REPO_ROOT/Vendor/out/licenses}
mkdir -p "$OUT"

field() { jq -r --arg n "$1" ".components[] | select(.name == \$n) | .$2" "$MANIFEST"; }
crate_dir() { ls -d "$CARGO_HOME"/registry/src/*/"$1-$2" 2>/dev/null | head -1; }

# Prints one licence file of a component from its source tree, its verified tarball or the cargo registry.
licence_text() {
    local name=$1 version=$2 source=$3 file=$4 archive
    case "$source" in
        src) cat "$SRC/$name-$version/$file" ;;
        tarball)
            archive=$(ls "$DOWNLOADS/$name-$version"/* | head -1)
            tar -xOf "$archive" "$(tar -tf "$archive" | grep -E "(^|/)$file\$" | head -1)"
            ;;
        crate) cat "$(crate_dir "$name" "$version")/$file" ;;
    esac
}

write_component() {
    local name=$1 version source file
    version=$(field "$name" version); source=$(field "$name" source)
    {
        printf '%s %s\nLicence: %s\nShips: %s\nUpstream: %s\n' "$name" "$version" "$(field "$name" spdx)" \
            "$(field "$name" ships)" "$(field "$name" url)"
        while IFS= read -r file; do
            printf '\n===== %s =====\n\n' "$file"
            licence_text "$name" "$version" "$source" "$file"
        done < <(jq -r --arg n "$name" '.components[] | select(.name == $n) | .files[]' "$MANIFEST")
    } >"$OUT/$name.txt"
}

# Every crate linked into CZivletSVG, with the licence files it ships (LICENSE*, COPYING*, NOTICE*).
write_crates() {
    local name version licence dir file
    {
        echo "Rust crates statically linked into Zivlet through zivlet-svg (resvg 0.47.0)."
        while read -r name version licence; do
            [[ "$name" == "zivlet_svg" ]] && continue
            printf '\n######## %s %s (%s) ########\n' "$name" "${version#v}" "$licence"
            dir=$(crate_dir "$name" "${version#v}")
            for file in "$dir"/LICEN[CS]E* "$dir"/COPYING* "$dir"/NOTICE*; do
                [[ -f "$file" ]] || continue
                printf '\n===== %s =====\n\n' "$(basename "$file")"
                cat "$file"
            done
        done < <(cd "$CRATE" && CARGO_HOME=$CARGO_HOME cargo tree --locked --offline -e normal \
            --target aarch64-apple-darwin --prefix none --format '{p} {l}' | sed -e 's/ (\*)$//' -e 's/ (\/[^)]*)//' |
            sort -u)
    } >"$OUT/rust-crates.txt"
}

write_index() {
    local name
    {
        echo '<!doctype html><html><head><meta charset="utf-8"><title>Zivlet acknowledgements</title></head><body>'
        echo '<h1>Third-party software in Zivlet</h1><p>Zivlet is free software under GPL-3.0-or-later.</p><ul>'
        for name in $(jq -r '.components[].name' "$MANIFEST"); do
            printf '<li><a href="%s.txt">%s %s</a> (%s)</li>\n' "$name" "$name" "$(field "$name" version)" \
                "$(field "$name" spdx)"
        done
        echo '<li><a href="rust-crates.txt">Rust crates used by the SVG renderer</a></li></ul></body></html>'
    } >"$OUT/index.html"
}

for name in $(jq -r '.components[].name' "$MANIFEST"); do write_component "$name"; done
write_crates
write_index
echo "collected $(jq '.components | length' "$MANIFEST") licences and the crate list into $OUT"
