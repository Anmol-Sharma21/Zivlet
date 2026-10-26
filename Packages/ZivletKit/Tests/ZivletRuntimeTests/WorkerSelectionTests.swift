import EngineTestSupport
import Foundation
import Synchronization
import TestSupport
import Testing
import WorkerTestSupport
import ZivletCore
import ZivletEngineKit
import ZivletIPC
import ZivletWorkerCore

@testable import ZivletRuntime

/// A worker that never answers: every send waits forever.
struct SilentTransport: WorkerTransport {
    struct Channel: WorkerChannel {
        func send(_ request: WorkerRequest) async throws(JobError) -> WorkerReply {
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
            throw .internalInvariant("unreachable")
        }
        func close() {}
    }

    func open(onEvent: @escaping @Sendable (WorkerEvent) -> Void, onClosed: @escaping @Sendable () -> Void)
        throws(JobError) -> any WorkerChannel
    { Channel() }
}

/// A timeout the test fires by hand.
final class ManualTimeout: Sendable {
    let fired = Signal()
    var sleep: WorkerSelection.Sleeper { { _ in await self.fired.wait() } }
}

/// A selection over a temporary "bundle" folder and a loopback worker hosting a scripted engine.
struct SelectionRig {
    let dir: TempDir
    let worker: ScriptedEngine
    let local: ScriptedEngine
    let verifies = Counter()

    init() throws {
        dir = try TempDir(prefix: "zivlet-selection")
        worker = ScriptedEngine()
        local = ScriptedEngine()
    }

    func selection(
        bundle: Bool = true, damaged: Bool = false, transport: (any WorkerTransport)? = nil,
        timeout: ManualTimeout = ManualTimeout()
    ) throws -> WorkerSelection {
        let url = bundle ? try dir.folder("ZivletWorker.xpc") : dir.url.appending(path: "ZivletWorker.xpc")
        let verifies = self.verifies
        let service = WorkerService(engines: [worker], onIdle: {})
        return WorkerSelection(
            workerBundle: url,
            verify: { _ throws(JobError) in
                verifies.increment()
                if damaged { throw .engineDamaged(.worker) }
            },
            connection: WorkerConnection(transport: transport ?? LoopbackTransport(service: service)),
            sleep: timeout.sleep)
    }

    /// One job through a routed engine; returns which engine ran it.
    func run(_ selection: WorkerSelection) async throws -> String {
        let box = try Sandbox()
        try box.file("a.png")
        let request = try box.request("a.png", .png, to: .jpg)
        let workspace = try Publisher().claimStaging(for: request)
        let engine = WorkerRoutedEngine(local: local, selection: selection)
        let plan = try await engine.prepare(request, workspace: workspace)
        let output = try await engine.execute(plan, context: ExecutionContext())
        try await engine.verify(output, plan: plan)
        return worker.executeCount == 1 ? "worker" : local.executeCount == 1 ? "in-process" : "none"
    }
}

@Suite("The worker when it is there and sound, else in-process (D-M6-9, plan 18c C7)")
struct WorkerSelectionTests {
    @Test func aMissingWorkerRunsInProcess() async throws {
        let rig = try SelectionRig()
        let selection = try rig.selection(bundle: false)
        #expect(try await rig.run(selection) == "in-process")
        #expect(await selection.status == .inProcess(reason: "worker missing"))
        #expect(rig.verifies.value == 0)
    }

    @Test func aDamagedWorkerRunsInProcess() async throws {
        let rig = try SelectionRig()
        let selection = try rig.selection(damaged: true)
        #expect(try await rig.run(selection) == "in-process")
        #expect(await selection.status == .inProcess(reason: "worker damaged"))
        #expect(JobErrorCopy.copy(for: .workerCrashed).message == "The converter stopped unexpectedly.")
    }

    @Test func aWorkerThatDoesNotAnswerInTimeRunsInProcess() async throws {
        let rig = try SelectionRig()
        let timeout = ManualTimeout()
        let selection = try rig.selection(transport: SilentTransport(), timeout: timeout)
        timeout.fired.fire()
        #expect(try await rig.run(selection) == "in-process")
        #expect(await selection.status == .inProcess(reason: "worker unreachable"))
    }

    @Test func aSoundWorkerRunsTheJob() async throws {
        let rig = try SelectionRig()
        let selection = try rig.selection()
        #expect(try await rig.run(selection) == "worker")
        #expect(await selection.status == .running(pid: getpid()))
    }

    @Test func theChoiceIsMadeOnceAndOnlyAtTheFirstJob() async throws {
        let rig = try SelectionRig()
        let selection = try rig.selection()
        let routed = WorkerRoutedEngine(local: rig.local, selection: selection)
        #expect(routed.handles(ConversionPair(source: .png, target: .jpg)))
        #expect(await routed.availability(of: ConversionPair(source: .png, target: .webp)) == .unavailable(["libwebp"]))
        #expect(await selection.status == .notStarted && rig.verifies.value == 0)
        _ = try await rig.run(selection)
        _ = await selection.choice()
        #expect(rig.verifies.value == 1)
        #expect(routed.id == .image)
    }

    @Test func statusLinesNameNoPath() {
        #expect(WorkerStatus.notStarted.line == "Worker: not started yet")
        #expect(WorkerStatus.running(pid: 42).line == "Worker: running (pid 42)")
        #expect(WorkerStatus.inProcess(reason: "worker missing").line == "Worker: in-process (worker missing)")
    }
}

@Suite("The app's worker wiring (plan 18c C11)")
struct WorkerWiringTests {
    @Test func theServiceReportsWhereConversionsRunAndClosesTheWorkerAtQuit() async throws {
        let rig = try SelectionRig()
        let selection = try rig.selection(bundle: false)
        let scheduler = JobScheduler(engines: [], records: nil)
        let service = ConversionService(scheduler: scheduler, worker: selection)
        #expect(await service.workerStatus() == .notStarted)
        _ = await selection.choice()
        #expect(await service.workerStatus() == .inProcess(reason: "worker missing"))
        #expect(await service.shutdown(within: .milliseconds(100)))
    }

    @Test func theStandardSelectionLooksInsideTheAppBundle() {
        let bundle = URL(fileURLWithPath: "/Applications/Zivlet.app")
        #expect(
            WorkerSelection.workerBundle(in: bundle).path
                == "/Applications/Zivlet.app/Contents/XPCServices/ZivletWorker.xpc")
    }

    @Test func aServiceWithoutAWorkerSaysSo() async {
        let service = ConversionService(scheduler: JobScheduler(engines: [], records: nil))
        #expect(await service.workerStatus() == .inProcess(reason: "no worker in this build"))
    }
}
