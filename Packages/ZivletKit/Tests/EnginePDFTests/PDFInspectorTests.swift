import EngineTestSupport
import Foundation
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EnginePDF

/// P2-105's pre-flight (plan 20e D1, FR-107): what a PDF holds, read through the library on files made at test time.
@Suite("PDF pre-flight reads what a file holds (P2-105)")
struct PDFInspectorTests {
    static let aes256 = PDFEncryption.standard(
        revision: 6, version: 5, streams: .aes256, strings: .aes256, files: .aes256)

    @Test func aPlainPDFHasNothingToReport() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.plain(in: dir.url)

        let facts = try PDFInspector.inspect(url, password: nil)

        #expect(facts.pageCount == 2)
        #expect(facts.encryption == .none)
        #expect(facts.permissions == .all)
        #expect(facts.opensWithoutPassword)
        #expect(facts.matched == .none)
        #expect(!facts.hasAcroForm)
        #expect(facts.fieldCount == 0)
        #expect(facts.signatureFieldCount == 0)
        #expect(!facts.isTagged)
        #expect(!facts.hasEmbeddedFiles)
        #expect(!facts.hasJavaScript)
        #expect(!facts.isLinearized)
        #expect(facts.warningCount == 0)
    }

    @Test func aRawFilesVersionComesFromItsHeader() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.raw(in: dir.url, name: "seven.pdf", objects: PDFFixtures.onePageObjects)

        #expect(try PDFInspector.inspect(url, password: nil).pdfVersion == "1.7")
    }

    @Test func anAcroFormsFieldsAndSignatureFieldsAreCountedAfterTheShimRewroteIt() throws {
        let dir = try TempDir()
        let rewritten = dir.url.appending(path: "rewritten.pdf")
        try QPDFWriterBridge.write(try PDFFixtures.acroForm(in: dir.url), password: nil, mode: .preserve, to: rewritten)

        let facts = try PDFInspector.inspect(rewritten, password: nil)

        #expect(facts.hasAcroForm)
        #expect(facts.fieldCount == 2)
        #expect(facts.signatureFieldCount == 1)
    }

    /// PDFKit writes widgets with no `/AcroForm` in the catalog, and shows them as live fields all the same.
    @Test func widgetsPDFKitWroteCountAsFieldsWithoutAnAcroForm() throws {
        let dir = try TempDir()
        let rewritten = dir.url.appending(path: "rewritten.pdf")
        try QPDFWriterBridge.write(try PDFFixtures.form(in: dir.url), password: nil, mode: .preserve, to: rewritten)

        let facts = try PDFInspector.inspect(rewritten, password: nil)

        #expect(!facts.hasAcroForm)
        #expect(facts.fieldCount == 2)
        #expect(facts.signatureFieldCount == 1)
    }

    @Test func aTaggedPDFSaysSo() throws {
        let dir = try TempDir()
        let objects = PDFFixtures.objects(catalog: "/StructTreeRoot 5 0 R", extra: ["<< /Type /StructTreeRoot >>"])
        let url = try PDFFixtures.raw(in: dir.url, name: "tagged.pdf", objects: objects)

        #expect(try PDFInspector.inspect(url, password: nil).isTagged)
    }

    @Test func anEmbeddedFilesNameTreeCountsAsAnAttachment() throws {
        let dir = try TempDir()
        let objects = PDFFixtures.objects(
            catalog: "/Names << /EmbeddedFiles << /Names [(note.txt) 5 0 R] >> >>",
            extra: ["<< /Type /Filespec /F (note.txt) /EF << /F 6 0 R >> >>", "<< /Length 0 >>\nstream\n\nendstream"])
        let url = try PDFFixtures.raw(in: dir.url, name: "attached.pdf", objects: objects)

        #expect(try PDFInspector.inspect(url, password: nil).hasEmbeddedFiles)
    }

    @Test func aFileAttachmentAnnotationCountsAsAnAttachment() throws {
        let dir = try TempDir()
        let annotation = "<< /Type /Annot /Subtype /FileAttachment /Rect [72 72 96 96] /Contents (note) >>"
        let objects = PDFFixtures.objects(page: "/Annots [5 0 R]", extra: [annotation])
        let url = try PDFFixtures.raw(in: dir.url, name: "annotated.pdf", objects: objects)

        #expect(try PDFInspector.inspect(url, password: nil).hasEmbeddedFiles)
    }

    /// The JavaScript is the string `void 0` and is never run.
    @Test(arguments: [
        PDFFixtures.objects(catalog: "/OpenAction << /S /JavaScript /JS (void 0) >>"),
        PDFFixtures.objects(
            catalog: "/Names << /JavaScript << /Names [(start) 5 0 R] >> >>",
            extra: ["<< /S /JavaScript /JS (void 0) >>"]),
        PDFFixtures.objects(catalog: "/AA << /WC 5 0 R >>", extra: ["<< /S /JavaScript /JS (void 0) >>"]),
        PDFFixtures.objects(page: "/AA << /O 5 0 R >>", extra: ["<< /S /JavaScript /JS (void 0) >>"]),
    ])
    func javaScriptIsSeen(objects: [String]) throws {
        let dir = try TempDir()
        let url = try PDFFixtures.raw(in: dir.url, name: "script.pdf", objects: objects)

        #expect(try PDFInspector.inspect(url, password: nil).hasJavaScript)
    }

    @Test func anOpenActionThatRunsNoJavaScriptIsNotJavaScript() throws {
        let dir = try TempDir()
        let objects = PDFFixtures.objects(catalog: "/OpenAction << /S /GoTo /D [3 0 R /Fit] >>")
        let url = try PDFFixtures.raw(in: dir.url, name: "goto.pdf", objects: objects)

        #expect(try !PDFInspector.inspect(url, password: nil).hasJavaScript)
    }

    @Test func aLinearizedFileSaysSo() throws {
        let dir = try TempDir()

        #expect(try PDFInspector.inspect(try PDFFixtures.linearized(in: dir.url), password: nil).isLinearized)
    }

    @Test func anRC4FileNamesItsCipherForEveryPart() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.encrypted(in: dir.url, keyLength: 40, user: "u-pass", owner: "o-pass")

        let facts = try PDFInspector.inspect(url, password: JobSecret(utf8: "u-pass"))

        #expect(facts.encryption == .standard(revision: 3, version: 2, streams: .rc4, strings: .rc4, files: .rc4))
        #expect(facts.matched == .user)
        #expect(!facts.opensWithoutPassword)
    }

    @Test func anAES128FileNamesItsCipherAndWhichPasswordMatched() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.encrypted(in: dir.url, keyLength: 128, user: "u-pass", owner: "o-pass")

        let byUser = try PDFInspector.inspect(url, password: JobSecret(utf8: "u-pass"))
        let byOwner = try PDFInspector.inspect(url, password: JobSecret(utf8: "o-pass"))

        #expect(
            byUser.encryption == .standard(revision: 4, version: 4, streams: .aes128, strings: .aes128, files: .aes128))
        #expect(byUser.matched == .user)
        #expect(byOwner.matched.includesOwner)
    }

    @Test func anIdentityCryptFilterIsNamed() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.identityCrypt(in: dir.url, user: "u-pass")

        let facts = try PDFInspector.inspect(url, password: JobSecret(utf8: "u-pass"))

        #expect(
            facts.encryption
                == .standard(revision: 4, version: 4, streams: .identity, strings: .identity, files: .identity))
    }

    @Test func anAES256FileWithoutRestrictionsGrantsEverything() throws {
        let dir = try TempDir()
        let locked = try lockedFile(in: dir, parameters: .init(user: Self.secret("same"), owner: Self.secret("same")))

        let facts = try PDFInspector.inspect(locked, password: Self.secret("same"))

        #expect(facts.encryption == Self.aes256)
        #expect(facts.permissions == .all)
        #expect(facts.matched == .both)
        #expect(!facts.opensWithoutPassword)
        #expect(facts.pageCount == 2)
    }

    @Test func anAES256FileWithRestrictionsListsWhatItStillAllows() throws {
        let dir = try TempDir()
        let denied = R6Permissions(
            accessibility: true, extract: false, assemble: false, annotateAndForm: false, formFilling: false,
            modifyOther: false, printing: .low)
        let parameters = R6Parameters(user: Self.secret("user"), owner: Self.secret("owner"), permissions: denied)
        let locked = try lockedFile(in: dir, parameters: parameters)

        let facts = try PDFInspector.inspect(locked, password: Self.secret("user"))

        #expect(facts.encryption == Self.aes256)
        #expect(facts.permissions == [.accessibility, .printLowQuality])
        #expect(facts.matched == .user)
    }

    @Test func aRestrictionsOnlyFileOpensWithoutAPasswordAndKnowsItsOwner() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.restrictionsOnly(in: dir.url, owner: "o-pass")

        let empty = try PDFInspector.inspect(url, password: nil)
        let owner = try PDFInspector.inspect(url, password: JobSecret(utf8: "o-pass"))

        #expect(empty.opensWithoutPassword)
        #expect(empty.matched == .user)
        #expect(!empty.permissions.contains(.copy))
        #expect(!empty.permissions.contains(.printHighQuality))
        #expect(empty.pageCount == 2)
        #expect(owner.opensWithoutPassword)
        #expect(owner.matched.includesOwner)
    }

    @Test func aLockedFileWithoutItsPasswordTellsItsEncryptionAndNothingBehindIt() throws {
        let dir = try TempDir()
        let parameters = R6Parameters(user: Self.secret("user"), owner: Self.secret("owner"))
        let locked = try lockedFile(in: dir, parameters: parameters)

        let facts = try PDFInspector.inspect(locked, password: nil)

        #expect(facts.isShut)
        #expect(facts.encryption == Self.aes256)
        #expect(facts.matched == .none)
        #expect(!facts.opensWithoutPassword)
        #expect(facts.pageCount == 0)
        #expect(!facts.pdfVersion.isEmpty)
    }

    @Test func anOpenFileIsNotShut() throws {
        let dir = try TempDir()
        let facts = try PDFInspector.inspect(try PDFFixtures.plain(in: dir.url), password: nil)

        #expect(!facts.isShut)
    }

    @Test func aWrongPasswordIsRefusedAndAnEmptyOneMeansNone() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.encrypted(in: dir.url, keyLength: 40, user: "u-pass", owner: "o-pass")

        #expect(throws: PDFEngineError.wrongPassword) {
            try PDFInspector.inspect(url, password: JobSecret(utf8: "nope"))
        }
        #expect(try PDFInspector.inspect(url, password: JobSecret(utf8: "")).isShut)
    }

    @Test func aPublicKeyFileIsNamedEvenThoughItCannotOpen() throws {
        let dir = try TempDir()
        let handler = "<< /Filter /Adobe.PubSec /SubFilter /adbe.pkcs7.s5 /V 4 /R 4 /Length 128 >>"
        let url = try PDFFixtures.raw(
            in: dir.url, name: "certificate.pdf", objects: PDFFixtures.onePageObjects + [handler],
            trailer: "/Encrypt 5 0 R /ID [<00> <00>]")

        let facts = try PDFInspector.inspect(url, password: nil)

        #expect(facts.encryption == .publicKey)
        #expect(facts.isShut)
        #expect(facts.permissions.isEmpty)
    }

    @Test func aStandardHandlerOfAnUnknownRevisionIsUnknown() throws {
        let dir = try TempDir()
        let handler = "<< /Filter /Standard /V 9 /R 9 /O (owner) /U (user) /P -4 >>"
        let url = try PDFFixtures.raw(
            in: dir.url, name: "future.pdf", objects: PDFFixtures.onePageObjects + [handler],
            trailer: "/Encrypt 5 0 R /ID [<00> <00>]")

        #expect(try PDFInspector.inspect(url, password: nil).encryption == .unknown)
    }

    @Test func aPreflightCrossesTheWire() throws {
        let dir = try TempDir()
        let facts = try PDFInspector.inspect(try PDFFixtures.plain(in: dir.url), password: nil)

        let decoded = try JSONDecoder().decode(PDFPreflight.self, from: JSONEncoder().encode(facts))

        #expect(decoded == facts)
    }

    private static func secret(_ text: String) -> JobSecret { JobSecret(utf8: text) }

    private func lockedFile(in dir: TempDir, parameters: R6Parameters) throws -> URL {
        let output = dir.url.appending(path: "locked.pdf")
        try QPDFWriterBridge.write(
            try PDFFixtures.plain(in: dir.url), password: nil, mode: .encryptR6(parameters), to: output)
        return output
    }
}
