import Foundation
import Synchronization
import ZivletCore
import ZivletEngineKit
import os

/// The located tools and what they can do, resolved once per engine.
struct ResolvedTools: Sendable {
    let tools: MediaTools
    let capabilities: FFmpegCapabilities
}

/// Locates ffmpeg, checks a bundled helper's signature (A11) and probes it on first use. Concurrent first jobs share one
/// lookup, check and probe; a missing or damaged engine is not cached, so reinstalling takes effect.
struct MediaToolbox: Sendable {
    private let locator: EngineLocator
    private let runner: any ProcessRunning
    private let integrity: any HelperIntegrityChecking
    private let cacheDirectory: URL?
    private let shared = SharedLoad<ResolvedTools>()

    init(
        locator: EngineLocator, runner: any ProcessRunning, integrity: any HelperIntegrityChecking, cacheDirectory: URL?
    ) {
        self.locator = locator
        self.runner = runner
        self.integrity = integrity
        self.cacheDirectory = cacheDirectory
    }

    func resolve() async throws(JobError) -> ResolvedTools {
        let (locator, runner, integrity, cacheDirectory) = (locator, runner, integrity, cacheDirectory)
        return try await shared.value { () async throws(JobError) in
            let tools = try locator.locateMediaTools()
            try integrity.check(tools)
            let probe = CapabilityProbe(tools: tools, runner: runner, cacheDirectory: cacheDirectory)
            return ResolvedTools(tools: tools, capabilities: try await probe.capabilities())
        }
    }
}

/// Audio, video and GIF conversions through ffmpeg (P1-23): ffprobe → `MediaInfo` → pure planner → ffmpeg with
/// `-progress pipe:1` → ffprobe verification of the staged file.
public struct MediaEngine: Engine {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "media")
    public let id = EngineID.media

    let toolbox: MediaToolbox
    let runner: any ProcessRunning
    let registry: FormatRegistry
    let stall: StallPolicy

    public init(
        locator: EngineLocator = EngineLocator(), runner: any ProcessRunning = SubprocessRunner(),
        integrity: any HelperIntegrityChecking = SignedHelperCheck(), capabilityCache: URL? = nil,
        registry: FormatRegistry = .standard, stall: StallPolicy = .standard
    ) {
        self.toolbox = MediaToolbox(
            locator: locator, runner: runner, integrity: integrity, cacheDirectory: capabilityCache)
        self.runner = runner
        self.registry = registry
        self.stall = stall
    }

    /// Audio, video and GIF on both sides; the catalog decides which of those pairs exist.
    public func handles(_ pair: ConversionPair) -> Bool {
        let media: Set<FormatCategory> = [.audio, .video, .gif]
        return media.contains(registry.format(pair.source).category)
            && media.contains(registry.format(pair.target).category)
    }

    public func availability(of pair: ConversionPair) async -> RouteAvailability {
        do {
            let resolved = try await toolbox.resolve()
            return MediaRouteGate.availability(pair, capabilities: resolved.capabilities, registry: registry)
        } catch {
            return Self.availability(after: error)
        }
    }

    /// A helper that could not start right now (too many open files) says nothing about the route, so the job goes
    /// ahead and reports the real cause; any other failure hides the route and is logged.
    static func availability(after error: JobError) -> RouteAvailability {
        switch error {
        case .helperFailed, .cancelled:
            return .available
        case .engineDamaged:
            logger.error("Media engine damaged: its helper failed the signature check")
            return .unavailable(["signature"])
        default:
            logger.error(
                "Media engine unavailable: \(error.logDescription, privacy: .public) \(String(describing: error), privacy: .private)"
            )
            return .unavailable(["ffmpeg"])
        }
    }

    public func prepare(_ request: JobRequest, workspace: JobWorkspace) async throws(JobError) -> ExecutionPlan {
        let resolved = try await toolbox.resolve()
        let gate = MediaRouteGate.availability(request.pair, capabilities: resolved.capabilities, registry: registry)
        if case .unavailable(let missing) = gate {
            throw .routeUnavailable(request.input.format, request.target, missing)
        }
        let info = try await probe(request.input.url, format: request.input.format, tools: resolved.tools)
        let planned = try Self.plan(request, info: info, staged: workspace.stagedFile, resolved: resolved)
        return try Self.executionPlan(planned, request: request, staged: workspace.stagedFile)
    }

    public func execute(_ plan: ExecutionPlan, context: ExecutionContext) async throws(JobError) -> StagedOutput {
        let tools = try await toolbox.resolve().tools
        for (index, stage) in plan.stages.enumerated() {
            guard let ffmpeg = stage.ffmpeg else { throw .internalInvariant("media engine got a non-ffmpeg stage") }
            try StagedFile.check(plan.stagedFile)  // ffmpeg -y follows a symlink at its output path
            try await run(ffmpeg, index: index, plan: plan, tools: tools, context: context)
        }
        let size = MediaFiles.size(of: plan.stagedFile)
        if let limit = context.outputByteLimit, size >= limit - FFmpegArgs.sizeCapSlack { throw .diskFull }
        return StagedOutput(format: plan.outputFormat, url: plan.stagedFile, byteCount: size)
    }

    public func verify(_ output: StagedOutput, plan: ExecutionPlan) async throws(JobError) {
        guard output.byteCount > 0 else { throw .verificationFailed("The output file is empty.") }
        let tools = try await toolbox.resolve().tools
        let info: MediaInfo
        do {
            info = try await probe(output.url, format: output.format, tools: tools)
        } catch .cancelled {
            throw .cancelled
        } catch {
            throw .verificationFailed("The output could not be read back.")
        }
        let expected = plan.stages.compactMap { $0.ffmpeg?.expectedDurationMicros }.last
        try MediaVerifier.check(info, target: output.format, expectedMicros: expected, registry: registry)
    }
}

extension MediaEngine {
    /// ffprobe with the input whitelist; the container must match the extension.
    func probe(_ url: URL, format: FormatID, tools: MediaTools) async throws(JobError) -> MediaInfo {
        let request = SubprocessRequest(
            executable: tools.ffprobe, arguments: MediaProbe.arguments(for: url.path),
            stdoutLimit: MediaProbe.maxOutputBytes + 1)
        let result = try await MediaFailure.launch(runner, request) { _ in }
        guard result.termination == .exited(0) else { throw .unsupportedInput(.unreadable) }
        let info: MediaInfo
        do {
            info = try MediaProbe.parse(result.stdout)
        } catch .tooLarge {
            throw .unsupportedInput(.tooLarge)
        } catch {
            throw .unsupportedInput(.unreadable)
        }
        guard MediaProbe.confirms(info, source: format) else { throw .unsupportedInput(.contentMismatch) }
        return info
    }

    static func plan(_ request: JobRequest, info: MediaInfo, staged: URL, resolved: ResolvedTools) throws(JobError)
        -> FFmpegPlan
    {
        let planRequest = MediaPlanRequest(
            source: request.input.url.path, sourceFormat: request.input.format, info: info, target: request.target,
            staged: staged.path, capabilities: MediaCapabilities(resolved.capabilities))
        let plan: FFmpegPlan
        do {
            plan = try MediaPlanner.plan(planRequest)
        } catch {
            throw MediaFailure.map(error)
        }
        let argv = plan.passes.flatMap(\.argv)
        let missing = resolved.capabilities.missing(
            encoders: FFmpegRequirements.encoders(in: argv), filters: FFmpegRequirements.filters(in: argv))
        guard missing.isEmpty else { throw .routeUnavailable(request.input.format, request.target, missing) }
        return plan
    }

    static func executionPlan(_ plan: FFmpegPlan, request: JobRequest, staged: URL) throws(JobError) -> ExecutionPlan {
        let total = plan.passes.map(\.weight).reduce(0, +)
        let flattened = request.input.format == .gif && ![.webm, .mov].contains(request.target)
        do {
            return try ExecutionPlan(
                engine: .media,
                stages: plan.passes.map {
                    .ffmpeg(FFmpegStage(argv: $0.argv, expectedDurationMicros: plan.expectedDurationMicros))
                },
                stageWeights: plan.passes.map { $0.weight / total }, lanes: plan.passes.map { _ in plan.lane },
                outputFormat: request.target, stagedFile: staged, notes: flattened ? [.alphaFlattened] : [])
        } catch {
            throw .internalInvariant("media plan rejected: \(error)")
        }
    }

    /// Filters that hold all output until the input has been read (03b §5.6: `palettegen` for GIF).
    static let wholeInputFilters: Set<String> = ["palettegen"]

    /// Such a pass may decode the whole input before its first `out_time`, so it gets the input's duration (decoding
    /// at least at real time) on top of the normal limit; every other pass starts on the normal limit.
    static func startupLimit(_ stage: FFmpegStage, policy: StallPolicy) -> Duration {
        let filters = FFmpegRequirements.filters(in: stage.argv)
        guard let micros = stage.expectedDurationMicros, micros > 0,
            filters.contains(where: wholeInputFilters.contains)
        else { return policy.limit }
        return policy.limit + .microseconds(micros)
    }

    private func run(
        _ stage: FFmpegStage, index: Int, plan: ExecutionPlan, tools: MediaTools, context: ExecutionContext
    ) async throws(JobError) {
        let parser = Mutex(FFmpegProgressParser())
        let monitor = StallMonitor(policy: stall, startupLimit: Self.startupLimit(stage, policy: stall))
        let (runner, request) = (
            runner,
            SubprocessRequest(
                executable: tools.ffmpeg, arguments: FFmpegArgs.capped(stage.argv, at: context.outputByteLimit),
                stdoutLimit: 0)
        )
        let result = try await monitor.guarding { () async throws(JobError) in
            try await MediaFailure.launch(runner, request, spawned: context.spawned) { line in
                let event = parser.withLock { parser -> FFmpegProgressEvent? in
                    let step = parser.consuming(line)
                    parser = step.next
                    return step.event
                }
                guard let event else { return }
                monitor.observe(event)
                guard let fraction = FFmpegProgressParser.fraction(event, expectedMicros: stage.expectedDurationMicros)
                else { return }
                context.progress.report(plan.overallFraction(stage: index, fraction: fraction))
            }
        }
        try MediaFailure.check(result)
    }
}
