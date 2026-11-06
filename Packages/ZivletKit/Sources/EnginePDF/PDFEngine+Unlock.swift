import Foundation
import ZivletCore
import ZivletEngineKit

/// Unlock (P2-106, D-M7-21). The typed password is tried as typed, then in NFC and NFD, silently; none matching is
/// `wrongPassword`, and there is no attempt counter. A decrypted file is written only when the owner password matched
/// or the file grants every permission; otherwise the owner password is asked for, and nothing is written. A file that
/// opens without a password always needs its owner password, since its restrictions are all it has.
extension PDFEngine {
    func unlockStage(_ source: URL, secrets: JobSecrets?) throws(JobError) -> (PDFStage, [PlanNote]) {
        let shut = try inspect(source, password: nil)
        guard shut.encryption != .publicKey, shut.encryption != .unknown else { throw .unsupportedEncryption }
        let facts = try open(source, Self.opening(secrets))
        guard Self.mayRemoveEncryption(facts) else { throw .ownerPasswordNeeded }
        return (Self.stage(source, .remove, facts: facts), [])
    }

    /// The rule as one pure function: owner matched, or a password-protected file that grants everything.
    static func mayRemoveEncryption(_ facts: PDFPreflight) -> Bool {
        facts.matched.includesOwner || (!facts.opensWithoutPassword && facts.permissions == .all)
    }

    /// The password Unlock opens with: the typed one, or the owner password the restrictions sheet asked for.
    static func opening(_ secrets: JobSecrets?) -> JobSecret? {
        secrets?.input ?? secrets?.owner
    }

    /// The facts with the first form of `typed` that opens the file; with no password, what opens without one.
    func open(_ source: URL, _ typed: JobSecret?) throws(JobError) -> PDFPreflight {
        guard let typed else { return try inspect(source, password: nil) }
        var opened: PDFPreflight?
        try Self.eachForm(of: typed) { form throws(JobError) in
            do throws(JobError) {
                opened = try inspect(source, password: form)
                return true
            } catch {
                guard error == .wrongPassword else { throw error }
                return false
            }
        }
        guard let opened else { throw .wrongPassword }
        return opened
    }

    /// Calls `attempt` with the typed bytes, then each other Unicode form, until one is accepted. The extra forms
    /// are secrets of their own, wiped before this returns.
    static func eachForm(
        of typed: JobSecret, _ attempt: (JobSecret) throws(JobError) -> Bool
    ) throws(JobError) {
        if try attempt(typed) { return }
        let others = otherForms(of: typed)
        defer { others.forEach { $0.wipe() } }
        for form in others where try attempt(form) { return }
    }

    /// NFC and NFD of a UTF-8 password, each once, without the form already typed.
    private static func otherForms(of typed: JobSecret) -> [JobSecret] {
        guard let text = typed.withBytes({ String(bytes: $0, encoding: .utf8) }) else { return [] }
        return PasswordRules.variants(text).dropFirst().map(JobSecret.init(utf8:))
    }
}
