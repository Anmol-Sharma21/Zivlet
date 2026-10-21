#!/usr/bin/env bash
# Shared by build-native.sh and build-rs.sh (sourced; needs OUT set): packaging of static xcframeworks.

# One hash over every file of an xcframework, by relative path, so it does not depend on where it was built.
tree_hash() { (cd "$1" && find . -type f | LC_ALL=C sort | xargs shasum -a 256 | shasum -a 256 | cut -d' ' -f1); }

# Packages one static library with its headers and module map into $OUT/<name>.xcframework and writes
# $OUT/<name>.sha256.
package_xcframework() {
    local name=$1 lib=$2 headers=$3 dest=$OUT/$1.xcframework
    rm -rf "$dest"
    mkdir -p "$OUT"
    xcodebuild -create-xcframework -library "$lib" -headers "$headers" -output "$dest" >/dev/null
    tree_hash "$dest" >"$OUT/$name.sha256"
    echo "$name.xcframework $(cat "$OUT/$name.sha256")"
}
