#!/usr/bin/env bash
# D-PDF-3 (plan 20e D4): every PDF that PDFKit or Quartz writes is rewritten and checked by qpdf. Refuses, in App, Worker
# and the package's Sources: `PDFDocument.write(` anywhere; `.write(to:`, `.write(toFile:` and `.dataRepresentation(` in
# a file that imports PDFKit; and a Quartz PDF context (`closePDF(`, `mediaBox:`, `CGPDFContext`). Comment lines are
# skipped. ALLOWED names the files whose output reaches qpdf.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES=()
for dir in "$REPO_ROOT/App" "$REPO_ROOT/Worker" "$REPO_ROOT/Packages/ZivletKit/Sources"; do
    [[ -d "$dir" ]] && SOURCES+=("$dir")
done
# ImagePDFWriter: the worker's PDFRewritingEngine rewrites its output; the in-process path has no qpdf (D-M7-16).
ALLOWED=" Packages/ZivletKit/Sources/EngineImage/ImagePDFWriter.swift "
status=0

while IFS= read -r file; do
    relative=${file#"$REPO_ROOT"/}
    [[ "$ALLOWED" == *" $relative "* ]] && continue
    code=$(grep -vE '^[[:space:]]*//' "$file" || true)
    found=$(grep -E 'PDFDocument\.write\(|closePDF\(|mediaBox:|CGPDFContext' <<<"$code" || true)
    if grep -qE '^import PDFKit' <<<"$code"; then
        found+=$(grep -E '\.write\((to|toFile):|\.dataRepresentation\(' <<<"$code" || true)
    fi
    if [[ -n "$found" ]]; then
        printf '%s:\n%s\n' "$relative" "$found" >&2
        status=1
    fi
done < <(find "${SOURCES[@]}" -name '*.swift')

if ((status != 0)); then
    echo "error: a PDF written by PDFKit or Quartz must be rewritten by qpdf (D-PDF-3); call PDFRewrite and name the" \
        "file in ALLOWED" >&2
fi
exit $status
