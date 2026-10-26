import Testing

@testable import ZivletCore

@Suite("Tools and actions catalog (P0-14, 03a §2.6)")
struct ToolCatalogTests {
    let tools = ToolCatalog.standard

    @Test func has27ToolsInCanonicalOrderEndingWithReadQR() {
        let wheelOrder: [ToolID] = [
            .shrink, .stripMetadata, .imageAdjust, .imageMarkup, .imageBackdrop, .imageCrop, .audioNormalize,
            .videoMute, .videoTrim, .pdfSplit, .pdfArrange, .archiveUnpack, .pdfFromImages, .pdfCombine,
            .videoCrop, .videoSpeed, .videoJoin, .videoFrameGrab, .videoClips, .audioWaveform,
            .audioTrim, .audioChannelMix, .imageCollage, .imageRedact, .videoRedact, .audioBleep, .qrScan,
        ]
        #expect(ToolID.allCases.count == 27)
        #expect(tools.specs.map(\.id) == wheelOrder)
        #expect(Set(wheelOrder) == Set(ToolID.allCases))
        #expect(tools.specs.last?.wheelLabel == "READ QR")
    }

    @Test func instantToolsAreTheFiveWindowlessOnes() {
        let instant = Set(tools.specs.filter { $0.presentation == .instant }.map(\.id))
        #expect(instant == [.videoMute, .pdfSplit, .archiveUnpack, .pdfFromImages, .qrScan])
    }

    @Test func multiOnlyToolsAreTheFourCombiningOnes() {
        let multiOnly = Set(tools.specs.filter { $0.cardinality == .multiOnly }.map(\.id))
        #expect(multiOnly == [.pdfFromImages, .pdfCombine, .videoJoin, .imageCollage])
    }

    @Test func multiFileListsOnlyContainMultiCapableTools() {
        for row in ToolCatalog.applicability {
            for tool in row.multi.map(\.id) { #expect(tools.spec(tool).cardinality != .single, "\(tool)") }
            for tool in row.single.map(\.id) { #expect(tools.spec(tool).cardinality != .multiOnly, "\(tool)") }
        }
    }

    @Test(arguments: [
        (
            [FormatID.jpg],
            [
                ToolID.shrink, .stripMetadata, .imageAdjust, .imageMarkup, .imageBackdrop, .imageCrop,
                .imageRedact,
            ]
        ),
        ([.jpg, .jpg], [.shrink, .stripMetadata, .imageCrop, .pdfFromImages, .imageCollage]),
        ([.svg], [.qrScan]),
        ([.svg, .svg], [.pdfFromImages, .imageCollage, .qrScan]),
        ([.avif], [.qrScan]),
        ([.pdf], [.shrink, .stripMetadata, .pdfSplit, .pdfArrange, .qrScan]),
        ([.pdf, .pdf], [.shrink, .stripMetadata, .pdfSplit, .pdfCombine, .qrScan]),
        (
            [.wav],
            [
                .shrink, .stripMetadata, .audioNormalize, .audioWaveform, .audioTrim, .audioChannelMix,
                .audioBleep,
            ]
        ),
        ([.flac, .flac], [.shrink, .stripMetadata, .audioNormalize]),
        (
            [.mov],
            [
                .shrink, .stripMetadata, .videoMute, .videoTrim, .videoCrop, .videoSpeed,
                .videoFrameGrab, .videoClips, .videoRedact,
            ]
        ),
        ([.mp4, .mp4], [.shrink, .stripMetadata, .videoMute, .videoJoin]),
        ([.gif], [.stripMetadata, .qrScan]),
        ([.rar], [.archiveUnpack]),
        ([.ogg], []), ([.webm], []), ([.docx], []), ([.xlsx], []), ([.srt], []),
    ])
    func perFormatToolLists(formats: [FormatID], expected: [ToolID]) {
        #expect(tools.tools(for: formats) == expected)
    }

    @Test(arguments: [
        ([FormatID.jpg, .png], [ToolID.shrink, .stripMetadata, .imageCrop, .pdfFromImages, .imageCollage]),
        ([.jpg, .avif], [.qrScan]),
        ([.jpg, .pdf], [.qrScan]),
        ([.gif, .png], [.qrScan]),
        ([.jpg, .mp4], []),
        ([.mp4, .webm], []),
        ([.gif, .mov], [.stripMetadata]),
        ([.zip, .rar, .tar], [.archiveUnpack]),
        ([], []),
    ])
    func mixedSelections(formats: [FormatID], expected: [ToolID]) {
        #expect(tools.tools(for: formats) == expected)
    }

    @Test func actionsAreSixInFixedOrder() {
        #expect(ActionID.allCases.map(\.wheelLabel) == ["AIRDROP", "BOX", "COPY", "MOVE", "COPY PATH", "TERMINAL"])
    }

    /// The Drop Box replaces Float (P2-55 §9.5, OWN-APP-1): the stored raw value stays, the slice says BOX.
    @Test func theBoxSliceKeepsFloatsRawValue() {
        #expect(ActionID.pinFloating.rawValue == "pinFloating" && ActionID.pinFloating.symbolName == "tray.full")
    }
}
