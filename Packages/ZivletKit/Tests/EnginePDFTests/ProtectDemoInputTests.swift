import EngineTestSupport
import Foundation
import Testing

/// The inputs of the LOCK · UNLOCK demo and the PDF smoke (plan 20g F3, exit rows V6 and V8), made here in our own
/// words: with `ZIVLET_PDF_DEMO_DUMP=<folder>` it writes `Report.pdf` (two plain pages), `Form.pdf` (a text field and
/// a signature field as PDFKit writes them), `Legacy RC4.pdf` (RC4 at 40 bits) and `Legacy AES.pdf` (AES-128), the
/// last two locked by CoreGraphics with the first line of `<folder>/inputs-secret` as both passwords. That 0600 file
/// is the script's, deleted here once read, so the password is never in argv or the environment.
@Suite(
    "LOCK · UNLOCK demo inputs",
    .enabled(if: ProcessInfo.processInfo.environment["ZIVLET_PDF_DEMO_DUMP"] != nil))
struct ProtectDemoInputTests {
    @Test func theInputsAreWritten() throws {
        let path = try #require(ProcessInfo.processInfo.environment["ZIVLET_PDF_DEMO_DUMP"])
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        let password = try Self.readSecret(in: folder)
        try PDFFixtures.plain(in: folder, name: "Report.pdf", pages: 2)
        try PDFFixtures.encrypted(in: folder, name: "Legacy RC4.pdf", keyLength: 40, user: password, owner: password)
        try PDFFixtures.encrypted(in: folder, name: "Legacy AES.pdf", keyLength: 128, user: password, owner: password)
        // The form helper leaves its base page beside the form, so it works in a folder of its own.
        let scratch = folder.appending(path: ".form", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let form = try PDFFixtures.form(in: scratch, name: "Form.pdf")
        try FileManager.default.moveItem(at: form, to: folder.appending(path: "Form.pdf"))
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
