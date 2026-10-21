#!/usr/bin/env bash
# sbom.sh writes SPDX 2.3 JSON: Zivlet itself, one package per lock entry and per manifest crate with the manifest's
# licence, every Rust crate in zivlet-svg's tree, unique SPDX ids, and the relationships that tie them to Zivlet.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
out=$(ZIVLET_RELEASE_DIR=$T "$ROOT/Scripts/sbom.sh" 0.1.0-test 2>&1) || fail "sbom failed: $out"
SBOM=$T/zivlet-0.1.0-test.spdx.json
assert_file "$SBOM"
jq empty "$SBOM" || fail "not JSON"
assert_eq "$(jq -r .spdxVersion "$SBOM")" "SPDX-2.3"
assert_eq "$(jq -r .dataLicense "$SBOM")" "CC0-1.0"
assert_eq "$(jq -r '.packages[] | select(.name == "Zivlet") | .licenseDeclared' "$SBOM")" "GPL-3.0-or-later"
assert_eq "$(jq -r '.packages[] | select(.name == "Zivlet") | .versionInfo' "$SBOM")" "0.1.0-test"

# Every lock entry is a package with its version, SHA-256 and the manifest's licence.
while read -r name version _ hash; do
    got=$(jq -r --arg n "$name" --arg v "$version" \
        '.packages[] | select(.name == $n and .versionInfo == $v)
        | [.checksums[0].checksumValue, .licenseDeclared] | @tsv' \
        "$SBOM")
    want_licence=$(jq -r --arg n "$name" '.components[] | select(.name == $n) | .spdx' "$ROOT/Vendor/licenses.json")
    assert_eq "$got" "${hash#sha256:}	$want_licence" "package $name"
done < <(awk '!/^[[:space:]]*(#|$)/' "$ROOT/Vendor/versions.lock")

# Crates: resvg with the manifest licence, the whole linked tree with purls, no "/" licences, not our own crate.
assert_eq "$(jq -r '.packages[] | select(.name == "resvg") | .licenseDeclared' "$SBOM")" "Apache-2.0 OR MIT"
crates=$(jq '[.packages[] | select(.externalRefs[0].referenceType == "purl")] | length' "$SBOM")
want=$("$ROOT/Scripts/crates.sh" 2>/dev/null | grep -vc '^zivlet_svg ')
assert_eq "$crates" "$want" "crate packages"
assert_eq "$(jq '[.packages[] | select(.licenseDeclared | test("/"))] | length' "$SBOM")" "0" "old-style licences"
assert_eq "$(jq '[.packages[] | select(.name == "zivlet_svg")] | length' "$SBOM")" "0" "own crate listed"

# Ids unique; LicenseRef ids explained; Zivlet described and containing every other package.
assert_eq "$(jq '[.packages[].SPDXID] | length == (unique | length)' "$SBOM")" "true" "unique ids"
for ref in $(jq -r '.packages[].licenseDeclared' "$SBOM" | grep -o 'LicenseRef-[A-Za-z0-9.-]*' | sort -u); do
    jq -e --arg r "$ref" '.hasExtractedLicensingInfos[] | select(.licenseId == $r)' "$SBOM" >/dev/null ||
        fail "$ref has no extracted licensing info"
done
assert_eq "$(jq -r '.relationships[] | select(.relationshipType == "DESCRIBES") | .relatedSpdxElement' "$SBOM")" \
    "SPDXRef-Package-Zivlet"
assert_eq "$(jq '[.relationships[] | select(.relationshipType == "CONTAINS")] | length' "$SBOM")" \
    "$(jq '.packages | length - 1' "$SBOM")" "CONTAINS relationships"
assert_fails env ZIVLET_RELEASE_DIR="$T" "$ROOT/Scripts/sbom.sh" "../bad"
echo "PASS test-sbom"
