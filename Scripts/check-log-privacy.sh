#!/usr/bin/env bash
# NFR-6 (01-prd): paths stay private in logs. Error descriptions can carry paths (a stderr tail, a folder, an
# NSError's file path), so they must never be interpolated with `privacy: .public`; log `error.logDescription`
# (JobError) publicly and the description privately.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pattern='(String\(describing: [^)]*\)|localizedDescription|stderrTail|folder), privacy: \.public'
if grep -rnE "$pattern" "$REPO_ROOT/App" "$REPO_ROOT/Packages/ZivletKit/Sources"; then
    echo "error: an error description or path is logged with privacy: .public (NFR-6)" >&2
    exit 1
fi
