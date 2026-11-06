import Foundation
import ZivletCore
import ZivletEngineKit

/// Change password (P2-106, D-M7-22). The current password opens the file (each Unicode form, as Unlock tries); a file
/// with restrictions needs its owner password, which then stays the owner password, with the same restrictions. A
/// file without restrictions gets the new password as both. The output is always R6 AES-256, so an RC4 or AES-128
/// input is upgraded; the owner password is known in both cases, so nothing weaker is ever kept (P2-107).
extension PDFEngine {
    func changeStage(_ source: URL, secrets: JobSecrets?) throws(JobError) -> (PDFStage, [PlanNote]) {
        let newUser = try Self.required(secrets?.newUser)
        let current = try Self.required(secrets?.input)
        let shut = try inspect(source, password: nil)
        guard shut.encryption != .publicKey, shut.encryption != .unknown else { throw .unsupportedEncryption }
        let facts = try open(source, current)
        let restricted = facts.permissions != .all
        guard !restricted || facts.matched.includesOwner else { throw .ownerPasswordNeeded }
        let notes: [PlanNote] = Self.isNotASCII(newUser) ? [.passwordNotForPreview] : []
        return (Self.stage(source, .change(keepOwner: restricted), facts: facts), notes)
    }

    /// The new user password; the typed owner password and the input's permissions when they are kept.
    static func changeParameters(_ stage: PDFStage, keepOwner: Bool, _ secrets: JobSecrets?) throws(JobError)
        -> R6Parameters
    {
        let user = try required(secrets?.newUser)
        let owner = keepOwner ? try required(secrets?.input) : user
        return R6Parameters(user: user, owner: owner, permissions: keepOwner ? R6Permissions(stage.permissions) : .all)
    }

    static func changeCheck(
        _ stage: PDFStage, keepOwner: Bool, _ secrets: JobSecrets?, forms: PDFExpectation
    ) throws(JobError) -> Check {
        let parameters = try changeParameters(stage, keepOwner: keepOwner, secrets)
        let expectations: [PDFExpectation] = [
            .locked(revision: 6, method: .aes256, ownerSeparate: keepOwner),
            .permits(parameters.permissions.pdfPermissions), forms,
        ]
        return Check(
            expectations: expectations,
            secrets: JobSecrets(newUser: parameters.user, owner: keepOwner ? parameters.owner : nil))
    }
}

extension R6Permissions {
    /// The R6 form of what a file allows, so Change can keep it (D-M7-22).
    init(_ bits: PDFPermissions) {
        let printing: Printing =
            bits.contains(.printHighQuality) ? .full : bits.contains(.printLowQuality) ? .low : .none
        self.init(
            accessibility: bits.contains(.accessibility), extract: bits.contains(.copy),
            assemble: bits.contains(.assemble), annotateAndForm: bits.contains(.annotate),
            formFilling: bits.contains(.fillForms), modifyOther: bits.contains(.modify), printing: printing)
    }
}
