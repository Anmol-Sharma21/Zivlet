#!/usr/bin/env bash
# Software bill of materials for a release (P1-53): build/release/zivlet-<version>.spdx.json, SPDX 2.3 JSON with
#   Zivlet itself (GPL-3.0-or-later),
#   every vendored component: Vendor/versions.lock (URL, SHA-256) with its licence from Vendor/licenses.json,
#   every Rust crate linked through zivlet-svg (Scripts/crates.sh), with a pkg:cargo purl,
# each contained in Zivlet. The creation time is the commit time of HEAD, so the same commit gives the same file.
# Usage: Scripts/sbom.sh <version>
set -euo pipefail
source "$(dirname "$0")/env.sh"
VERSION=${1:?usage: sbom.sh <version>}
[[ "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ ]] || { echo "error: bad version [$VERSION]" >&2; exit 2; }
RELEASE=${ZIVLET_RELEASE_DIR:-$REPO_ROOT/build/release}
OUT=$RELEASE/zivlet-$VERSION.spdx.json
COMMIT=$(git -C "$REPO_ROOT" rev-parse HEAD)
CREATED=$(date -u -r "$(git -C "$REPO_ROOT" log -1 --format=%ct)" +%Y-%m-%dT%H:%M:%SZ)

lock=$(awk '!/^[[:space:]]*(#|$)/ { print $1 "\t" $2 "\t" $3 "\t" $4 }' "$REPO_ROOT/Vendor/versions.lock" |
    jq -R -s 'split("\n") | map(select(length > 0) | split("\t")
        | {name: .[0], version: .[1], url: .[2], sha256: (.[3] | ltrimstr("sha256:"))})')
crates=$("$REPO_ROOT/Scripts/crates.sh" | jq -R -s 'split("\n") | map(select(length > 0)
    | capture("^(?<name>\\S+) v(?<version>\\S+) (?<license>.+)$")) | map(select(.name != "zivlet_svg"))')
[[ "$(jq length <<<"$crates")" -gt 0 ]] || { echo "error: no crates listed (run Vendor/build-rs.sh once)" >&2; exit 1; }

mkdir -p "$RELEASE"
jq -n --arg version "$VERSION" --arg commit "$COMMIT" --arg created "$CREATED" --argjson lock "$lock" \
    --argjson crates "$crates" --slurpfile manifest "$REPO_ROOT/Vendor/licenses.json" '
    def id: gsub("[^A-Za-z0-9.]"; "-");
    def spdx: gsub(" */ *"; " OR ");
    def purl: {externalRefs: [{referenceCategory: "PACKAGE-MANAGER", referenceType: "purl",
        referenceLocator: ("pkg:cargo/" + .name + "@" + .version)}]};
    def package($id; $name; $version; $licence; $location):
        {SPDXID: $id, name: $name, versionInfo: $version, downloadLocation: $location, filesAnalyzed: false,
         licenseConcluded: ($licence | spdx), licenseDeclared: ($licence | spdx), copyrightText: "NOASSERTION"};
    ($manifest[0].components | map({key: .name, value: .}) | from_entries) as $m
    | ([package("SPDXRef-Package-Zivlet"; "Zivlet"; $version; "GPL-3.0-or-later";
          "git+https://github.com/Anmol-Sharma21/Zivlet@" + $commit)
        + {primaryPackagePurpose: "APPLICATION", supplier: "Organization: Zivlet contributors"}]
      + ($lock | map(package("SPDXRef-Package-" + (.name | id); .name; .version; $m[.name].spdx; .url)
          + {checksums: [{algorithm: "SHA256", checksumValue: .sha256}], comment: ("Ships: " + $m[.name].ships)}))
      + ($m | to_entries | map(.value | select(.source == "crate"))
          | map(package("SPDXRef-Package-" + (.name | id); .name; .version; .spdx;
              "https://crates.io/crates/" + .name + "/" + .version) + {comment: ("Ships: " + .ships)} + purl))
      + ($crates | map(select(.name as $n | $m | has($n) | not))
          | map(package("SPDXRef-Crate-" + (.name | id) + "-" + (.version | id); .name; .version; .license;
              "https://crates.io/crates/" + .name + "/" + .version) + purl))) as $packages
    | ([$packages[].licenseDeclared | scan("LicenseRef-[A-Za-z0-9.-]+")] | unique) as $refs
    | {spdxVersion: "SPDX-2.3", dataLicense: "CC0-1.0", SPDXID: "SPDXRef-DOCUMENT", name: ("zivlet-" + $version),
       documentNamespace: ("https://spdx.org/spdxdocs/zivlet-" + $version + "-" + $commit),
       creationInfo: {created: $created, creators: ["Tool: zivlet-sbom.sh", "Organization: Zivlet contributors"]},
       packages: $packages,
       hasExtractedLicensingInfos: ($refs | map({licenseId: ., name: (. | ltrimstr("LicenseRef-")),
           extractedText: "See the licence files shipped in Zivlet.app/Contents/Resources/Licenses."})),
       relationships: ([{spdxElementId: "SPDXRef-DOCUMENT", relationshipType: "DESCRIBES",
           relatedSpdxElement: "SPDXRef-Package-Zivlet"}]
         + ($packages[1:] | map({spdxElementId: "SPDXRef-Package-Zivlet", relationshipType: "CONTAINS",
             relatedSpdxElement: .SPDXID})))}' >"$OUT.part"
mv "$OUT.part" "$OUT"
echo "SBOM: $OUT ($(jq '.packages | length' "$OUT") packages)"
