import Foundation
import ZivletCore
import ZivletEngineKit

/// Lock (P2-106, D-M7-20): AES-256 R6 and nothing weaker. Without restrictions the typed password is both user and
/// owner (17a §3.1); with them the owner password is the random one the app made and showed once. Metadata is
/// encrypted too. An input with any encryption is refused: LOCK · UNLOCK would have offered Unlock for it.
extension PDFEngine {
    func lockStage(
        _ source: URL, restrictions: PDFRestrictions?, secrets: JobSecrets?
    ) throws(JobError) -> (PDFStage, [PlanNote]) {
        let user = try Self.required(secrets?.newUser)
        if restrictions != nil { _ = try Self.required(secrets?.owner) }
        let facts = try inspect(source, password: nil)
        guard facts.encryption == .none else { throw .alreadyEncrypted }
        let notes: [PlanNote] = Self.isNotASCII(user) ? [.passwordNotForPreview] : []
        return (Self.stage(source, .lock(restrictions), facts: facts), notes)
    }

    static func lockParameters(_ restrictions: PDFRestrictions?, _ secrets: JobSecrets?) throws(JobError)
        -> R6Parameters
    {
        let user = try required(secrets?.newUser)
        let owner = restrictions == nil ? user : try required(secrets?.owner)
        return R6Parameters(user: user, owner: owner, permissions: R6Permissions(restrictions))
    }

    static func lockCheck(
        _ restrictions: PDFRestrictions?, _ secrets: JobSecrets?, forms: PDFExpectation
    ) throws(JobError) -> Check {
        let parameters = try lockParameters(restrictions, secrets)
        let separate = restrictions != nil
        let expectations: [PDFExpectation] = [
            .locked(revision: 6, method: .aes256, ownerSeparate: separate),
            .permits(parameters.permissions.pdfPermissions), forms,
        ]
        let opening = JobSecrets(newUser: parameters.user, owner: separate ? parameters.owner : nil)
        return Check(expectations: expectations, secrets: opening)
    }
}

extension R6Permissions {
    /// The /P bits of the Lock sheet's three choices (17a §3.1): copying is extraction (accessibility stays on, so
    /// screen readers keep working); editing is changing, annotating, filling forms and assembling.
    init(_ restrictions: PDFRestrictions?) {
        let chosen = restrictions ?? .none
        let printing: Printing =
            switch chosen.printing {
            case .full: .full
            case .low: .low
            case .none: .none
            }
        self.init(
            accessibility: true, extract: chosen.copying, assemble: chosen.editing,
            annotateAndForm: chosen.editing, formFilling: chosen.editing, modifyOther: chosen.editing,
            printing: printing)
    }

    /// The same permissions as pre-flight reads them back.
    var pdfPermissions: PDFPermissions {
        var bits: PDFPermissions = []
        if printing != .none { bits.insert(.printLowQuality) }
        if printing == .full { bits.insert(.printHighQuality) }
        let flags: [(Bool, PDFPermissions)] = [
            (accessibility, .accessibility), (extract, .copy), (assemble, .assemble), (annotateAndForm, .annotate),
            (formFilling, .fillForms), (modifyOther, .modify),
        ]
        for (allowed, bit) in flags where allowed { bits.insert(bit) }
        return bits
    }
}
