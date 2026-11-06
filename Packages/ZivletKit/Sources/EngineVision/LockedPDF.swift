import Foundation
import PDFKit
import ZivletCore

/// Opens a PDF for Copy Text or Read QR with the password its job carries (P2-107, plan 20f E10), in the worker only.
/// The password is tried as typed, then in NFC and NFD, silently; one that opens nothing leaves the file locked, so
/// the app asks again. PDFKit takes a `String`, which cannot be wiped (best effort, G-M7-5).
enum LockedPDF {
    /// The document, unlocked when it was locked and the password opens it; still locked otherwise.
    static func open(_ url: URL, password: JobSecret?) -> PDFDocument? {
        guard let document = PDFDocument(url: url) else { return nil }
        guard document.isLocked, let password,
            let typed = password.withBytes({ String(bytes: $0, encoding: .utf8) })
        else { return document }
        for form in PasswordRules.variants(typed) where document.unlock(withPassword: form) { break }
        return document
    }

    /// OWN-PDF-5: copying text needs the copy permission, unless the owner password opened the file.
    static func mayCopy(_ document: PDFDocument) -> Bool {
        document.allowsCopying || document.permissionsStatus == .owner
    }
}
