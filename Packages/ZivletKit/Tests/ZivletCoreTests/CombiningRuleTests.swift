import Testing

@testable import ZivletCore

/// Mixed selections (P2-100, FR-91): a same-family mix keeps the intersection of its lists; otherwise the wheel
/// shows the tools whose accepted formats cover every item.
@Suite("Combining rule for mixed selections (P2-100)")
struct CombiningRuleTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let formats: [FormatID]
        let expected: [ToolID]
        var testDescription: String { formats.map(\.rawValue).joined(separator: "+") }
    }

    static let imageMulti: [ToolID] = [.shrink, .stripMetadata, .imageCrop, .pdfFromImages, .imageCollage]

    /// Thirty mixed sets, two to five items, with duplicates. Today only READ QR crosses families.
    static let thirty: [Row] = [
        Row(formats: [.jpg, .pdf], expected: [.qrScan]),
        Row(formats: [.png, .pdf, .pdf], expected: [.qrScan]),
        Row(formats: [.jpg, .svg], expected: [.pdfFromImages, .imageCollage]),
        Row(formats: [.svg, .pdf], expected: [.qrScan]),
        Row(formats: [.gif, .pdf], expected: [.qrScan]),
        Row(formats: [.gif, .png], expected: [.qrScan]),
        Row(formats: [.mp3, .mp4], expected: []),
        Row(formats: [.mp4, .png], expected: []),
        Row(formats: [.mov, .jpg, .jpg], expected: []),
        Row(formats: [.png, .docx], expected: []),
        Row(formats: [.pdf, .docx], expected: []),
        Row(formats: [.zip, .png], expected: []),
        Row(formats: [.rar, .pdf], expected: []),
        Row(formats: [.heic, .webp, .avif], expected: [.qrScan]),
        Row(formats: [.bmp, .tiff], expected: [.qrScan]),
        Row(formats: [.avif, .bmp], expected: [.qrScan]),
        Row(formats: [.jpg, .png, .webp, .heic, .tiff], expected: imageMulti),
        Row(formats: [.jpg, .jpg, .pdf, .pdf], expected: [.qrScan]),
        Row(formats: [.gif, .mov], expected: [.stripMetadata]),
        Row(formats: [.gif, .mp4, .pdf], expected: []),
        Row(formats: [.gif, .gif, .svg, .pdf, .jpg], expected: [.qrScan]),
        Row(formats: [.svg, .svg, .png], expected: [.pdfFromImages, .imageCollage]),
        Row(formats: [.wav, .flac], expected: [.shrink, .stripMetadata, .audioNormalize]),
        Row(formats: [.mp3, .ogg], expected: []),
        Row(formats: [.mp4, .webm], expected: []),
        Row(formats: [.pdf, .md], expected: []),
        Row(formats: [.srt, .mp4], expected: []),
        Row(formats: [.xlsx, .csv], expected: []),
        Row(formats: [.zip, .tar, .gz, .rar], expected: [.archiveUnpack]),
        Row(formats: [.png, .mp3, .pdf], expected: []),
    ]

    @Test func theTableHasThirtyMixedSetsOfTwoToFiveItems() {
        #expect(Self.thirty.count == 30)
        #expect(Self.thirty.allSatisfy { (2...5).contains($0.formats.count) && Set($0.formats).count >= 2 })
    }

    @Test(arguments: thirty)
    func mixedSelectionsShowOnlyToolsThatAcceptEveryItem(_ row: Row) {
        #expect(ToolCatalog.standard.tools(for: row.formats) == row.expected)
        #expect(ToolCatalog.standard.extras(for: row.formats).isEmpty)
    }

    @Test func readQRAcceptsEveryImageFormatGIFAndPDF() {
        let images = FormatID.allCases.filter { FormatRegistry.standard.format($0).family == .image }
        #expect(ToolCatalog.standard.spec(.qrScan).accepts == Set(images + [.gif, .pdf]))
        let others = ToolCatalog.standard.specs.filter { $0.id != .qrScan }
        #expect(others.allSatisfy { $0.accepts == nil })
    }

    @Test func aCombiningToolShowsForImagesWithPDFButNotWithAudio() {
        let catalog = Self.catalog(combining: .defaultVisible)
        #expect(catalog.tools(for: [.png, .pdf]) == [.pdfCombine, .qrScan])
        #expect(catalog.tools(for: [.svg, .pdf, .jpg]) == [.pdfCombine, .qrScan])
        #expect(catalog.tools(for: [.png, .mp3]).isEmpty)
    }

    @Test func aCombiningToolMarkedExtraWaitsInTheExtras() {
        let catalog = Self.catalog(combining: .extra)
        #expect(catalog.tools(for: [.png, .pdf]) == [.qrScan])
        #expect(catalog.extras(for: [.png, .pdf]) == [.pdfCombine])
    }

    @Test func aSingleItemToolNeverCombines() {
        let catalog = Self.catalog(combining: .defaultVisible, cardinality: .single)
        #expect(catalog.tools(for: [.png, .pdf]) == [.qrScan])
    }

    /// The standard tables with MERGE PDF made a combining tool that takes images, SVG and PDF; `mark` is how the
    /// PDF row lists it.
    static func catalog(
        combining mark: ToolVisibility, cardinality: ToolCardinality = .multiOnly
    ) -> ToolCatalog {
        let images: Set<FormatID> = [.jpg, .png, .webp, .heic, .tiff, .avif, .bmp, .svg]
        let specs = ToolCatalog.specTable.map { spec in
            guard spec.id == .pdfCombine else { return spec }
            return ToolSpec(
                id: spec.id, wheelLabel: spec.wheelLabel, symbolName: spec.symbolName,
                presentation: spec.presentation, cardinality: cardinality, outputSuffix: spec.outputSuffix,
                accepts: images.union([.pdf]))
        }
        let rows = ToolCatalog.applicability.map { row in
            guard row.formats.contains(.pdf) else { return row }
            let multi = row.multi.map { entry in
                entry.id == .pdfCombine ? ToolCatalog.ApplicabilityRow.Entry(id: entry.id, visibility: mark) : entry
            }
            return ToolCatalog.ApplicabilityRow(formats: row.formats, single: row.single, multi: multi)
        }
        return ToolCatalog(registry: .standard, specs: specs, applicability: rows)
    }
}
