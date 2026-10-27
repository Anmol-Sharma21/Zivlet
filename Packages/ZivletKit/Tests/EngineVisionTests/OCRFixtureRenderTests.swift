import Foundation
import ImageIO
import OCRTestSupport
import TestSupport
import Testing

@Suite("OCR fixtures (D-M6-11): the manifest is validated and the 12 images are rendered at test time")
struct OCRFixtureRenderTests {
    @Test func theManifestHasTwelveUniqueFixtures() throws {
        let manifest = try OCRFixtures.manifest()
        #expect(manifest.entries.count == 12)
        #expect(Set(manifest.entries.map(\.name)).count == 12)
        #expect(manifest.entries.allSatisfy { !$0.text.isEmpty })
    }

    @Test func renderingWritesOneFilePerFixtureWithItsName() throws {
        let folder = try TempDir()
        let files = try OCRFixtures.render(into: folder.url)
        let manifest = try OCRFixtures.manifest()
        #expect(files.map(\.lastPathComponent) == manifest.entries.map(\.fileName))
        for file in files {
            let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width > 80 && image.height > 80, "\(file.lastPathComponent)")
        }
    }

    @Test func theDegradedFixtureIsDeterministic() throws {
        let first = try TempDir()
        let second = try TempDir()
        try OCRFixtures.render(into: first.url)
        try OCRFixtures.render(into: second.url)
        let name = "07_mixed_degraded.jpg"
        let a = try Data(contentsOf: first.url.appending(path: name))
        let b = try Data(contentsOf: second.url.appending(path: name))
        #expect(a == b)
    }

    @Test func anUnknownFontFailsValidationWithItsName() throws {
        let json = """
            {"version": 1, "entries": [
              {"name": "01_x", "font": "ComicSansMS", "size": 36, "lines": ["Hello"], "style": "plain"}
            ]}
            """
        #expect(throws: OCRFixtureError.unknownFont("ComicSansMS")) {
            try OCRFixtures.Manifest.decode(Data(json.utf8))
        }
    }

    @Test func duplicateNamesEmptyTextAndOddSizesAreRefused() throws {
        func manifest(_ entries: String) -> Data { Data("{\"version\": 1, \"entries\": [\(entries)]}".utf8) }
        let entry = { (name: String, size: Int, line: String) in
            "{\"name\": \"\(name)\", \"font\": \"HelveticaNeue\", \"size\": \(size), \"lines\": [\"\(line)\"],"
                + " \"style\": \"plain\"}"
        }
        #expect(throws: OCRFixtureError.duplicateName("a")) {
            try OCRFixtures.Manifest.decode(manifest(entry("a", 36, "x") + "," + entry("a", 36, "y")))
        }
        #expect(throws: OCRFixtureError.emptyText("a")) {
            try OCRFixtures.Manifest.decode(manifest(entry("a", 36, " ")))
        }
        #expect(throws: OCRFixtureError.sizeOutOfRange("a", 7)) {
            try OCRFixtures.Manifest.decode(manifest(entry("a", 7, "x")))
        }
        #expect(throws: OCRFixtureError.sizeOutOfRange("a", 97)) {
            try OCRFixtures.Manifest.decode(manifest(entry("a", 97, "x")))
        }
    }
}
