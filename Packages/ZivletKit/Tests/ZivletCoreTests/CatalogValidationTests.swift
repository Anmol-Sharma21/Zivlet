import Foundation
import Testing

@testable import ZivletCore

@Suite("Catalog and value validation at public boundaries")
struct CatalogValidationTests {
    let formats = FormatRegistry.standard.formats

    @Test func standardTablesPassTheirOwnValidation() throws {
        let registry = try FormatRegistry(formats: formats)
        #expect(registry.formats == formats)
        let catalog = try ConversionCatalog(rows: ConversionCatalog.table, registry: registry)
        #expect(catalog.pairs == ConversionCatalog.standard.pairs)
    }

    @Test func registryRefusesAMissingFormat() {
        let partial = formats.filter { $0.id != .webm }
        #expect(throws: CatalogError.missingFormat(.webm)) { try FormatRegistry(formats: partial) }
    }

    @Test func registryRefusesADuplicateFormat() {
        let doubled = formats + [FormatRegistry.standard.format(.png)]
        #expect(throws: CatalogError.duplicateFormat(.png)) { try FormatRegistry(formats: doubled) }
    }

    @Test func catalogRefusesSelfTargetsAndDuplicateRows() {
        let registry = FormatRegistry.standard
        #expect(throws: CatalogError.selfTarget(.png)) {
            try ConversionCatalog(rows: [ConversionRow(.png, [.jpg, .png])], registry: registry)
        }
        #expect(throws: CatalogError.duplicateRow(.png)) {
            try ConversionCatalog(
                rows: [ConversionRow(.png, [.jpg]), ConversionRow(.png, [.webp])], registry: registry)
        }
        #expect(throws: CatalogError.duplicateTarget(.png, .jpg)) {
            try ConversionCatalog(rows: [ConversionRow(.png, [.jpg, .jpg])], registry: registry)
        }
    }

    @Test func formatRoundTripsThroughJSON() throws {
        let png = FormatRegistry.standard.format(.png)
        let decoded = try JSONDecoder().decode(Format.self, from: JSONEncoder().encode(png))
        #expect(decoded == png)
    }

    @Test(arguments: [
        #"{"id":"png","family":"image","category":"raster","role":"inputAndOutput","extensions":[],"#
            + #""contentTypes":["public.png"],"isPackage":false}"#,
        #"{"id":"png","family":"image","category":"raster","role":"inputAndOutput","extensions":["png"],"#
            + #""contentTypes":[],"isPackage":false}"#,
        #"{"id":"png","family":"image","category":"raster","role":"inputAndOutput","extensions":["../x"],"#
            + #""contentTypes":["public.png"],"isPackage":false}"#,
    ])
    func invalidFormatPayloadsFailToDecode(json: String) {
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Format.self, from: Data(json.utf8)) }
    }

    @Test func decodedOutputNamesAreNFC() throws {
        let json = #"{"stem":"Café","ext":"png"}"#
        let name = try JSONDecoder().decode(OutputName.self, from: Data(json.utf8))
        #expect(name.stem == "Caf\u{E9}")
        #expect(try name == OutputName(stem: "Caf\u{E9}", ext: "png"))
    }
}
