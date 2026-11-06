import Foundation
import Synchronization
import ZivletCore
import ZivletEngineKit

/// A PDF engine for the secrets tests (plan 20f E3): it takes protect jobs (`pdf → pdf`), records what each step was
/// given, and keeps the secret objects so a test can see them wiped afterwards. It writes a few bytes and never runs
/// qpdf.
public final class SecretEngine: Engine, @unchecked Sendable {
    public enum Behaviour: Sendable {
        case succeed
        case fail(JobError)
        /// The first execute ends as a crashed worker's would; the retry succeeds.
        case crashOnce
        case waitUntilCancelled
    }

    /// One step's view of its job's passwords: the step and the input's and new user's bytes as it read them.
    public struct Seen: Sendable, Equatable {
        public let step: String
        public let input: [UInt8]?
        public let newUser: [UInt8]?

        public init(step: String, input: [UInt8]?, newUser: [UInt8]?) {
            self.step = step
            self.input = input
            self.newUser = newUser
        }
    }

    public let id = EngineID.pdf
    public let behaviour: Behaviour
    public let reachedExecute = Signal()
    private let state = Mutex<(seen: [Seen], secrets: [JobSecret], executes: Int)>(([], [], 0))

    public init(_ behaviour: Behaviour = .succeed) {
        self.behaviour = behaviour
    }

    public var seen: [Seen] { state.withLock(\.seen) }

    /// Every secret object a step was given.
    public var secretsGiven: [JobSecret] { state.withLock(\.secrets) }

    public func handles(_ pair: ConversionPair) -> Bool { pair.source == .pdf && pair.target == .pdf }

    public func availability(of pair: ConversionPair) async -> RouteAvailability { .available }

    public func prepare(_ request: JobRequest, workspace: JobWorkspace) async throws(JobError) -> ExecutionPlan {
        try await prepare(request, workspace: workspace, secrets: nil)
    }

    public func prepare(_ request: JobRequest, workspace: JobWorkspace, secrets: JobSecrets?) async throws(JobError)
        -> ExecutionPlan
    {
        record("prepare", secrets)
        do {
            let stage = PDFStage(source: request.input.url, encryption: .remove, pageCount: 1)
            return try ExecutionPlan(
                engine: .pdf, stages: [.pdf(stage)], stageWeights: [1], lanes: [.cpu], outputFormat: .pdf,
                stagedFile: workspace.stagedFile)
        } catch {
            throw .internalInvariant("secret engine plan")
        }
    }

    public func execute(_ plan: ExecutionPlan, context: ExecutionContext) async throws(JobError) -> StagedOutput {
        try await execute(plan, context: context, secrets: nil)
    }

    public func execute(_ plan: ExecutionPlan, context: ExecutionContext, secrets: JobSecrets?) async throws(JobError)
        -> StagedOutput
    {
        record("execute", secrets)
        let count = state.withLock { state in
            state.executes += 1
            return state.executes
        }
        reachedExecute.fire()
        switch behaviour {
        case .succeed: break
        case .fail(let error): throw error
        case .crashOnce where count == 1: throw .workerCrashed
        case .crashOnce: break
        case .waitUntilCancelled:
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(2)) }
            throw .cancelled
        }
        do {
            try Data("%PDF-1.7\n".utf8).write(to: plan.stagedFile)
        } catch {
            throw .writeFailed("secret engine")
        }
        return StagedOutput(format: .pdf, url: plan.stagedFile, byteCount: 9)
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError) {
        try await verify(output, plan: plan, secrets: nil)
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan, secrets: JobSecrets?) async throws(JobError) {
        record("verify", secrets)
    }

    private func record(_ step: String, _ secrets: JobSecrets?) {
        let seen = Seen(
            step: step, input: secrets?.input?.withBytes { Array($0) },
            newUser: secrets?.newUser?.withBytes { Array($0) })
        state.withLock { state in
            state.seen.append(seen)
            state.secrets += secrets?.all ?? []
        }
    }
}
