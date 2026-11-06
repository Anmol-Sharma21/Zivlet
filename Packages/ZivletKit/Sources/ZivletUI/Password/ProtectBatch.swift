import CoreGraphics
import Foundation
import ZivletCore
import ZivletRuntime

/// How a LOCK · UNLOCK drop ended for the files it was given, in drop order.
public struct ProtectBatchOutcome: Sendable, Equatable {
    public let succeeded: [URL]
    /// Files whose password never opened them (or that were skipped in a per-file sheet).
    public let notOpened: [URL]
    /// The first sheet was cancelled: nothing ran.
    public let cancelled: Bool

    public static let nothing = ProtectBatchOutcome(succeeded: [], notOpened: [], cancelled: true)

    /// The card's line for files that stayed locked (17b §3.3).
    public static func notUnlockedLine(_ count: Int) -> String { BatchPresentation.notUnlockedLine(count) }
}

/// One sheet per drop (17b §3.3, plan 20f E7). With "the same password for all" on (the default), one set of secrets
/// serves every job; files it did not open are offered again in a second sheet that lists them, and the files that
/// opened are not redone. With it off, each further file is asked for in drop order. An Unlock that needs the owner
/// password asks for it in the owner-needed sheet. The secrets go to the submitter, which wipes them as jobs end.
@MainActor
public struct ProtectBatch {
    private let prompter: any PasswordPrompting
    private let submitter: any ProtectSubmitting

    public init(prompter: any PasswordPrompting, submitter: any ProtectSubmitting) {
        self.prompter = prompter
        self.submitter = submitter
    }

    public func run(_ files: [URL], mode: PasswordMode, spec: ProtectSpec, near: CGPoint?) async
        -> ProtectBatchOutcome
    {
        let request = PasswordRequest(mode: mode, files: Self.names(files), near: near)
        guard case .secrets(let first, let sameForAll, let restrictions) = await prompter.ask(request) else {
            return .nothing
        }
        let chosen = Self.spec(spec, restrictions)
        var secrets: [URL: JobSecrets] = [:]
        for file in sameForAll ? files : Array(files.prefix(1)) { secrets[file] = first }
        if !sameForAll { secrets.merge(await askEach(files.dropFirst(), mode: mode, near: near)) { old, _ in old } }
        let asked = files.filter { secrets[$0] != nil }
        var states = await submitter.protect(asked, spec: chosen, secrets: secrets)
        states = await retryWrong(states, files: asked, mode: mode, spec: chosen, near: near)
        if mode == .unlock || mode == .ownerNeeded {
            states = await askOwner(states, files: asked, near: near)
        }
        return Self.outcome(files, states)
    }

    /// The person's own password for each further file, in drop order; a cancelled one is skipped.
    private func askEach(_ files: ArraySlice<URL>, mode: PasswordMode, near: CGPoint?) async -> [URL: JobSecrets] {
        var secrets: [URL: JobSecrets] = [:]
        for file in files {
            let request = PasswordRequest(mode: mode, files: [file.lastPathComponent], near: near)
            if case .secrets(let answer, _, _) = await prompter.ask(request) { secrets[file] = answer }
        }
        return secrets
    }

    /// The second sheet, as long as some files answer that the password was wrong and the person types another.
    private func retryWrong(
        _ states: [URL: JobState], files: [URL], mode: PasswordMode, spec: ProtectSpec, near: CGPoint?
    ) async -> [URL: JobState] {
        var all = states
        while mode != .lock {
            let wrong = files.filter { all[$0] == .failed(.wrongPassword) }
            guard !wrong.isEmpty else { break }
            let request = PasswordRequest(mode: mode, files: Self.names(wrong), near: near)
            guard case .secrets(let again, _, _) = await prompter.retry(request, failed: Self.names(wrong)) else {
                break
            }
            let next = await submitter.protect(
                wrong, spec: spec, secrets: Dictionary(wrong.map { ($0, again) }) { a, _ in a })
            all.merge(next) { _, new in new }
        }
        return all
    }

    /// Files whose password opened them but may not lift their restrictions ask for the owner password (D-M7-21).
    private func askOwner(_ states: [URL: JobState], files: [URL], near: CGPoint?) async -> [URL: JobState] {
        let restricted = files.filter { states[$0] == .failed(.ownerPasswordNeeded) }
        guard !restricted.isEmpty else { return states }
        let request = PasswordRequest(mode: .ownerNeeded, files: Self.names(restricted), near: near)
        guard case .secrets(let owner, _, _) = await prompter.ask(request) else { return states }
        let unlock = ProtectSpec(mode: .unlock)
        var all = states
        let next = await submitter.protect(
            restricted, spec: unlock, secrets: Dictionary(restricted.map { ($0, owner) }) { a, _ in a })
        all.merge(next) { _, new in new }
        return await retryWrong(all, files: restricted, mode: .ownerNeeded, spec: unlock, near: near)
    }

    /// Lock's restrictions come from the sheet.
    private static func spec(_ spec: ProtectSpec, _ restrictions: PDFRestrictions?) -> ProtectSpec {
        guard case .lock = spec.mode else { return spec }
        return ProtectSpec(mode: .lock(restrictions), keepRestrictions: spec.keepRestrictions)
    }

    private static func outcome(_ files: [URL], _ states: [URL: JobState]) -> ProtectBatchOutcome {
        let succeeded = files.filter { states[$0]?.published != nil }
        let notOpened = files.filter { file in
            guard let state = states[file] else { return true }
            return state == .failed(.wrongPassword) || state == .failed(.ownerPasswordNeeded)
        }
        return ProtectBatchOutcome(succeeded: succeeded, notOpened: notOpened, cancelled: false)
    }

    static func names(_ files: [URL]) -> [String] { files.map(\.lastPathComponent) }
}
