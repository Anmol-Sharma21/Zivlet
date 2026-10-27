#!/usr/bin/env bash
# NFR-6 (01-prd): paths stay private in logs. Error descriptions can carry paths (a stderr tail, a folder, an
# NSError's file path), so they must never be interpolated with `privacy: .public`; log `error.logDescription`
# (JobError) publicly and the description privately. P1-48: every Logger and OSSignposter uses one of the categories
# of 10 §8.7 as adopted for Phase 1, so Copy Diagnostics and `log stream` can filter by them.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES=()
for dir in "$REPO_ROOT/App" "$REPO_ROOT/Worker" "$REPO_ROOT/Packages/ZivletKit/Sources"; do
    [[ -d "$dir" ]] && SOURCES+=("$dir")
done
pattern='(String\(describing: [^)]*\)|localizedDescription|stderrTail|folder), privacy: \.public'
if grep -rnE "$pattern" "${SOURCES[@]}"; then
    echo "error: an error description or path is logged with privacy: .public (NFR-6)" >&2
    exit 1
fi
# Plan 18d D14: recognised text (Copy Text) is never logged at any privacy level; counts and scripts only.
text_pattern='(Logger|logger|log)\.[a-z]+\(.*\\\([^)]*(fullText|[Rr]ecognized|RecognizedText|[A-Za-z]+\.text\b)'
if grep -rnE "$text_pattern" "${SOURCES[@]}"; then
    echo "error: recognised text is logged (plan 18d D14); log counts and scripts only" >&2
    exit 1
fi
CATEGORIES="app trigger wheel scheduler media image actions settings hud updates"
status=0
while IFS= read -r line; do
    category=$(sed -E 's/.*category: "([^"]*)".*/\1/' <<<"$line")
    if [[ " $CATEGORIES " != *" $category "* ]]; then
        echo "error: log category \"$category\" is not one of: $CATEGORIES (P1-48): ${line%%:*}" >&2
        status=1
    fi
done < <(grep -rnE '(Logger|OSSignposter)\(subsystem: [^,]*, category: "' "${SOURCES[@]}" || true)
exit $status
