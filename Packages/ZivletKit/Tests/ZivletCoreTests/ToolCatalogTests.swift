import Testing

@testable import ZivletCore

@Suite("Tools and actions catalog (P0-14, 03a §2.6)")
struct ToolCatalogTests {
    let tools = ToolCatalog.standard

    @Test func has28ToolsInCanonicalOrderEndingWithReadQRAndCopyText() {
        let wheelOrder: [ToolID] = [
            .shrink, .stripMetadata, .imageAdjust, .imageMarkup, .imageBackdrop, .imageCrop, .audioNormalize,
            .videoMute, .videoTrim, .pdfSplit, .pdfArrange, .archiveUnpack, .pdfFromImages, .pdfCombine,
            .videoCrop, .videoSpeed, .videoJoin, .videoFrameGrab, .videoClips, .audioWaveform,
            .audioTrim, .audioChannelMix, .imageCollage, .imageRedact, .videoRedact, .audioBleep, .qrScan, .copyText,
        ]
        #expect(ToolID.allCases.count == 28)
        #expect(tools.specs.map(\.id) == wheelOrder)
        #expect(Set(wheelOrder) == Set(ToolID.allCases))
        #expect(tools.specs.suffix(2).map(\.wheelLabel) == ["READ QR", "COPY TEXT"])
    }

    /// P2-104: an instant slice for one or many images and PDFs, writing `<name> Text.txt` with ⌥.
    @Test func copyTextIsAnInstantMultiFileToolForImagesAndPDFs() {
        let spec = tools.spec(.copyText)
        #expect(spec.wheelLabel == "COPY TEXT" && spec.symbolName == "text.viewfinder")
        #expect(spec.presentation == .instant && spec.cardinality == .multiAllowed && spec.outputSuffix == "Text")
        #expect(spec.accepts == [.jpg, .png, .webp, .heic, .tiff, .avif, .bmp, .gif, .pdf])
    }

    @Test func instantToolsAreTheSixWindowlessOnes() {
        let instant = Set(tools.specs.filter { $0.presentation == .instant }.map(\.id))
        #expect(instant == [.videoMute, .pdfSplit, .archiveUnpack, .pdfFromImages, .qrScan, .copyText])
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
                ToolID.copyText, .shrink, .stripMetadata, .imageAdjust, .imageMarkup, .imageBackdrop, .imageCrop,
                .imageRedact,
            ]
        ),
        ([.jpg, .jpg], [.copyText, .shrink, .stripMetadata, .imageCrop, .pdfFromImages, .imageCollage]),
        ([.svg], [.qrScan]),
        ([.svg, .svg], [.pdfFromImages, .imageCollage, .qrScan]),
        ([.avif], [.qrScan, .copyText]),
        ([.bmp, .bmp], [.qrScan, .copyText]),
        ([.pdf], [.shrink, .stripMetadata, .pdfSplit, .pdfArrange, .copyText, .qrScan]),
        ([.pdf, .pdf], [.shrink, .stripMetadata, .pdfSplit, .pdfCombine, .copyText, .qrScan]),
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
        ([.gif], [.stripMetadata, .qrScan, .copyText]),
        ([.gif, .gif], [.stripMetadata, .qrScan, .copyText]),
        ([.rar], [.archiveUnpack]),
        ([.ogg], []), ([.webm], []), ([.docx], []), ([.xlsx], []), ([.srt], []),
    ])
    func perFormatToolLists(formats: [FormatID], expected: [ToolID]) {
        #expect(tools.tools(for: formats) == expected)
    }

    @Test(arguments: [
        ([FormatID.jpg, .png], [ToolID.copyText, .shrink, .stripMetadata, .imageCrop, .pdfFromImages, .imageCollage]),
        ([.jpg, .avif], [.copyText]),
        ([.jpg, .pdf], [.qrScan, .copyText]),
        ([.gif, .png], [.qrScan, .copyText]),
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
