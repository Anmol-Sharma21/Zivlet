import ZivletEngineKit

/// What a PDF output must be once a tool has written it (D-M7-23). A job names every one that applies.
public enum PDFExpectation: Sendable, Equatable {
    /// Encrypted with `method` at `revision`, needing a password; `ownerSeparate`: the user and owner passwords differ.
    case locked(revision: Int, method: PDFCipher, ownerSeparate: Bool)
    /// No encryption left, restrictions included.
    case unlocked
    /// The same encryption, permissions and need for a password as the input had.
    case preserved(from: PDFPreflight)
    case formsKept(fieldCount: Int, signatureFieldCount: Int)
}

/// Why an output failed verification. None carries a path, a password or qpdf's own words.
public enum PDFVerifyFailure: Sendable, Equatable {
    case check, pageCount, encryption, opensWithoutItsPassword, ownerPassword, permissions, forms, reader

    /// The detail behind "The result didn't pass checks and wasn't saved."
    public var message: String {
        switch self {
        case .check: "The PDF did not pass qpdf's check."
        case .pageCount: "The PDF has a different number of pages than the original."
        case .encryption: "The PDF's encryption is not what the tool should have written."
        case .opensWithoutItsPassword: "The PDF opened without its password."
        case .ownerPassword: "The PDF's owner password is not what the tool should have set."
        case .permissions: "The PDF's permissions changed."
        case .forms: "The PDF has different form fields than the original."
        case .reader: "The PDF could not be opened again."
        }
    }
}

/// Something a person should know about an output that passed.
public enum PDFVerifyNote: Sendable, Equatable {
    /// qpdf reads it, but PDFKit, and so Preview on this Mac, cannot use this password (OWN-PDF-1).
    case macCannotOpen
}

public enum PDFVerifyResult: Sendable, Equatable {
    case passed
    case passedWithNote(PDFVerifyNote)
}
