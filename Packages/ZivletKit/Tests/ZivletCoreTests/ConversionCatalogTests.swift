import Testing

@testable import ZivletCore

@Suite("Conversion catalog (P0-12, 03a §3.3, 10 §4.13)")
struct ConversionCatalogTests {
    let catalog = ConversionCatalog.standard
    let registry = FormatRegistry.standard

    @Test func has275Pairs() {
        #expect(catalog.pairs.count == 275)
        #expect(Set(catalog.pairs).count == 275)
    }

    @Test(arguments: [
        (FormatCategory.raster, 49), (.svg, 8), (.audio, 56), (.video, 42), (.gif, 6), (.pdf, 9),
        (.document, 65), (.slides, 6), (.spreadsheet, 21), (.subtitle, 4), (.archive, 9),
    ])
    func pairCountPerCategory(category: FormatCategory, expected: Int) {
        #expect(catalog.pairCount(in: category) == expected)
    }

    @Test func everyInputHasARowAndOutputOnlyHasNone() {
        let sources = Set(catalog.pairs.map(\.source))
        #expect(sources.count == 45)
        #expect(sources == Set(registry.formats.filter(\.isInput).map(\.id)))
        #expect(catalog.targets(for: .html).isEmpty)
    }

    @Test func targetsAreExactlyThe39OutputFormats() {
        #expect(catalog.distinctTargets.count == 39)
        #expect(catalog.distinctTargets == Set(registry.formats.filter(\.isOutput).map(\.id)))
    }

    @Test func noSelfPairsAndNoInputOnlyTargets() {
        for pair in catalog.pairs {
            #expect(pair.source != pair.target)
            #expect(registry.format(pair.target).isOutput, "\(pair.target) is input-only")
        }
    }

    @Test func petalOrderMatchesSpecSamples() {
        #expect(catalog.targets(for: .png) == [.jpg, .webp, .heic, .tiff, .avif, .bmp, .pdf])
        #expect(catalog.targets(for: .wav) == [.mp3, .m4a, .flac, .ogg, .opus, .aiff, .wma])
        #expect(catalog.targets(for: .txt).suffix(2) == [.jpg, .png])
        #expect(catalog.targets(for: .docx).suffix(2) == [.png, .jpg])
        #expect(catalog.targets(for: .rar) == [.zip, .tar, .gz])
    }

    @Test func maxPetalCountIsNine() {
        let maxCount = FormatID.allCases.map { catalog.targets(for: $0).count }.max()
        #expect(maxCount == 9)
    }
}
