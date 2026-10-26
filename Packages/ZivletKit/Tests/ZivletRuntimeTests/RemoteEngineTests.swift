import CoreGraphics
import EngineImage
import EngineTestSupport
import Foundation
import ImageIO
import TestSupport
import Testing
import WorkerTestSupport
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import ZivletWorkerCore

@testable import ZivletRuntime

/// Source images drawn at test time, and claimed staging for one conversion of each.
struct ParityRig {
    let dir: TempDir

    init() throws { dir = try TempDir(prefix: "zivlet-parity") }

    func source(_ format: FormatID) throws -> URL {
        let url = dir.url.appending(path: "source.\(format.rawValue)")
        if format == .svg {
            let svg =
                #"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="20" height="20" fill="red"/></svg>"#
            try Data(svg.utf8).write(to: url)
            return url
        }
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        let type = FormatRegistry.standard.format(format).contentTypes[0] as CFString
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        try #require(CGImageDestinationFinalize(destination))
        return url
    }

    func request(_ source: URL, as format: FormatID, to target: FormatID) throws -> (JobRequest, JobWorkspace) {
        let item = try InputItem(url: source, format: format, byteCount: 1)
        let request = try JobRequest(input: item, operation: .convert(target), destination: dir.url)
        return (request, try Publisher().claimStaging(for: request))
    }
}

/// The plan, notes and staged bytes of one conversion through `engine`.
func convert(_ engine: any Engine, _ request: JobRequest, _ workspace: JobWorkspace) async throws
    -> (ExecutionPlan, StagedOutput, Data)
{
    let plan = try await engine.prepare(request, workspace: workspace)
    let output = try await engine.execute(plan, context: ExecutionContext())
    try await engine.verify(output, plan: plan)
    return (plan, output, try Data(contentsOf: output.url))
}

@Suite("RemoteEngine runs engines through the worker connection (plan 18c C5)")
struct RemoteEngineTests {
    static func remote(_ engines: [any Engine]) async throws -> (RemoteEngine, WorkerService) {
        let service = WorkerService(engines: engines, onIdle: {})
        let connection = WorkerConnection(transport: LoopbackTransport(service: service))
        let capability = try #require(try await connection.capabilities().engine(engines[0].id))
        return (RemoteEngine(capability: capability, connection: connection), service)
    }

    @Test(arguments: [(FormatID.png, FormatID.jpg), (.heic, .png), (.svg, .pdf)])
    func theWorkerGivesWhatTheInProcessEngineGives(_ source: FormatID, _ target: FormatID) async throws {
        let rig = try ParityRig()
        let input = try rig.source(source)
        let (remote, _) = try await Self.remote([ImageEngine()])
        let (r1, w1) = try rig.request(input, as: source, to: target)
        let (r2, w2) = try rig.request(input, as: source, to: target)
        let (localPlan, localOutput, localBytes) = try await convert(ImageEngine(), r1, w1)
        let (remotePlan, remoteOutput, remoteBytes) = try await convert(remote, r2, w2)
        #expect(remotePlan.stages == localPlan.stages && remotePlan.notes == localPlan.notes)
        #expect(remoteOutput.withdrawnNotes == localOutput.withdrawnNotes)
        if target == .pdf {  // Quartz stamps each PDF with its creation time and a fresh ID
            #expect(CGPDFDocument(remoteOutput.url as CFURL)?.numberOfPages == 1)
            #expect(abs(remoteBytes.count - localBytes.count) < 64)
        } else {
            #expect(remoteBytes == localBytes)
        }
    }

    @Test func handlesAndAvailabilityComeFromTheCapabilities() async throws {
        let (remote, _) = try await Self.remote([ImageEngine(writableTypes: ["public.jpeg"])])
        #expect(remote.id == .image)
        #expect(remote.handles(ConversionPair(source: .png, target: .jpg)))
        #expect(!remote.handles(ConversionPair(source: .mp3, target: .wav)))
        #expect(await remote.availability(of: ConversionPair(source: .png, target: .jpg)) == .available)
        #expect(await remote.availability(of: ConversionPair(source: .png, target: .heic)) != .available)
    }

    @Test func progressReachesTheSinkInOrderBeforeExecuteReturns() async throws {
        let rig = try ParityRig()
        let (remote, _) = try await Self.remote([ScriptedEngine(execution: .reportProgress)])
        let (request, workspace) = try rig.request(try rig.source(.png), as: .png, to: .jpg)
        let plan = try await remote.prepare(request, workspace: workspace)
        let seen = ProgressLog()
        let context = ExecutionContext(progress: ProgressSink(interval: .zero) { seen.append($0.fraction) })
        _ = try await remote.execute(plan, context: context)
        #expect(seen.values == [0.5, 1])
    }

    @Test func cancellingTheTaskCancelsTheWorkersJob() async throws {
        let rig = try ParityRig()
        let engine = ScriptedEngine(execution: .waitUntilCancelled)
        let (remote, service) = try await Self.remote([engine])
        let (request, workspace) = try rig.request(try rig.source(.png), as: .png, to: .jpg)
        let plan = try await remote.prepare(request, workspace: workspace)
        let task = Task { await outcome { () throws(JobError) in try await remote.execute(plan, context: .init()) } }
        await engine.reachedExecute.wait()
        task.cancel()
        #expect(await task.value == .failure(.cancelled))
        #expect(await service.runningJobs.isEmpty)
    }
}
