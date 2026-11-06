import Foundation
import ZivletCore
import ZivletEngineKit

/// LOCK · UNLOCK's three modes in the engine (plan 20f E4–E6): what prepare reads, what execute writes and what verify
/// holds the output to. Each mode's own rules live in `PDFEngine+Lock`, `+Unlock` and `+Change`.
extension PDFEngine {
    static let modeMessage = "mode not handled"

    /// What a write opens the input with and how it encrypts the output.
    struct Write {
        let password: JobSecret?
        let mode: QPDFWriterBridge.Mode
    }

    /// What verify expects of an output and the passwords that open it.
    struct Check {
        let expectations: [PDFExpectation]
        let secrets: JobSecrets?
    }

    /// The plan of one protect job: pre-flight decides, nothing is written yet.
    func plan(
        _ spec: ProtectSpec, source: URL, workspace: JobWorkspace, secrets: JobSecrets?
    ) throws(JobError) -> ExecutionPlan {
        try PDFLimits.check(fileAt: source)
        let (stage, notes) = try protectStage(spec, source: source, secrets: secrets)
        do {
            return try ExecutionPlan(
                engine: .pdf, stages: [.pdf(stage)], stageWeights: [1], lanes: [.cpu], outputFormat: .pdf,
                stagedFile: workspace.stagedFile, notes: notes)
        } catch {
            throw .internalInvariant(Self.planMessage)
        }
    }

    private func protectStage(
        _ spec: ProtectSpec, source: URL, secrets: JobSecrets?
    ) throws(JobError) -> (PDFStage, [PlanNote]) {
        switch spec.mode {
        case .lock(let restrictions): try lockStage(source, restrictions: restrictions, secrets: secrets)
        case .unlock: try unlockStage(source, secrets: secrets)
        case .changePassword: throw .internalInvariant(Self.modeMessage)
        }
    }

    /// The input's facts, read under the watchdog with `password` (nil: none).
    func inspect(_ source: URL, password: JobSecret?) throws(JobError) -> PDFPreflight {
        let limits = self.limits
        do throws(PDFEngineError) {
            return try watchdog.guarding(inputBytes: Self.size(of: source)) { () throws(PDFEngineError) in
                try PDFInspector.inspect(source, password: password, limits: limits)
            }
        } catch {
            throw Self.jobError(error)
        }
    }

    /// The stage with the input's facts that every output keeps.
    static func stage(_ source: URL, _ encryption: PDFStage.Encryption, facts: PDFPreflight) -> PDFStage {
        PDFStage(
            source: source, encryption: encryption, pageCount: facts.pageCount, permissions: facts.permissions,
            fieldCount: facts.fieldCount, signatureFieldCount: facts.signatureFieldCount)
    }

    static func write(_ stage: PDFStage, _ secrets: JobSecrets?) throws(JobError) -> Write {
        switch stage.encryption {
        case .keep: Write(password: secrets?.input, mode: .preserve)
        case .remove: Write(password: opening(secrets), mode: .decrypt)
        case .lock(let restrictions): Write(password: nil, mode: .encryptR6(try lockParameters(restrictions, secrets)))
        case .change: throw .internalInvariant(modeMessage)
        }
    }

    static func check(_ stage: PDFStage, _ secrets: JobSecrets?) throws(JobError) -> Check {
        let forms = PDFExpectation.formsKept(
            fieldCount: stage.fieldCount, signatureFieldCount: stage.signatureFieldCount)
        switch stage.encryption {
        case .keep: return Check(expectations: [], secrets: nil)
        case .remove: return Check(expectations: [.unlocked, forms], secrets: nil)
        case .lock(let restrictions): return try lockCheck(restrictions, secrets, forms: forms)
        case .change: throw .internalInvariant(modeMessage)
        }
    }

    /// The plan expected PDFKit to refuse a password that is not ASCII; when it opens the output after all, the note
    /// is taken back.
    static func withdrawnNotes(_ notes: [PlanNote], staged: URL, secrets: JobSecrets?) -> [PlanNote] {
        guard notes.contains(.passwordNotForPreview), let user = secrets?.newUser,
            PDFKitReopen.opens(staged, with: user)
        else { return [] }
        return [.passwordNotForPreview]
    }

    /// A password with any byte past ASCII, which PDFKit cannot use on this SDK (OWN-PDF-1).
    static func isNotASCII(_ secret: JobSecret) -> Bool {
        secret.withBytes { bytes in bytes.contains { $0 >= 0x80 } }
    }

    /// The secret, or a bug: the app sends every password a mode needs (D-M7-14).
    static func required(_ secret: JobSecret?) throws(JobError) -> JobSecret {
        guard let secret, !secret.isEmpty else { throw .internalInvariant(passwordMessage) }
        return secret
    }
}
