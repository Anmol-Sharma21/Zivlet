import EngineTestSupport
import Foundation
import PDFKit
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EnginePDF

/// P2-13's smoke test (plan 20d C4): qpdf, inside our own shim, rewrites, decrypts and encrypts PDFs made at test time.
@Suite("qpdf smoke (P2-13)")
struct QPDFSmokeTests {
    @Test func aPlainTwoPagePDFIsRewrittenAndPassesTheCheck() throws {
        let dir = try TempDir()
        let input = try PDFFixtures.plain(in: dir.url)
        let output = dir.url.appending(path: "out.pdf")

        try QPDFWriterBridge.write(input, password: nil, mode: .preserve, to: output)

        #expect(PDFDocument(url: output)?.pageCount == 2)
        #expect(try QPDFDocumentReader.check(output, password: nil) == 0)
        let info = try PDFInspector.inspect(output, password: nil)
        #expect(info.pageCount == 2)
        #expect(info.encryption == .none)
        #expect(info.matched == .none)
    }

    @Test func aCoreGraphicsRC4FileOpensWithItsUserPassword() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.encrypted(in: dir.url, keyLength: 40, user: "u-pass", owner: "o-pass")

        let info = try PDFInspector.inspect(url, password: JobSecret(utf8: "u-pass"))

        #expect(info.encryption == .standard(revision: 3, version: 2, streams: .rc4, strings: .rc4, files: .rc4))
        #expect(info.matched == .user)
        #expect(info.pageCount == 2)
    }

    @Test func aCoreGraphicsAES128FileOpensWithItsOwnerPassword() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.encrypted(in: dir.url, keyLength: 128, user: "u-pass", owner: "o-pass")

        let byUser = try PDFInspector.inspect(url, password: JobSecret(utf8: "u-pass"))
        let byOwner = try PDFInspector.inspect(url, password: JobSecret(utf8: "o-pass"))

        #expect(
            byUser.encryption == .standard(revision: 4, version: 4, streams: .aes128, strings: .aes128, files: .aes128))
        #expect(byUser.matched == .user)
        #expect(byOwner.matched.includesOwner)
    }

    @Test(arguments: [40, 128])
    func anEncryptedFileIsDecryptedWithItsUserPassword(keyLength: Int) throws {
        let dir = try TempDir()
        let input = try PDFFixtures.encrypted(in: dir.url, keyLength: keyLength, user: "u-pass", owner: "o-pass")
        let output = dir.url.appending(path: "open.pdf")

        try QPDFWriterBridge.write(input, password: JobSecret(utf8: "u-pass"), mode: .decrypt, to: output)

        #expect(try PDFInspector.inspect(output, password: nil).encryption == .none)
        let document = try #require(PDFDocument(url: output))
        #expect(!document.isEncrypted)
        #expect(document.pageCount == 2)
    }

    @Test func anAES256FileWrittenByTheShimOpensOnlyWithItsPasswords() throws {
        let dir = try TempDir()
        let input = try PDFFixtures.plain(in: dir.url)
        let output = dir.url.appending(path: "locked.pdf")
        let parameters = R6Parameters(user: JobSecret(utf8: "new user"), owner: JobSecret(utf8: "new owner"))

        try QPDFWriterBridge.write(input, password: nil, mode: .encryptR6(parameters), to: output)

        let info = try PDFInspector.inspect(output, password: JobSecret(utf8: "new user"))
        #expect(
            info.encryption == .standard(revision: 6, version: 5, streams: .aes256, strings: .aes256, files: .aes256))
        #expect(info.matched == .user)
        #expect(try PDFInspector.inspect(output, password: JobSecret(utf8: "new owner")).matched.includesOwner)
        #expect(try QPDFDocumentReader.check(output, password: JobSecret(utf8: "new user")) == 0)
        let document = try #require(PDFDocument(url: output))
        #expect(document.isLocked)
        #expect(!document.unlock(withPassword: "not it"))
        #expect(document.unlock(withPassword: "new user"))
        #expect(document.pageCount == 2)
    }

    /// Without restrictions the owner password is the user password (D-M7-20): one secret in both roles.
    @Test func oneSecretCanBeBothUserAndOwner() throws {
        let dir = try TempDir()
        let input = try PDFFixtures.plain(in: dir.url)
        let output = dir.url.appending(path: "locked.pdf")
        let same = JobSecret(utf8: "one password")
        let parameters = R6Parameters(user: same, owner: same)

        try QPDFWriterBridge.write(input, password: nil, mode: .encryptR6(parameters), to: output)

        #expect(try PDFInspector.inspect(output, password: same).matched == .both)
    }

    @Test func aWrongPasswordIsRefused() throws {
        let dir = try TempDir()
        let rc4 = try PDFFixtures.encrypted(in: dir.url, keyLength: 40, user: "u-pass", owner: "o-pass")
        let output = dir.url.appending(path: "out.pdf")

        #expect(throws: PDFEngineError.wrongPassword) {
            try PDFInspector.inspect(rc4, password: JobSecret(utf8: "nope"))
        }
        #expect(throws: PDFEngineError.wrongPassword) {
            try QPDFDocumentReader.check(rc4, password: nil)
        }
        #expect(throws: PDFEngineError.wrongPassword) {
            try QPDFWriterBridge.write(rc4, password: JobSecret(utf8: "nope"), mode: .decrypt, to: output)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test func aFileThatIsNotAPDFIsDamagedAndAMissingOneIsAnIOError() throws {
        let dir = try TempDir()
        let text = try dir.file("note.pdf", "These words are not a PDF at all.")

        #expect(throws: PDFEngineError.damaged) { try PDFInspector.inspect(text, password: nil) }
        #expect(throws: PDFEngineError.io) {
            try PDFInspector.inspect(dir.url.appending(path: "missing.pdf"), password: nil)
        }
    }

    @Test func anUnknownSecurityHandlerIsUnsupported() throws {
        let dir = try TempDir()
        let objects = PDFFixtures.onePageObjects + ["<< /Filter /ZivletTestHandler /V 1 /R 2 >>"]
        let url = try PDFFixtures.raw(
            in: dir.url, name: "handler.pdf", objects: objects, trailer: "/Encrypt 5 0 R /ID [<00> <00>]")

        #expect(throws: PDFEngineError.unsupportedEncryption) { try QPDFDocumentReader.check(url, password: nil) }
    }

    @Test func aFileWithMorePagesThanTheLimitIsRefusedBeforeAnyWrite() throws {
        let dir = try TempDir()
        let input = try PDFFixtures.plain(in: dir.url, pages: 3)
        let output = dir.url.appending(path: "out.pdf")
        let limits = QPDFLimits(maxPages: 2)

        #expect(throws: PDFEngineError.limit) { try PDFInspector.inspect(input, password: nil, limits: limits) }
        #expect(throws: PDFEngineError.limit) {
            try QPDFWriterBridge.write(input, password: nil, limits: limits, mode: .preserve, to: output)
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test func anExistingOutputIsNeverOverwritten() throws {
        let dir = try TempDir()
        let input = try PDFFixtures.plain(in: dir.url)
        let output = try dir.file("taken.pdf", "keep me")

        #expect(throws: PDFEngineError.outputExists) {
            try QPDFWriterBridge.write(input, password: nil, mode: .preserve, to: output)
        }
        #expect(try String(contentsOf: output, encoding: .utf8) == "keep me")
    }

    @Test func aPasswordWithANulByteIsRefusedBeforeQPDFSeesIt() throws {
        let dir = try TempDir()
        let input = try PDFFixtures.plain(in: dir.url)

        #expect(throws: PDFEngineError.unusablePassword) {
            try PDFInspector.inspect(input, password: JobSecret(bytes: [0x61, 0x00, 0x62]))
        }
    }

    @Test func aRepairedFileCountsItsWarnings() throws {
        let dir = try TempDir()
        let url = try PDFFixtures.brokenCrossReference(in: dir.url)

        let info = try PDFInspector.inspect(url, password: nil)

        #expect(info.pageCount == 1)
        #expect(info.warningCount > 0)
        #expect(try QPDFDocumentReader.check(url, password: nil) > 0)
    }

    @Test func aFailedCheckIsDamaged() throws {
        let dir = try TempDir()
        let noPages = [
            "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [] /Count 0 >>",
        ]
        let url = try PDFFixtures.raw(in: dir.url, name: "empty.pdf", objects: noPages)

        #expect(throws: PDFEngineError.damaged) { try QPDFDocumentReader.check(url, password: nil) }
    }
}
