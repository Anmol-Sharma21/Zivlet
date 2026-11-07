import CoreGraphics
import Foundation
import ZivletActions
import ZivletCore
import ZivletRuntime

/// How a LOCK · UNLOCK drop ended for the files it was given, in drop order.
public struct ProtectBatchOutcome: Sendable, Equatable {
    public let succeeded: [URL]
    /// Files whose password never opened them (or that were skipped in a per-file sheet).
    public let notOpened: [URL]
    /// The first sheet was cancelled: nothing ran.
    public let cancelled: Bool
    /// No sheet could open, because another tool's window is open (it was brought forward): nothing ran.
    public let unavailable: Bool

    public init(succeeded: [URL], notOpened: [URL], cancelled: Bool, unavailable: Bool = false) {
        self.succeeded = succeeded
        self.notOpened = notOpened
        self.cancelled = cancelled
        self.unavailable = unavailable
    }

    public static let nothing = ProtectBatchOutcome(succeeded: [], notOpened: [], cancelled: true)
    public static let unavailable = ProtectBatchOutcome(
        succeeded: [], notOpened: [], cancelled: false, unavailable: true)

    /// What the HUD says when no sheet could open; nil otherwise (a Cancel says nothing).
    public var refusal: ActionResult? {
        unavailable ? .failed(ActionCard(title: ToolWindowCoordinator.windowBusy)) : nil
    }

    /// The card's line for files that stayed locked (17b §3.3).
    public static func notUnlockedLine(_ count: Int) -> String { BatchPresentation.notUnlockedLine(count) }
}

/// One sheet per drop (17b §3.3, plan 20f E7). With "the same password for all" on (the default), one set of secrets
/// serves every job; files it did not open are offered again in a second sheet that lists them, and the files that
/// opened are not redone. With it off, each further file is asked for in drop order, in the second sheet and the
/// owner-needed sheet too. Every answer keeps its own job: a sheet switched to Change changes that file's password, and
/// Lock's restrictions go with the file they were chosen for (D-M7-60). An Unlock that needs the owner password asks
/// for it in the owner-needed sheet. The secrets go to the submitter, which wipes them as jobs end.
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
        let sheet = ProtectSheet(mode: mode, spec: spec, near: near)
        let reply = await prompter.ask(sheet.request(files))
        switch reply {
        case .cancelled: return .nothing
        case .unavailable: return .unavailable
        case .secrets: break
        }
        let answers = await spread(reply, over: files, sheet: sheet, again: false)
        let asked = files.filter { answers[$0] != nil }
        var states = await submit(answers, in: asked)
        states = await retryWrong(states, answers: answers, files: asked, near: near)
        if mode == .unlock || mode == .ownerNeeded {
            states = await askOwner(states, files: asked, near: near)
        }
        return Self.outcome(files, states)
    }

    /// The reply to a sheet that listed `files`: one answer for all of them, or, with the batch switch off, the first
    /// file's and then each further file's own sheet in drop order. A file whose own sheet is cancelled is skipped; once
    /// no sheet can open, the rest are too. `again`: the further sheets are second sheets (wrong password).
    private func spread(_ reply: PasswordAnswer, over files: [URL], sheet: ProtectSheet, again: Bool) async
        -> [URL: ProtectAnswer]
    {
        guard case .secrets(let secrets, let sameForAll, let restrictions) = reply, let head = files.first else {
            return [:]
        }
        let first = sheet.answer(secrets, restrictions)
        guard !sameForAll, files.count > 1 else { return Dictionary(files.map { ($0, first) }) { a, _ in a } }
        var answers = [head: first]
        for file in files.dropFirst() {
            let request = sheet.request([file])
            let own = again ? await prompter.retry(request, failed: Self.names([file])) : await prompter.ask(request)
            if own == .unavailable { break }
            if case .secrets(let secrets, _, let restrictions) = own {
                answers[file] = sheet.answer(secrets, restrictions)
            }
        }
        return answers
    }

    /// One job group per spec, in drop order, each with its files' own secrets.
    private func submit(_ answers: [URL: ProtectAnswer], in files: [URL]) async -> [URL: JobState] {
        var states: [URL: JobState] = [:]
        for (spec, group) in ProtectAnswer.groups(answers, in: files) {
            let pairs = group.compactMap { file in answers[file].map { (file, $0.secrets) } }
            let secrets = Dictionary(pairs) { first, _ in first }
            states.merge(await submitter.protect(group, spec: spec, secrets: secrets)) { _, new in new }
        }
        return states
    }

    /// The second sheet, in each file's own mode (Change asks for Change again), as long as some files answer that the
    /// password was wrong and the person types another. A file whose own retry sheet is cancelled is not asked again.
    private func retryWrong(
        _ states: [URL: JobState], answers: [URL: ProtectAnswer], files: [URL], near: CGPoint?
    ) async -> [URL: JobState] {
        var all = states
        var current = answers
        var givenUp: Set<URL> = []
        while case (let answer, let wrong)? = Self.nextWrong(files.filter { !givenUp.contains($0) }, all, current) {
            let sheet = ProtectSheet(mode: answer.mode, spec: answer.spec, near: near)
            let reply = await prompter.retry(sheet.request(wrong), failed: Self.names(wrong))
            guard case .secrets = reply else { break }
            let again = await spread(reply, over: wrong, sheet: sheet, again: true)
            givenUp.formUnion(wrong.filter { again[$0] == nil })
            current.merge(again) { _, new in new }
            all.merge(await submit(again, in: wrong)) { _, new in new }
        }
        return all
    }

    /// Files whose password opened them but may not lift their restrictions ask for the owner password (D-M7-21).
    private func askOwner(_ states: [URL: JobState], files: [URL], near: CGPoint?) async -> [URL: JobState] {
        let restricted = files.filter { states[$0] == .failed(.ownerPasswordNeeded) }
        guard !restricted.isEmpty else { return states }
        let sheet = ProtectSheet(mode: .ownerNeeded, spec: ProtectSpec(mode: .unlock), near: near)
        let answers = await spread(
            await prompter.ask(sheet.request(restricted)), over: restricted, sheet: sheet, again: false)
        guard !answers.isEmpty else { return states }
        let asked = restricted.filter { answers[$0] != nil }
        var all = states
        all.merge(await submit(answers, in: asked)) { _, new in new }
        return await retryWrong(all, answers: answers, files: asked, near: near)
    }

    /// The first wrong file's answer and every wrong file whose retry shows the same sheet, in drop order.
    private static func nextWrong(_ files: [URL], _ states: [URL: JobState], _ answers: [URL: ProtectAnswer])
        -> (ProtectAnswer, [URL])?
    {
        let wrong = files.filter { states[$0] == .failed(.wrongPassword) }
        guard let answer = wrong.first.flatMap({ answers[$0] }) else { return nil }
        return (answer, wrong.filter { answers[$0]?.mode == answer.mode })
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

/// One file's answer: its secrets, the job they are for, and the sheet its retry shows.
struct ProtectAnswer {
    let secrets: JobSecrets
    let spec: ProtectSpec
    let mode: PasswordMode

    /// `files` in drop order, grouped by spec in the order each spec first appears.
    static func groups(_ answers: [URL: ProtectAnswer], in files: [URL]) -> [(ProtectSpec, [URL])] {
        var groups: [(ProtectSpec, [URL])] = []
        for file in files {
            guard let spec = answers[file]?.spec else { continue }
            if let index = groups.firstIndex(where: { $0.0 == spec }) {
                groups[index].1.append(file)
            } else {
                groups.append((spec, [file]))
            }
        }
        return groups
    }
}

/// A kind of sheet: its mode, the job it starts from and where it opens.
struct ProtectSheet {
    let mode: PasswordMode
    let spec: ProtectSpec
    let near: CGPoint?

    func request(_ files: [URL]) -> PasswordRequest {
        PasswordRequest(mode: mode, files: ProtectBatch.names(files), near: near)
    }

    /// The job one answer asks for: Lock with the restrictions chosen in that sheet; Unlock as Change when that sheet
    /// switched to Change (it answered with a new password), whose retry is then a Change sheet.
    func answer(_ secrets: JobSecrets, _ restrictions: PDFRestrictions?) -> ProtectAnswer {
        let base: ProtectSpec =
            if case .lock = spec.mode {
                ProtectSpec(mode: .lock(restrictions), keepRestrictions: spec.keepRestrictions)
            } else {
                spec
            }
        let chosen = ProtectPlanner.spec(base, answered: secrets)
        let changed = mode == .unlock && chosen.mode == .changePassword
        return ProtectAnswer(secrets: secrets, spec: chosen, mode: changed ? .change : mode)
    }
}
