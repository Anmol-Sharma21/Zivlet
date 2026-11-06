import CoreGraphics
import Foundation
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import ZivletRuntime

/// LOCK · UNLOCK's decision after a drop (D-M7-19), pure: from each file's pre-flight, which sheet to show. None
/// encrypted → Lock; every readable one encrypted → Unlock (Change is a mode inside it), or the owner-needed sheet when
/// all of them only have restrictions; mixed → Lock, whose job leaves the locked files as they are and lists them
/// (OS-M7-3). Files the worker could not read go along, and their job reports why; with none readable, no sheet opens.
public enum ProtectPlanner {
    public enum Decision: Sendable, Equatable {
        case ask(PasswordMode, ProtectSpec, [URL])
        /// Nothing to ask: run the jobs without secrets, so each says why it cannot be read.
        case report(ProtectSpec, [URL])
    }

    public static func decide(_ inspected: [(URL, PDFInspection)]) -> Decision {
        let files = inspected.map(\.0)
        let read = inspected.compactMap { _, answer -> PDFPreflight? in
            guard case .read(let preflight) = answer else { return nil }
            return preflight
        }
        let unlock = ProtectSpec(mode: .unlock)
        guard !read.isEmpty else { return .report(unlock, files) }
        let encrypted = read.filter { $0.encryption != .none }
        guard !encrypted.isEmpty, encrypted.count == read.count else {
            return .ask(.lock, ProtectSpec(mode: .lock(nil)), files)
        }
        let restrictionsOnly = encrypted.allSatisfy(\.opensWithoutPassword)
        return .ask(restrictionsOnly ? .ownerNeeded : .unlock, unlock, files)
    }

    /// The Unlock sheet's "Change password…" answers with a new password: the jobs change it instead (D-M7-22).
    public static func spec(_ spec: ProtectSpec, answered secrets: JobSecrets) -> ProtectSpec {
        guard spec.mode == .unlock, secrets.newUser != nil else { return spec }
        return ProtectSpec(mode: .changePassword, keepRestrictions: true)
    }
}

/// A drop on LOCK · UNLOCK from start to end (plan 20f E9): the worker's pre-flight without a password, the planner's
/// sheet, then the batch. The app gives it the real service and prompter; tests give fakes.
@MainActor
public struct ProtectFlow {
    public typealias Inspect = @Sendable ([URL]) async -> [PDFInspection]

    private let inspect: Inspect
    private let prompter: any PasswordPrompting
    private let submitter: any ProtectSubmitting

    public init(inspect: @escaping Inspect, prompter: any PasswordPrompting, submitter: any ProtectSubmitting) {
        self.inspect = inspect
        self.prompter = prompter
        self.submitter = submitter
    }

    @discardableResult
    public func run(_ files: [URL], near point: CGPoint?) async -> ProtectBatchOutcome {
        let answers = await inspect(files)
        switch ProtectPlanner.decide(Array(zip(files, answers))) {
        case .report(let spec, let files):
            _ = await submitter.protect(files, spec: spec, secrets: [:])
            return .nothing
        case .ask(let mode, let spec, let files):
            return await ProtectBatch(prompter: prompter, submitter: submitter)
                .run(files, mode: mode, spec: spec, near: point)
        }
    }

    /// A failed card's Retry: the same mode's sheet for its failed files.
    @discardableResult
    public func retry(_ retry: ProtectRetry, near point: CGPoint?) async -> ProtectBatchOutcome {
        let (mode, spec): (PasswordMode, ProtectSpec) =
            switch retry.mode {
            case .lock: (.lock, ProtectSpec(mode: retry.mode))
            case .unlock: (.unlock, ProtectSpec(mode: .unlock))
            case .changePassword: (.change, ProtectSpec(mode: .changePassword, keepRestrictions: true))
            }
        return await ProtectBatch(prompter: prompter, submitter: submitter)
            .run(retry.files, mode: mode, spec: spec, near: point)
    }
}
