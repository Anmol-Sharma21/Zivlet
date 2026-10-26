import Foundation
import ZivletCore
import ZivletEngineKit
import ZivletIPC

/// An `Engine` whose work runs in the worker (P2-01, plan 18c C5). `handles` and `availability` answer from the
/// capabilities the worker reported for this engine; `prepare`, `execute` and `verify` go through the connection.
/// Each `execute` call gets its own id for event routing and cancel (a plan does not carry its job id); spawned PIDs
/// and progress reach the context as the worker reports them.
public struct RemoteEngine: Engine {
    public let id: EngineID
    let capability: EngineCapability
    let connection: WorkerConnection

    public init(capability: EngineCapability, connection: WorkerConnection) {
        id = capability.id
        self.capability = capability
        self.connection = connection
    }

    public func handles(_ pair: ConversionPair) -> Bool { capability.handles(pair) }

    public func availability(of pair: ConversionPair) async -> RouteAvailability { capability.availability(of: pair) }

    public func prepare(_ request: JobRequest, workspace: JobWorkspace) async throws(JobError) -> ExecutionPlan {
        try await connection.prepare(request, workspace: workspace)
    }

    public func execute(_ plan: ExecutionPlan, context: ExecutionContext) async throws(JobError) -> StagedOutput {
        try await connection.execute(plan, job: JobID(), context: context)
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError) {
        try await connection.verify(output, plan: plan)
    }
}
