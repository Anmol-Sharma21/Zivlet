import Foundation
import ZivletCore

/// Where a job may write (02 §7.3, R4): one hidden staged file in the destination folder, claimed exclusively by the
/// runtime before planning. Engines never write anywhere else.
public struct JobWorkspace: Sendable, Equatable, Codable {
    public let job: JobID
    public let stagedFile: URL

    public init(job: JobID, stagedFile: URL) {
        self.job = job
        self.stagedFile = stagedFile
    }
}

/// The finished staged file, before verification and publication.
public struct StagedOutput: Sendable, Equatable, Codable {
    public let format: FormatID
    public let url: URL
    public let byteCount: Int64
    /// Plan notes the run took back: what it found differs from what the plan expected (an alpha channel with no
    /// transparent pixel had nothing to flatten).
    public let withdrawnNotes: [PlanNote]

    public init(format: FormatID, url: URL, byteCount: Int64, withdrawnNotes: [PlanNote] = []) {
        self.format = format
        self.url = url
        self.byteCount = byteCount
        self.withdrawnNotes = withdrawnNotes
    }

    private enum CodingKeys: String, CodingKey { case format, url, byteCount, withdrawnNotes }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            format: try c.decode(FormatID.self, forKey: .format), url: try c.decode(URL.self, forKey: .url),
            byteCount: try c.decode(Int64.self, forKey: .byteCount),
            withdrawnNotes: try c.decodeIfPresent([PlanNote].self, forKey: .withdrawnNotes) ?? [])
    }
}

/// What `execute` may report back besides its result: progress, and each child process it spawns (the runtime
/// records the PID so the orphan reaper can stop it after a crash, 03a §4.8).
public struct ExecutionContext: Sendable {
    public let progress: ProgressSink
    public let spawned: @Sendable (Int32) -> Void
    /// Bytes the output may reach before the volume is too full (free space minus the reserve); nil when unknown.
    /// Helpers that can stop themselves at a size (ffmpeg `-fs`) are given it, so hostile input cannot fill the disk.
    public let outputByteLimit: Int64?

    public init(
        progress: ProgressSink = .discard, spawned: @escaping @Sendable (Int32) -> Void = { _ in },
        outputByteLimit: Int64? = nil
    ) {
        self.progress = progress
        self.spawned = spawned
        self.outputByteLimit = outputByteLimit
    }
}

/// Whether a catalog route can run on this machine (03a §3.5). `unavailable` names what is missing, for example
/// `["libvorbis"]`, so Settings and the result card can say why.
public enum RouteAvailability: Sendable, Equatable, Codable {
    case available
    case unavailable([String])

    public var isAvailable: Bool { self == .available }
}

/// One conversion engine (02 §7.3, adapted for M3): probe and plan in `prepare` (the plan step itself is pure and
/// golden-tested inside each engine), run in `execute`, check the staged file in `verify`.
/// Every failure is a `JobError`.
public protocol Engine: Sendable {
    var id: EngineID { get }

    /// The engine's family of pairs (for example audio/video/GIF for media), whether or not it can run them here.
    func handles(_ pair: ConversionPair) -> Bool

    /// Capability gate for a handled pair (03a §3.5). May probe the engine once; results are cached.
    func availability(of pair: ConversionPair) async -> RouteAvailability

    /// Probes the input and returns a plan that writes `workspace.stagedFile`.
    func prepare(_ request: JobRequest, workspace: JobWorkspace) async throws(JobError) -> ExecutionPlan

    func execute(_ plan: ExecutionPlan, context: ExecutionContext) async throws(JobError) -> StagedOutput

    /// Re-opens the staged file and checks it against the plan (03a §4.3 "Verify").
    func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError)
}
