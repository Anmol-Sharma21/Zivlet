import EngineVision
import Foundation
import ZivletCore
import ZivletEngineKit

/// What the app asks the worker (02 §7.4–§7.5). A job step is one request whose reply comes when the step ends;
/// progress and spawned PIDs travel as `WorkerEvent`s on the same session; cancel is a request of its own (D-M6-2).
/// Files travel as absolute paths, checked by `WorkerRequestValidator` in the worker (D-M6-4).
public enum WorkerRequest: Codable, Sendable, Equatable {
    case ping
    case capabilities
    case prepare(JobRequest, JobWorkspace)
    case execute(JobID, ExecutionPlan, outputByteLimit: Int64?)
    case verify(StagedOutput, ExecutionPlan)
    case cancel(JobID)
    /// Copy Text (P2-104): every Vision call runs here, never in the app (D-M6-8).
    case recognizeText(TextJob)
    /// The languages this Mac's Vision reads (OWN-OCR-1).
    case textCapabilities
    /// The one-time warm-up in the production configuration (D-M6-16), under its own job id so a cancel or the end
    /// of the session stops it.
    case warmUpText(JobID, [LanguageTag])
    #if DEBUG
        /// The smoke run's real crash (D-M6-18): the worker SIGKILLs itself, so no crash report is written.
        case selfKillForTesting(afterMilliseconds: Int)
        /// The smoke run's short idle exit; launchd starts the worker, so no launch argument can reach it.
        case setIdleForTesting(seconds: Int)
    #endif
}

/// The worker's answer to one request.
public enum WorkerReply: Codable, Sendable, Equatable {
    case pong(pid: Int32, osBuild: String)
    case capabilities(WorkerCapabilities)
    case planned(ExecutionPlan)
    case staged(StagedOutput)
    case verified
    case failed(JobError)
    /// Cancel, the warm-up and the DEBUG requests: received or done, nothing to return.
    case accepted
    case text(RecognizedText)
    case textFailed(TextError)
    case textCapabilities(VisionCapabilities)
}

/// What the worker reports while a step runs.
public enum WorkerEvent: Codable, Sendable, Equatable {
    case progress(JobID, JobProgress)
    case spawned(JobID, Int32)

    public var job: JobID {
        switch self {
        case .progress(let job, _), .spawned(let job, _): job
        }
    }
}

/// One route an engine handles and whether it can run on this Mac.
public struct RouteCapability: Codable, Sendable, Equatable {
    public let pair: ConversionPair
    public let availability: RouteAvailability

    public init(pair: ConversionPair, availability: RouteAvailability) {
        self.pair = pair
        self.availability = availability
    }
}

/// One hosted engine and every catalog route it handles, so the app answers `handles` and `availability` locally.
public struct EngineCapability: Codable, Sendable, Equatable {
    public let id: EngineID
    public let routes: [RouteCapability]

    public init(id: EngineID, routes: [RouteCapability]) {
        self.id = id
        self.routes = routes
    }

    public func handles(_ pair: ConversionPair) -> Bool { routes.contains { $0.pair == pair } }

    /// A route the engine does not handle is unavailable with nothing named.
    public func availability(of pair: ConversionPair) -> RouteAvailability {
        routes.first { $0.pair == pair }?.availability ?? .unavailable([])
    }
}

/// The engines a worker hosts.
public struct WorkerCapabilities: Codable, Sendable, Equatable {
    public let engines: [EngineCapability]

    public init(engines: [EngineCapability]) {
        self.engines = engines
    }

    public func engine(_ id: EngineID) -> EngineCapability? { engines.first { $0.id == id } }
}
