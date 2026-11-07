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
        try await prepare(request, workspace: workspace, secrets: nil)
    }

    public func execute(_ plan: ExecutionPlan, context: ExecutionContext) async throws(JobError) -> StagedOutput {
        try await execute(plan, context: context, secrets: nil)
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError) {
        try await verify(output, plan: plan, secrets: nil)
    }

    /// The job's passwords go with each of its own requests, and with nothing else (plan 20f E3).
    public func prepare(_ request: JobRequest, workspace: JobWorkspace, secrets: JobSecrets?) async throws(JobError)
        -> ExecutionPlan
    {
        try await connection.prepare(request, workspace: workspace, secrets: secrets)
    }

    public func execute(_ plan: ExecutionPlan, context: ExecutionContext, secrets: JobSecrets?) async throws(JobError)
        -> StagedOutput
    {
        try await connection.execute(plan, job: JobID(), context: context, secrets: secrets)
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan, secrets: JobSecrets?) async throws(JobError) {
        try await connection.verify(output, plan: plan, secrets: secrets)
    }
}

/// An engine whose steps may run in the worker: its jobs go through the worker's isolation (D-M7-66).
protocol WorkerHosted {
    var workerIsolation: WorkerIsolation { get }
}

extension RemoteEngine: WorkerHosted {
    var workerIsolation: WorkerIsolation { connection.isolation }
}

extension WorkerOnlyEngine: WorkerHosted {
    var workerIsolation: WorkerIsolation { selection.workerConnection.isolation }
}

extension WorkerRoutedEngine: WorkerHosted {
    var workerIsolation: WorkerIsolation { selection.workerConnection.isolation }
}
