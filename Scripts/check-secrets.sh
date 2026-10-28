#!/usr/bin/env bash
# P2-102 (plan 20c B7, D-M7-14): passwords stay out of argv, the Keychain and the logs. Refuses, in App, Worker and the
# package's Sources: a `--password` flag or a `password=` value on a line that builds a command line (argv shows in
# `ps`; comment lines are skipped); any Keychain item API, comments included (no password is ever stored, 17b §2.2);
# SecCreateSharedWebCredentialPassword outside SystemPasswordSuggester.swift (Suggest only); and a Logger or os_log
# line that interpolates an identifier named password, secret or passphrase, or a JobSecret, at any privacy level.
# Lines are checked one at a time: an interpolation on a later line of a multi-line log call is not seen.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES=()
for dir in "$REPO_ROOT/App" "$REPO_ROOT/Worker" "$REPO_ROOT/Packages/ZivletKit/Sources"; do
    [[ -d "$dir" ]] && SOURCES+=("$dir")
done
status=0

# Prints the matches of an extended pattern in Swift files (file:line:text), comment lines left out when asked.
matches() {
    local pattern=$1 skip_comments=${2:-no}
    local found
    found=$(grep -rnE --include='*.swift' -- "$pattern" "${SOURCES[@]}" || true)
    if [[ "$skip_comments" == yes ]]; then
        found=$(grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' <<<"$found" || true)
    fi
    printf '%s' "$found"
}

refuse() {
    local found=$1 message=$2
    [[ -z "$found" ]] && return 0
    printf '%s\n' "$found" >&2
    echo "error: $message" >&2
    status=1
}

argv='"--password|(arguments|argv|args|executable|launch)[^/]*password='
refuse "$(matches "$argv" yes)" "a password on a command line (argv shows in ps; send it inside the worker request)"

keychain='SecItemAdd|SecItemCopyMatching|SecItemUpdate|SecItemDelete|kSecClass'
refuse "$(matches "$keychain")" "a Keychain item API (Zivlet never stores a password, 17b §2.2)"

generator=$(matches 'SecCreateSharedWebCredentialPassword' yes | grep -v '/SystemPasswordSuggester\.swift:' || true)
refuse "$generator" "SecCreateSharedWebCredentialPassword outside SystemPasswordSuggester.swift"

logged='(Logger|logger|os_log|log)[.(].*\\\([^)]*([Pp]assword|[Ss]ecret|[Pp]assphrase|JobSecret)'
refuse "$(matches "$logged" yes)" "a password or secret is logged (P2-102); log counts and outcomes only"

exit $status
