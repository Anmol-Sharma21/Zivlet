import Foundation
import OCRTestSupport
import Testing

@testable import EngineVision

/// The inputs of the Read QR and locked-input demos (plan 20g F3, exit rows V9 and V10), made here in our own words:
/// with `ZIVLET_QR_DUMP=<folder>` a QR web link as `inputs/Menu.png`, a Code 128 ticket as `inputs/Label.png` and a
/// one-page PDF with a QR text as `inputs/Poster.pdf`, and `expected-codes.txt` (payload, a tab, whether Open is
/// offered); with `ZIVLET_LOCKED_TEXT_DUMP=<folder>` a two-page locked PDF as `Locked.pdf` and the text Copy Text must
/// copy as `expected.txt`. Its password is the first line of `<folder>/inputs-secret`, a 0600 file the script wrote,
/// deleted here once read (never in argv or the environment).
@Suite(
    "Read QR and locked-input demo inputs",
    .enabled(if: demoFolder("ZIVLET_QR_DUMP") != nil || demoFolder("ZIVLET_LOCKED_TEXT_DUMP") != nil))
struct ToolDemoInputTests {
    @Test(.enabled(if: demoFolder("ZIVLET_QR_DUMP") != nil)) func theCodesAndTheirPayloadsAreWritten() throws {
        let folder = try #require(demoFolder("ZIVLET_QR_DUMP"))
        let inputs = folder.appending(path: "inputs", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inputs, withIntermediateDirectories: true)
        try CodeFixtures.writePNG(try CodeFixtures.image(CodeFixtures.link), to: inputs.appending(path: "Menu.png"))
        let ticket = try CodeFixtures.image(CodeFixtures.ticket, kind: .code128, scale: 4)
        try CodeFixtures.writePNG(ticket, to: inputs.appending(path: "Label.png"))
        try CodeFixtures.writePDF(
            [try CodeFixtures.image(CodeFixtures.table)], to: inputs.appending(path: "Poster.pdf"))
        let expected = [
            "\(CodeFixtures.link)\tyes", "\(CodeFixtures.ticket)\tno", "\(CodeFixtures.table)\tno",
        ]
        try Data((expected.joined(separator: "\n") + "\n").utf8).write(to: folder.appending(path: "expected-codes.txt"))
    }

    @Test(.enabled(if: demoFolder("ZIVLET_LOCKED_TEXT_DUMP") != nil)) func theLockedPDFAndItsTextAreWritten() throws {
        let folder = try #require(demoFolder("ZIVLET_LOCKED_TEXT_DUMP"))
        let password = try Self.readSecret(in: folder)
        let owner = LockedPDFInputTests.password("owner")
        let made = try LockedPDFInputTests.lockedText(in: folder, user: password, owner: owner)
        try FileManager.default.moveItem(at: made, to: folder.appending(path: "Locked.pdf"))
        let pages = LockedPDFInputTests.words.map { RecognizedPage(text: $0) }
        let text = TextAssembly.combine([FileText(name: "Locked.pdf", pages: pages)]).text
        try Data(text.utf8).write(to: folder.appending(path: "expected.txt"))
    }

    /// The first line of the 0600 file, which is removed whether or not it could be read.
    static func readSecret(in folder: URL) throws -> String {
        let file = folder.appending(path: "inputs-secret")
        defer { try? FileManager.default.removeItem(at: file) }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        let text = try String(contentsOf: file, encoding: .utf8)
        return try #require(text.split(separator: "\n").first.map(String.init))
    }
}

/// The folder a demo script named in the environment variable, or nil.
private func demoFolder(_ name: String) -> URL? {
    ProcessInfo.processInfo.environment[name].map { URL(fileURLWithPath: $0, isDirectory: true) }
}
