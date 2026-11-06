import CoreGraphics
import CoreText
import Foundation
import OCRTestSupport
import TestSupport
import Testing
import ZivletCore

@testable import EngineVision

/// Copy Text and Read QR on a locked PDF (P2-107, plan 20f E10): without its password it stays locked; the user
/// password opens it; Copy Text still needs the copy permission unless the owner password opened it (OWN-PDF-5); Read
/// QR renders pages, which needs no permission.
@Suite("Locked PDFs open in Copy Text and Read QR with their password")
struct LockedPDFInputTests {
    static let words = ["Zivlet keeps this page private", "The second page has its own line"]

    /// Two pages of our own words, AES-128 by CoreGraphics, with `user` and `owner` and the copy permission as given.
    static func lockedText(in dir: URL, user: String, owner: String, allowsCopying: Bool = true) throws -> URL {
        let url = dir.appending(path: "locked-\(UUID().uuidString.prefix(6)).pdf")
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let info: [CFString: Any] = [
            kCGPDFContextUserPassword: user, kCGPDFContextOwnerPassword: owner, kCGPDFContextEncryptionKeyLength: 128,
            kCGPDFContextAllowsCopying: allowsCopying,
        ]
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, info as CFDictionary))
        for line in words {
            context.beginPDFPage(nil)
            let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
            let text = NSAttributedString(string: line, attributes: [.init(kCTFontAttributeName as String): font])
            context.textPosition = CGPoint(x: 72, y: 684)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
            context.endPDFPage()
        }
        context.closePDF()
        return url
    }

    static func password(_ prefix: String) -> String { "\(prefix)-\(UUID().uuidString.prefix(10))" }

    /// The text layer is enough for these pages, so recognition must never run.
    struct NoRecognition: TextRecognizing {
        func recognize(_ image: CGImage, languages: [LanguageTag]) async throws(TextError) -> RecognizedPage {
            throw .recognitionFailed("recognition was not expected")
        }
    }

    func read(_ url: URL, _ password: String?) async throws(TextError) -> [String] {
        let secret = password.map(JobSecret.init(utf8:))
        return try await PDFTextSource.read(
            url, recognizer: NoRecognition(), languages: [.english], password: secret, progress: { _ in }
        ).map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    @Test func withoutItsPasswordOrWithAWrongOneItStaysLocked() async throws {
        let dir = try TempDir(prefix: "zivlet-locked-text")
        let url = try Self.lockedText(in: dir.url, user: Self.password("user"), owner: Self.password("owner"))
        await #expect(throws: TextError.pdfLocked) { try await read(url, nil) }
        await #expect(throws: TextError.pdfLocked) { try await read(url, Self.password("wrong")) }
    }

    /// CER 0: the text layer of each page is exactly the words drawn on it.
    @Test func theUserPasswordOpensItAndEveryWordComesBack() async throws {
        let dir = try TempDir(prefix: "zivlet-locked-text")
        let user = Self.password("user")
        let url = try Self.lockedText(in: dir.url, user: user, owner: Self.password("owner"))
        #expect(try await read(url, user) == Self.words)
    }

    @Test func withoutTheCopyPermissionOnlyTheOwnerPasswordCopies() async throws {
        let dir = try TempDir(prefix: "zivlet-locked-text")
        let (user, owner) = (Self.password("user"), Self.password("owner"))
        let url = try Self.lockedText(in: dir.url, user: user, owner: owner, allowsCopying: false)
        await #expect(throws: TextError.copyingNotAllowed) { try await read(url, user) }
        #expect(try await read(url, owner) == Self.words)
    }

    @Test func readQRFindsTheCodeOnPageTwoOfALockedPDF() async throws {
        let dir = try TempDir(prefix: "zivlet-locked-codes")
        let user = Self.password("user")
        let payload = "https://zivlet.app/locked-\(UUID().uuidString.prefix(6))"
        let url = try CodeFixtures.writePDF(
            [try CodeFixtures.blank(), try CodeFixtures.image(payload)], to: dir.url.appending(path: "menu.pdf"),
            userPassword: user)
        let reader = CodeReader()
        await #expect(throws: CodeError.pdfLocked) { try await reader.read(url) }
        let found = try await reader.read(url, password: JobSecret(utf8: user))
        #expect(found.map { $0.payload } == [payload] && found.first?.page == 2)
    }
}

/// A locked file's own job fills its place in the drop's text (plan 20f E10).
@Suite("A locked file's text joins the rest in drop order")
struct TextMergeTests {
    static func page(_ text: String) -> [RecognizedPage] { [RecognizedPage(text: text)] }

    @Test func theUnlockedFilesTextTakesItsPlaceAndItsSkipGoes() {
        let first = TextAssembly.combine(
            [FileText(name: "a.png", pages: Self.page("Alpha")), FileText(name: "b.pdf", pages: [])],
            skipped: [SkippedFile(name: "b.pdf", error: .pdfLocked)])
        let unlocked = TextAssembly.combine([FileText(name: "b.pdf", pages: Self.page("Bravo"))])

        let merged = TextAssembly.merge(first, replacing: ["b.pdf": unlocked])

        #expect(merged.perFile.map(\.name) == ["a.png", "b.pdf"])
        #expect(merged.text == "— a.png —\nAlpha\n\n— b.pdf —\nBravo\n")
        #expect(merged.skipped.isEmpty)
    }

    @Test func aFileLeftLockedKeepsItsSkip() {
        let first = TextAssembly.combine(
            [FileText(name: "b.pdf", pages: [])], skipped: [SkippedFile(name: "b.pdf", error: .pdfLocked)])
        #expect(TextAssembly.merge(first, replacing: [:]) == first)
    }
}
