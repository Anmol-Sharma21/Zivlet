import Testing

@testable import ZivletCore

@Suite("Format registry (P0-10, 03a §3.1)")
struct FormatRegistryTests {
    let registry = FormatRegistry.standard

    @Test func has46FormatsWith45InputsAnd39Outputs() {
        #expect(FormatID.allCases.count == 46)
        #expect(registry.formats.count == 46)
        #expect(registry.formats.filter(\.isInput).count == 45)
        #expect(registry.formats.filter(\.isOutput).count == 39)
    }

    @Test func inputOnlyAndOutputOnlySetsMatchSpec() {
        let inputOnly = Set(registry.formats.filter { $0.role == .inputOnly }.map(\.id))
        let outputOnly = Set(registry.formats.filter { $0.role == .outputOnly }.map(\.id))
        #expect(inputOnly == [.rar, .ppt, .xls, .rtf, .rtfd, .textClipping, .svg])
        #expect(outputOnly == [.html])
    }

    @Test(arguments: FormatID.allCases)
    func everyFormatRoundTripsThroughItsCanonicalExtension(id: FormatID) {
        let format = registry.format(id)
        #expect(registry.formatID(fileName: "file.\(format.canonicalExtension)") == id)
        #expect(!format.contentTypes.isEmpty)
    }

    @Test func familiesFollowMixingRules() {
        #expect(registry.format(.gif).family == .video)
        #expect(registry.format(.pdf).family == .document)
        #expect(registry.format(.pptx).family == .document)
        #expect(registry.format(.svg).family == .image)
    }

    @Test func wheelLabelIsUppercaseExtensionExceptGzip() {
        #expect(registry.format(.jpg).wheelLabel == "JPG")
        #expect(registry.format(.textClipping).wheelLabel == "TEXTCLIPPING")
        #expect(registry.format(.gz).wheelLabel == "GZIP")
    }

    @Test(arguments: [
        ("a.TAR.GZ", FormatID.gz), ("b.tgz", .gz), ("c.gz", .gz), ("x.JPEG", .jpg), ("y.jpe", .jpg),
        ("scan.TIF", .tiff), ("page.htm", .html), ("photo.heif", .heic), ("song.aif", .aiff),
        ("notes.markdown", .md), ("clip.textClipping", .textClipping), ("Report.Pages", .pages),
        ("my.file.name.png", .png), ("movie.M4V", .mp4), ("voice.oga", .ogg), ("v.opus", .opus),
        ("table.CSV", .csv), ("doc.rtfd", .rtfd), ("archive.tar", .tar), ("x.Rar", .rar),
    ])
    func resolvesEdgeFileNames(name: String, expected: FormatID) {
        #expect(registry.formatID(fileName: name) == expected)
    }

    @Test(arguments: [".hidden", "noext", "trailingdot.", "a.b.", "", "a.unknown", ".png"])
    func unknownOrExtensionlessNamesReturnNil(name: String) {
        #expect(registry.formatID(fileName: name) == nil)
    }

    @Test func sharedContentTypeIsDisambiguatedByExtension() {
        #expect(registry.formatID(contentType: "org.xiph.ogg-audio", fileName: "a.opus") == .opus)
        #expect(registry.formatID(contentType: "org.xiph.ogg-audio", fileName: "a") == nil)
        #expect(registry.formatID(contentType: "public.png", fileName: "noext") == .png)
    }
}
