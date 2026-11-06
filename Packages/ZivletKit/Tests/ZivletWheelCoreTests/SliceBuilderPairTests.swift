import Testing
import ZivletCore

@testable import ZivletWheelCore

/// A conversion is offered only when an engine handles that pair here (plan 20f E11, G-M7-2): a PDF's JPG and PNG
/// slices waited on no engine and failed after the drop, so they are hidden until P2-12.
@Suite("Conversions offered per pair")
struct SliceBuilderPairTests {
    let builder = SliceBuilder()

    func targets(_ content: WheelContent) -> [SliceTarget] { content.slices.map(\.target) }
    func files(_ formats: FormatID...) -> [SelectionItem] { formats.map { SelectionItem($0) } }

    /// Every catalog pair except the ones from a PDF: today's engines on this Mac.
    var noPDFSource: CapabilitySnapshot {
        let pairs = ConversionCatalog.standard.pairs.filter { $0.source != .pdf }
        return CapabilitySnapshot(unavailableTargets: [], availablePairs: Set(pairs))
    }

    @Test func aPDFAloneHasNoConversionUntilAnEngineReadsPDFs() {
        #expect(
            builder.content(for: .convert, items: files(.pdf), capabilities: noPDFSource)
                == .empty(.noInstalledConverter(.pdf)))
    }

    @Test func aPNGAloneKeepsItsList() {
        #expect(
            targets(builder.content(for: .convert, items: files(.png), capabilities: noPDFSource))
                == targets(builder.content(for: .convert, items: files(.png))))
    }

    /// PNG with PDF mixes families: only the PNG can be converted, so every slice counts it alone.
    @Test func aMixOffersOnlyWhatAnEngineCanDoAndCountsOnlyThose() {
        let content = builder.content(for: .convert, items: files(.png, .pdf), capabilities: noPDFSource)
        let pngTargets = Set(ConversionCatalog.standard.targets(for: .png))
        #expect(!content.slices.isEmpty)
        #expect(
            content.slices.allSatisfy { slice in
                guard case .convert(let target) = slice.target else { return false }
                return pngTargets.contains(target) && slice.badge == "1 of 2"
            })
    }

    @Test func withoutPairsTheOldRuleStands() {
        #expect(CapabilitySnapshot.full.availablePairs == nil)
        let catalog = ConversionCatalog.standard.targets(for: .pdf).map(SliceTarget.convert)
        #expect(targets(builder.content(for: .convert, items: files(.pdf))) == catalog)
    }
}
