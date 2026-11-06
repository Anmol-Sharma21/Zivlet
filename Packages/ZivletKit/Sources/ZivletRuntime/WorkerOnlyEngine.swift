import Foundation
import ZivletCore
import ZivletEngineKit
import ZivletIPC

/// An engine that exists only in the worker (the PDF engine, D-M7-16): the app answers `handles` from the pairs it is
/// given, without starting the worker, and runs every step there. With no worker, or one that does not host the engine,
/// a job fails with `.engineMissing` and never runs in the app (G-M7-19): an untrusted PDF never reaches qpdf here.
public struct WorkerOnlyEngine: Engine {
    public let id: EngineID
    let pairs: Set<ConversionPair>
    let selection: WorkerSelection

    public init(id: EngineID, pairs: Set<ConversionPair>, selection: WorkerSelection) {
        self.id = id
        self.pairs = pairs
        self.selection = selection
    }

    public func handles(_ pair: ConversionPair) -> Bool { pairs.contains(pair) }

    public func availability(of pair: ConversionPair) async -> RouteAvailability {
        handles(pair) ? .available : .unavailable([])
    }

    public func prepare(_ request: JobRequest, workspace: JobWorkspace) async throws(JobError) -> ExecutionPlan {
        try await prepare(request, workspace: workspace, secrets: nil)
    }

    public func execute(_ plan: ExecutionPlan, context: ExecutionContext) async throws(JobError) -> StagedOutput {
        try await execute(plan, context: context, secrets: nil)
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError) {
        try await verify(output, plan: plan, secrets: nil)
    }

    public func prepare(_ request: JobRequest, workspace: JobWorkspace, secrets: JobSecrets?) async throws(JobError)
        -> ExecutionPlan
    {
        try await remote().prepare(request, workspace: workspace, secrets: secrets)
    }

    public func execute(_ plan: ExecutionPlan, context: ExecutionContext, secrets: JobSecrets?) async throws(JobError)
        -> StagedOutput
    {
        try await remote().execute(plan, context: context, secrets: secrets)
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan, secrets: JobSecrets?) async throws(JobError) {
        try await remote().verify(output, plan: plan, secrets: secrets)
    }

    private func remote() async throws(JobError) -> RemoteEngine {
        guard case .worker(let connection, let capabilities) = await selection.choice(),
            let capability = capabilities.engine(id)
        else { throw .engineMissing(id) }
        return RemoteEngine(capability: capability, connection: connection)
    }
}
