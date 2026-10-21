import Foundation
import Testing

@testable import ZivletCore

@Suite("Output names are one safe path component")
struct OutputNameSafetyTests {
    let namer = OutputNamer()

    @Test(arguments: [
        ("a/../../x.png", "a-..-..-x.jpg"),
        ("/etc/passwd.png", "-etc-passwd.jpg"),
        ("nul\u{0}byte.png", "nul-byte.jpg"),
        ("tab\there\u{7F}.png", "tab-here-.jpg"),
        ("time 10:30.png", "time 10-30.jpg"),
        ("", "Untitled.jpg"),
        ("..", "Untitled.jpg"),
        ("   .png", "Untitled.jpg"),
    ])
    func conversionStemsAreSanitised(source: String, expected: String) {
        #expect(namer.conversion(source: source, target: .jpg).rendered() == expected)
    }

    @Test func dotAndEmptyFolderNamesFallBack() throws {
        #expect(try OutputName(stem: "..", ext: nil).rendered() == "Untitled")
        #expect(try OutputName(stem: ".", ext: nil).rendered() == "Untitled")
        #expect(try OutputName(stem: "", ext: nil).rendered() == "Untitled")
        #expect(namer.pagesFolder(source: "../x.pdf", target: .png).rendered() == "..-x PNG Pages")
    }

    @Test(arguments: ["../png", "p/g", "PNG", "", ".png", "png.", "a\u{0}b", String(repeating: "a", count: 17)])
    func invalidExtensionsAreRefused(ext: String) {
        #expect(throws: NamingError.invalidExtension(ext)) { try OutputName(stem: "a", ext: ext) }
        #expect(throws: NamingError.invalidExtension(ext)) {
            try namer.folderItem(prefix: "Page", index: 1, count: 3, ext: ext)
        }
    }

    @Test func folderItemPrefixIsSanitised() throws {
        #expect(try namer.folderItem(prefix: "../Page", index: 1, count: 3, ext: "png") == "..-Page 001.png")
        #expect(try namer.folderItem(prefix: "", index: 2, count: 3, ext: "tar.gz") == "Untitled 002.tar.gz")
    }

    @Test func decodingRefusesAnUnsafeExtension() {
        let json = #"{"stem":"a","ext":"..\/x"}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(OutputName.self, from: Data(json.utf8)) }
    }

    @Test func decodingSanitisesTheStem() throws {
        let json = #"{"stem":"..\/..\/x","ext":"png"}"#
        #expect(try JSONDecoder().decode(OutputName.self, from: Data(json.utf8)).rendered() == "..-..-x.png")
    }
}
