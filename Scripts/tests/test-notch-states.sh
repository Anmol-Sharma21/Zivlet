#!/usr/bin/env bash
# plan 14 D18: the states script lists one capture per state, finish and display kind without launching anything,
# and the luminance tool reads a PNG of known grey.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
mkdir "$T/bin"
for tool in open screencapture osascript pkill; do printf '#!/usr/bin/env bash\nexit 1\n' >"$T/bin/$tool"; done
chmod +x "$T/bin/"*

out=$(PATH="$T/bin:$PATH" ZIVLET_STATES_DRY_RUN=1 "$ROOT/Scripts/demo-notch-states.sh")
for state in collapsed progress indeterminate expanded result failure failureToast actionToast savedToast list; do
    assert_contains "$out" "notch-$state-glass.png"
done
assert_contains "$out" "pill-collapsed-glass.png"
assert_contains "$out" "notch-result-solid.png"
assert_contains "$out" "notch-result-contrast.png"
assert_contains "$out" "notch-result-reduce-motion.png"
for white in notch-savedToast-white pill-collapsed-white notch-result-white; do
    assert_contains "$out" "$white.png after"
    grep -F "$white.png" <<<"$out" | grep -qF "contrast box" || fail "$white has no contrast box"
done
grep -q 'notch-states' "$ROOT/Makefile" || fail "make notch-states runs the script"

# sRGB grey 128 is linear luminance 0.216; a box in points on a 2x image reads the same.
cat >"$T/grey.swift" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32, space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(CGColor(colorSpace: space, components: [128 / 255, 128 / 255, 128 / 255, 1])!)
context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
let url = URL(filePath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
_ = CGImageDestinationFinalize(destination)
SWIFT
xcrun swift "$T/grey.swift" "$T/grey.png" || fail "could not write the fixture"
assert_eq "$(xcrun swift "$ROOT/Scripts/png-luminance.swift" "$T/grey.png" 0 0 4 4)" "0.216"
assert_eq "$(xcrun swift "$ROOT/Scripts/png-luminance.swift" "$T/grey.png" 0 0 2 2 4)" "0.216"
status=0; xcrun swift "$ROOT/Scripts/png-luminance.swift" "$T/grey.png" 0 0 >/dev/null 2>&1 || status=$?
assert_eq "$status" "2" "missing box arguments exit 2"
# A point width that is not a positive number, or a box not wholly inside the image, is refused rather than read at
# the wrong place or on a smaller region.
for bad in "0 0 2 2 abc" "0 0 2 2 0" "0 0 2 2 -4" "6 6 4 4" "0 0 3 3 2"; do
    status=0
    # shellcheck disable=SC2086 # the box is words on purpose
    xcrun swift "$ROOT/Scripts/png-luminance.swift" "$T/grey.png" $bad >/dev/null 2>&1 || status=$?
    assert_eq "$status" "2" "box [$bad] exits 2"
done
echo "PASS test-notch-states"
