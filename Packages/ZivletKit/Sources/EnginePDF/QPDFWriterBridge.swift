import CZivletPDF
import Foundation
import ZivletCore

/// What an R6 (AES-256) output allows; every permission on by default (no restrictions, 17a §3.1).
public struct R6Permissions: Sendable, Equatable {
    public enum Printing: Sendable, Equatable { case full, low, none }

    public let accessibility: Bool
    public let extract: Bool
    public let assemble: Bool
    public let annotateAndForm: Bool
    public let formFilling: Bool
    public let modifyOther: Bool
    public let printing: Printing

    public init(
        accessibility: Bool = true, extract: Bool = true, assemble: Bool = true, annotateAndForm: Bool = true,
        formFilling: Bool = true, modifyOther: Bool = true, printing: Printing = .full
    ) {
        self.accessibility = accessibility
        self.extract = extract
        self.assemble = assemble
        self.annotateAndForm = annotateAndForm
        self.formFilling = formFilling
        self.modifyOther = modifyOther
        self.printing = printing
    }

    public static let all = R6Permissions()

    var shimPrint: zv_pdf_print {
        switch printing {
        case .full: ZV_PDF_PRINT_FULL
        case .low: ZV_PDF_PRINT_LOW
        case .none: ZV_PDF_PRINT_NONE
        }
    }
}

/// The passwords and permissions of an AES-256 R6 output.
public struct R6Parameters: Sendable, Equatable {
    public let user: JobSecret
    public let owner: JobSecret
    public let permissions: R6Permissions
    public let encryptMetadata: Bool

    public init(user: JobSecret, owner: JobSecret, permissions: R6Permissions = .all, encryptMetadata: Bool = true) {
        self.user = user
        self.owner = owner
        self.permissions = permissions
        self.encryptMetadata = encryptMetadata
    }
}

/// Writes PDFs through the shim (plan 20d C4). RC4 and AES-128 are never written: the only encryption is R6.
public enum QPDFWriterBridge {
    public enum Mode: Sendable, Equatable {
        /// The input's own encryption (none stays none).
        case preserve
        /// No encryption.
        case decrypt
        case encryptR6(R6Parameters)
    }

    /// Writes `input`, opened with `password`, to `output`, which must not exist; a failed write leaves nothing there.
    public static func write(
        _ input: URL, password: JobSecret?, limits: QPDFLimits = .standard, mode: Mode, to output: URL
    ) throws(PDFEngineError) {
        var shimLimits = limits.shimValue
        let status = output.withUnsafeFileSystemRepresentation { outPath -> zv_pdf_status in
            guard let outPath else { return ZV_PDF_IO }
            return withShimMode(mode) { shimMode, params in
                ShimCall.status(input, password) { inPath, bytes in
                    zv_pdf_write(inPath, bytes.pointer, bytes.count, &shimLimits, shimMode, params, outPath)
                }
            }
        }
        try PDFEngineError.check(status)
    }

    /// `body` with the shim's mode and, for R6, its parameters over the passwords' own buffers.
    private static func withShimMode(
        _ mode: Mode, _ body: (zv_pdf_mode, UnsafePointer<zv_pdf_r6_params>?) -> zv_pdf_status
    ) -> zv_pdf_status {
        switch mode {
        case .preserve: return body(ZV_PDF_MODE_PRESERVE, nil)
        case .decrypt: return body(ZV_PDF_MODE_DECRYPT, nil)
        case .encryptR6(let parameters):
            return ShimCall.withBytes(of: parameters.user) { user in
                ShimCall.withBytes(of: parameters.owner) { owner in
                    var params = shimParameters(parameters, user: user, owner: owner)
                    return body(ZV_PDF_MODE_ENCRYPT_R6, &params)
                }
            }
        }
    }

    private static func shimParameters(
        _ parameters: R6Parameters, user: ShimCall.Bytes, owner: ShimCall.Bytes
    ) -> zv_pdf_r6_params {
        let permissions = parameters.permissions
        return zv_pdf_r6_params(
            user: user.pointer, user_length: user.count, owner: owner.pointer, owner_length: owner.count,
            allow_accessibility: flag(permissions.accessibility), allow_extract: flag(permissions.extract),
            allow_assemble: flag(permissions.assemble), allow_annotate_and_form: flag(permissions.annotateAndForm),
            allow_form_filling: flag(permissions.formFilling), allow_modify_other: flag(permissions.modifyOther),
            print: permissions.shimPrint, encrypt_metadata: flag(parameters.encryptMetadata))
    }

    private static func flag(_ value: Bool) -> Int32 { value ? 1 : 0 }
}
