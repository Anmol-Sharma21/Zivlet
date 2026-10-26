import Testing

@testable import ZivletCore
@testable import ZivletWheelCore

/// One cap for every wheel list, in catalog order (P2-100, FR-27).
@Suite("Slice cap of 12 for every list (P2-100)")
struct SliceBuilderCapTests {
    func files(_ formats: FormatID...) -> [SelectionItem] { formats.map { SelectionItem($0) } }

    @Test func aThirteenthToolIsCutAndTheFirstTwelveKeepTheirOrder() {
        let ids = ToolCatalog.specTable.filter { $0.cardinality != .multiOnly }.prefix(13).map(\.id)
        let row = ToolCatalog.ApplicabilityRow(
            formats: [.png], single: ids.map(ToolCatalog.ApplicabilityRow.Entry.visible), multi: [])
        let tools = ToolCatalog(registry: .standard, specs: ToolCatalog.specTable, applicability: [row])
        let content = SliceBuilder(tools: tools).content(for: .tools, items: files(.png))
        #expect(content.slices.map(\.target) == ids.prefix(12).map(SliceTarget.tool))
    }

    @Test func aThirteenthSameFamilyConversionIsCut() throws {
        let targets: [FormatID] = [.jpg, .webp, .heic, .tiff, .avif, .bmp, .pdf, .mp4, .mov, .gif, .zip, .tar, .gz]
        let conversions = try ConversionCatalog(rows: [ConversionRow(.png, targets)], registry: .standard)
        let content = SliceBuilder(conversions: conversions).content(for: .convert, items: files(.png))
        #expect(content.slices.map(\.target) == targets.prefix(12).map(SliceTarget.convert))
    }

    @Test func theBuilderCapReadsTheCoreLimit() {
        #expect(WheelGeometry.standard.maxSlots == WheelLimits.maxSlots)
    }
}
