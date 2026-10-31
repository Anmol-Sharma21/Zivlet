import Foundation
import PDFKit
import ZivletCore
import ZivletEngineKit

/// The second reader of D-M7-23: PDFKit, which is what Preview and the rest of the Mac use, so an output that only qpdf
/// can read is caught here. A password reaches PDFKit as a `String`, which cannot be wiped (best effort, G-M7-5); this
/// runs in the worker, and the string lives only for the call.
enum PDFKitReopen {
    static func check(
        _ url: URL, pageCount: Int, expect expectations: [PDFExpectation], user: JobSecret?, owner: JobSecret?
    ) throws(PDFEngineError) -> PDFVerifyResult {
        for case .locked(_, _, let ownerSeparate) in expectations {
            guard let user else { throw .internalFailure }
            return try checkLocked(url, pageCount: pageCount, user: user, owner: ownerSeparate ? owner : nil)
        }
        return try checkOpen(url, pageCount: pageCount, noEncryption: expectations.contains(.unlocked), password: user)
    }

    /// Locked until the right password; a wrong one refused; each password opens with the rights it should have.
    private static func checkLocked(
        _ url: URL, pageCount: Int, user: JobSecret, owner: JobSecret?
    ) throws(PDFEngineError) -> PDFVerifyResult {
        let closed = try document(url)
        guard closed.isLocked else { throw .verifyFailed(.encryption) }
        guard !closed.unlock(withPassword: PDFVerify.wrongPassword()) else {
            throw .verifyFailed(.opensWithoutItsPassword)
        }
        let byUser = try open(url, with: user, pageCount: pageCount, rights: owner == nil ? .owner : .user)
        guard let owner else { return byUser }
        let byOwner = try open(url, with: owner, pageCount: pageCount, rights: .owner)
        return byUser == .passed ? byOwner : byUser
    }

    private static func checkOpen(
        _ url: URL, pageCount: Int, noEncryption: Bool, password: JobSecret?
    ) throws(PDFEngineError) -> PDFVerifyResult {
        let reopened = try document(url)
        if noEncryption, reopened.isEncrypted { throw .verifyFailed(.encryption) }
        if reopened.isLocked, let password {
            return try open(url, with: password, pageCount: pageCount, rights: nil)
        }
        guard reopened.pageCount == pageCount else { throw .verifyFailed(.pageCount) }
        return .passed
    }

    /// A fresh document, so one password's rights never carry over to the next.
    private static func open(
        _ url: URL, with password: JobSecret, pageCount: Int, rights: PDFDocumentPermissions?
    ) throws(PDFEngineError) -> PDFVerifyResult {
        let reopened = try document(url)
        guard let text = text(of: password), reopened.unlock(withPassword: text) else {
            guard isNotASCII(password) else { throw .verifyFailed(.reader) }
            return .passedWithNote(.macCannotOpen)
        }
        guard reopened.pageCount == pageCount else { throw .verifyFailed(.pageCount) }
        if let rights, reopened.permissionsStatus != rights { throw .verifyFailed(.ownerPassword) }
        return .passed
    }

    private static func document(_ url: URL) throws(PDFEngineError) -> PDFDocument {
        guard let document = PDFDocument(url: url) else { throw .verifyFailed(.reader) }
        return document
    }

    private static func text(of secret: JobSecret) -> String? {
        secret.withBytes { bytes in String(bytes: bytes, encoding: .utf8) }
    }

    private static func isNotASCII(_ secret: JobSecret) -> Bool {
        secret.withBytes { bytes in bytes.contains { $0 >= 0x80 } }
    }
}
