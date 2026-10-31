import Foundation
import ZivletCore
import ZivletEngineKit

/// P2-105's verify (plan 20e D3, D-M7-23, D-PDF-3): never trust a write. Every PDF output passes the shim's check (qpdf's
/// `--check` without its password echo) with the page count of the input, then a re-open that holds it to each
/// expectation, then a re-open by PDFKit, the reader the person will use. It runs in the worker only.
public enum PDFVerify {
    /// `secrets` holds what the job set: a `.locked` output opens with `newUser` and `owner`, a `.preserved` one with
    /// `input`. A password PDFKit cannot use is a note on the result, not a failure (OWN-PDF-1).
    public static func verify(
        _ output: URL, pageCount: Int, expect expectations: [PDFExpectation], secrets: JobSecrets? = nil,
        limits: QPDFLimits = .standard
    ) throws(PDFEngineError) -> PDFVerifyResult {
        let password = try openingPassword(expectations, secrets)
        let facts = try read(output, password: password, limits: limits)
        guard facts.pageCount == pageCount else { throw .verifyFailed(.pageCount) }
        for expectation in expectations {
            try hold(expectation, facts, output: output, owner: secrets?.owner, limits: limits)
        }
        return try PDFKitReopen.check(
            output, pageCount: pageCount, expect: expectations, user: password, owner: secrets?.owner)
    }

    /// A password nobody chose, for checking that a wrong one is refused.
    static func wrongPassword() -> String { "zivlet-verify-\(UUID().uuidString)" }

    private static func openingPassword(
        _ expectations: [PDFExpectation], _ secrets: JobSecrets?
    ) throws(PDFEngineError) -> JobSecret? {
        for expectation in expectations {
            switch expectation {
            case .locked:
                guard let user = secrets?.newUser else { throw .internalFailure }
                return user
            case .preserved: return secrets?.input
            case .unlocked, .formsKept: continue
            }
        }
        return nil
    }

    /// The check, then the facts. An output that the expected password cannot open has the wrong encryption.
    private static func read(
        _ output: URL, password: JobSecret?, limits: QPDFLimits
    ) throws(PDFEngineError) -> PDFPreflight {
        do {
            try QPDFDocumentReader.check(output, password: password, limits: limits)
            return try PDFInspector.inspect(output, password: password, limits: limits)
        } catch {
            switch error {
            case .wrongPassword: throw .verifyFailed(.encryption)
            case .damaged: throw .verifyFailed(.check)
            default: throw error
            }
        }
    }

    private static func hold(
        _ expectation: PDFExpectation, _ facts: PDFPreflight, output: URL, owner: JobSecret?, limits: QPDFLimits
    ) throws(PDFEngineError) {
        switch expectation {
        case .locked(let revision, let method, let ownerSeparate):
            guard
                case .standard(revision: revision, version: _, streams: method, strings: method, files: method) =
                    facts.encryption
            else { throw .verifyFailed(.encryption) }
            guard !facts.opensWithoutPassword else { throw .verifyFailed(.opensWithoutItsPassword) }
            try refuseWrongPassword(output, limits: limits)
            try holdOwner(ownerSeparate ? .separate(owner) : .same, facts, output: output, limits: limits)
        case .unlocked:
            guard facts.encryption == .none else { throw .verifyFailed(.encryption) }
        case .preserved(let input):
            guard facts.encryption == input.encryption, facts.opensWithoutPassword == input.opensWithoutPassword else {
                throw .verifyFailed(.encryption)
            }
            guard facts.permissions == input.permissions else { throw .verifyFailed(.permissions) }
        case .formsKept(let fields, let signatures):
            guard facts.fieldCount == fields, facts.signatureFieldCount == signatures else {
                throw .verifyFailed(.forms)
            }
        }
    }

    private static func refuseWrongPassword(_ output: URL, limits: QPDFLimits) throws(PDFEngineError) {
        do {
            _ = try PDFInspector.inspect(output, password: JobSecret(utf8: wrongPassword()), limits: limits)
        } catch {
            if error == .wrongPassword { return }
            throw error
        }
        throw .verifyFailed(.opensWithoutItsPassword)
    }

    private enum OwnerRule {
        case same
        case separate(JobSecret?)
    }

    /// qpdf says which password matched: both for one password, else the owner's opens as owner and the user's does not.
    private static func holdOwner(
        _ rule: OwnerRule, _ facts: PDFPreflight, output: URL, limits: QPDFLimits
    ) throws(PDFEngineError) {
        guard case .separate(let owner) = rule else {
            guard facts.matched == .both else { throw .verifyFailed(.ownerPassword) }
            return
        }
        guard let owner else { throw .internalFailure }
        guard facts.matched == .user else { throw .verifyFailed(.ownerPassword) }
        let opened: PDFPreflight
        do {
            opened = try PDFInspector.inspect(output, password: owner, limits: limits)
        } catch {
            throw error == .wrongPassword ? .verifyFailed(.ownerPassword) : error
        }
        guard opened.matched == .owner else { throw .verifyFailed(.ownerPassword) }
    }
}
