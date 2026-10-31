#!/usr/bin/env bash
# check-pdf-writes.sh (plan 20e D4, D-PDF-3): a PDFKit or Quartz PDF write outside the allow-list is refused, the
# allowed writer and ordinary file writes pass, and the repository itself passes.
source "$(dirname "$0")/../../Vendor/tests/lib.sh"
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
T=$(tmpdir); trap 'rm -rf "$T"' EXIT
SOURCES="$T/Packages/ZivletKit/Sources"
mkdir -p "$T/Scripts" "$T/App" "$T/Worker" "$SOURCES/EngineImage" "$SOURCES/EngineVision"
cp "$ROOT/Scripts/check-pdf-writes.sh" "$T/Scripts/"
FILE="$SOURCES/EngineVision/A.swift"
clean='let name = "Report.pdf"'

refused() {  # sample, file
    printf '%s\n' "$1" >"${2:-$FILE}"
    local status=0 out
    out=$("$T/Scripts/check-pdf-writes.sh" 2>&1) || status=$?
    assert_eq "$status" "1" "refused: $1"
    assert_contains "$out" "rewritten by qpdf"
    printf '%s\n' "$clean" >"${2:-$FILE}"
}

allowed() {  # sample, file
    printf '%s\n' "$1" >"${2:-$FILE}"
    "$T/Scripts/check-pdf-writes.sh" >/dev/null 2>&1 || fail "allowed: $1"
    printf '%s\n' "$clean" >"${2:-$FILE}"
}

printf '%s\n' "$clean" >"$FILE"
"$T/Scripts/check-pdf-writes.sh" >/dev/null || fail "a clean tree passes"

# PDFKit's writers, in any file that imports PDFKit.
refused 'PDFDocument.write(to: url)'
refused $'import PDFKit\nlet saved = document.write(to: url)'
refused $'import PDFKit\ndocument.write(toFile: path)'
refused $'import PDFKit\nlet bytes = document.dataRepresentation()'
refused $'import PDFKit\nlet bytes = document.dataRepresentation(options: [:])' "$T/App/B.swift"
refused $'import PDFKit\ndocument.write(to: url)' "$T/Worker/W.swift"

# Quartz's PDF contexts, anywhere.
refused 'let context = CGContext(url as CFURL, mediaBox: nil, nil)'
refused 'context.closePDF()'
refused 'let context = CGPDFContextCreateWithURL(url, nil, nil)'

# The named writer, comments, and writes that are not a PDF's.
allowed 'context.closePDF()' "$SOURCES/EngineImage/ImagePDFWriter.swift"
allowed '// PDFDocument.write(to:) leaves files qpdf must repair'
allowed $'import PDFKit\n// document.write(to: url) is refused'
allowed 'try data.write(to: url)'
allowed 'let bytes = image.dataRepresentation()'

# The repository itself.
"$ROOT/Scripts/check-pdf-writes.sh" >/dev/null || fail "the repository passes"
echo "ok: check-pdf-writes"
