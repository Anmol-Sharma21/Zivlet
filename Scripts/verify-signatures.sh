#!/usr/bin/env bash
# Signature gate (P1-52, 11 §7.3). Every Mach-O in the app must pass `codesign --verify --strict` and carry the
# hardened runtime flag. With --require-developer-id, every file must also have the same Team ID and a secure
# timestamp, the app must keep library validation on, and Gatekeeper (`spctl`) must accept the app (that needs
# notarization, owner step O-1). Without the flag an ad-hoc signed app is reported, not failed (05 §8 fallback).
# Usage: Scripts/verify-signatures.sh <Zivlet.app> [--require-developer-id]
set -euo pipefail
APP=${1:?usage: verify-signatures.sh <app> [--require-developer-id]}
REQUIRE_ID=${2:-}
problems=0; adhoc=0; teams=""; count=0
problem() { echo "verify-signatures: $*" >&2; problems=1; }
[[ -d "$APP/Contents" ]] || { echo "verify-signatures: $APP is not an app bundle" >&2; exit 1; }

check_file() {
    local file=$1 rel=${1#"$APP/"} info team
    if ! codesign --verify --strict "$file" 2>/dev/null; then problem "invalid signature: $rel"; return; fi
    info=$(codesign -dv "$file" 2>&1)
    grep -qE 'flags=0x[0-9a-f]+\([^)]*runtime' <<<"$info" || problem "no hardened runtime: $rel"
    if grep -q 'Signature=adhoc' <<<"$info"; then adhoc=1; return; fi
    team=$(awk -F= '/^TeamIdentifier=/ { print $2 }' <<<"$info")
    teams="$teams $team"
    if [[ "$REQUIRE_ID" == "--require-developer-id" ]] && ! grep -q '^Timestamp=' <<<"$info"; then
        problem "no secure timestamp: $rel"
    fi
}

while IFS= read -r -d '' file; do
    file -b "$file" | grep -q "Mach-O" || continue
    check_file "$file"
    count=$((count + 1))
done < <(find "$APP" -type f -print0)
codesign --verify --strict --deep "$APP" 2>/dev/null || problem "the app's seal is broken (codesign --verify --deep)"

if [[ "$REQUIRE_ID" == "--require-developer-id" ]]; then
    # Ad-hoc builds need it off to load Sparkle (Config/ZivletAdHoc.entitlements); a Developer ID build must not.
    if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "disable-library-validation"; then
        problem "library validation is off in the app (sign it with Config/Zivlet.entitlements)"
    fi
    distinct=$(tr ' ' '\n' <<<"$teams" | { grep -v '^$' || true; } | sort -u)
    if ((adhoc)) || [[ -z "$distinct" || "$distinct" == "not set" ]]; then
        echo "verify-signatures: Developer ID signature required (owner step O-1)" >&2
        exit 1
    fi
    [[ $(wc -l <<<"$distinct") -eq 1 ]] || problem "files are signed by different teams: $(echo $distinct)"
    spctl -a -vv -t exec "$APP" >/dev/null 2>&1 || problem "Gatekeeper rejects the app (is it notarized?)"
fi
if ((problems)); then exit 1; fi
if ((adhoc)); then
    echo "report-only: ad-hoc signature ($count Mach-O files verified, hardened runtime on all)"
else
    echo "Signatures OK: $count Mach-O files, Team ID $(tr ' ' '\n' <<<"$teams" | grep -v '^$' | sort -u)"
fi
