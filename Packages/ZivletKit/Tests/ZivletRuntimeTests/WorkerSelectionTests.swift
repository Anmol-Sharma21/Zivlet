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

/// A timeout that the test fires once; every later wait never ends, so a second decision is never timed out.
final class OnceTimeout: Sendable {
    let fired = Signal()
    let waits = Counter()

    var sleep: WorkerSelection.Sleeper {
        { _ in
            if self.waits.increment() == 1 { return await self.fired.wait() }
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
        }
    }
}

/// The first session never answers (a slow cold start); later ones are the loopback worker.
final class FirstSilentTransport: WorkerTransport {
    let then: LoopbackTransport
    let opened = Counter()

    init(then: LoopbackTransport) { self.then = then }

    func open(onEvent: @escaping @Sendable (WorkerEvent) -> Void, onClosed: @escaping @Sendable () -> Void)
        throws(JobError) -> any WorkerChannel
    {
        if opened.increment() == 1 { return SilentTransport.Channel() }
        return try then.open(onEvent: onEvent, onClosed: onClosed)
    }
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
        sleep: @escaping WorkerSelection.Sleeper = ManualTimeout().sleep,
        retryAfter: Duration = WorkerSelection.retryUnreachable
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
            sleep: sleep, retryUnreachableAfter: retryAfter)
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
        let selection = try rig.selection(transport: SilentTransport(), sleep: timeout.sleep)
        timeout.fired.fire()
        #expect(try await rig.run(selection) == "in-process")
        #expect(await selection.status == .inProcess(reason: "worker unreachable"))
    }

    /// A slow cold start under load is not final for the launch: the first job after the back-off tries again, on a
    /// new session. A damaged worker stays in-process.
    @Test func anUnreachableWorkerIsTriedAgainAfterTheBackOff() async throws {
        let rig = try SelectionRig()
        let timeout = OnceTimeout()
        let transport = FirstSilentTransport(
            then: LoopbackTransport(service: WorkerService(engines: [rig.worker], onIdle: {})))
        let selection = try rig.selection(transport: transport, sleep: timeout.sleep, retryAfter: .zero)
        timeout.fired.fire()
        guard case .inProcess(let reason) = await selection.choice() else {
            Issue.record("the silent worker was chosen")
            return
        }
        #expect(reason == "worker unreachable")
        guard case .worker = await selection.choice() else {
            Issue.record("the unreachable decision was kept")
            return
        }
        #expect(transport.opened.value == 2)
        let damaged = try rig.selection(damaged: true, retryAfter: .zero)
        _ = await damaged.choice()
        _ = await damaged.choice()
        #expect(rig.verifies.value == 3)  // two for the first selection, one for the damaged one
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
