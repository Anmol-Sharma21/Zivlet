#!/usr/bin/env bash
# Trims an embedded Sparkle.framework (D-M4-11, A14): Zivlet is not sandboxed, so Sparkle's XPC services
# (Downloader, Installer) are never used and are removed; every Mach-O is thinned to arm64. Leaves the framework
# unsigned-modified: the caller re-signs it (Scripts/sign-app.sh --nested-only). Safe to run twice.
# Usage: Scripts/trim-sparkle.sh <Sparkle.framework>
set -euo pipefail
FW=${1:?usage: trim-sparkle.sh <Sparkle.framework>}
[[ -d "$FW/Versions" && "$(basename "$FW")" == "Sparkle.framework" ]] ||
    { echo "error: $FW is not a Sparkle.framework" >&2; exit 1; }
ARCH=arm64

rm -rf "$FW/XPCServices"
for version in "$FW"/Versions/*/; do rm -rf "${version}XPCServices"; done

while IFS= read -r -d '' file; do
    file -b "$file" | grep -q "Mach-O universal" || continue
    lipo -thin "$ARCH" "$file" -output "$file.thin" || { echo "error: cannot thin $file" >&2; exit 1; }
    mv "$file.thin" "$file"
done < <(find "$FW/Versions" -type f -perm -u+x -print0)
echo "Trimmed Sparkle.framework: no XPC services, $ARCH only ($(du -sk "$FW" | cut -f1) KB)"
