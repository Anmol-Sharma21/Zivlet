import EngineTestSupport
import Foundation
import Synchronization
import TestSupport
import ZivletCore
import ZivletEngineKit
import ZivletIPC

@testable import ZivletWorkerCore

/// A sleeper the test drives: each `sleep(for:)` waits until `releaseAll()`; the requested durations are recorded.
final class ManualSleeper: Sendable {
    private let state = Mutex<(requested: [Duration], waiting: [CheckedContinuation<Void, Never>])>(([], []))

    var requested: [Duration] { state.withLock(\.requested) }

    var sleep: IdleTimer.Sleeper {
        { duration in
            await withCheckedContinuation { continuation in
                self.state.withLock { state in
                    state.requested.append(duration)
                    state.waiting.append(continuation)
                }
            }
        }
    }

    func releaseAll() {
        let waiting = state.withLock { state in
            defer { state.waiting = [] }
            return state.waiting
        }
        waiting.forEach { $0.resume() }
    }

    /// Waits (briefly, polling) until `count` sleeps have been requested.
    func waitForRequests(_ count: Int) async {
        for _ in 0..<500 where requested.count < count { try? await Task.sleep(for: .milliseconds(2)) }
    }
}

/// Counts idle firings.
final class IdleCounter: Sendable {
    private let count = Mutex(0)
    var fired: Int { count.withLock { $0 } }
    func fire() { count.withLock { $0 += 1 } }
}

/// Collects worker events in arrival order.
final class EventLog: Sendable {
    private let events = Mutex<[WorkerEvent]>([])
    var all: [WorkerEvent] { events.withLock { $0 } }
    var sink: @Sendable (WorkerEvent) -> Void { { event in self.events.withLock { $0.append(event) } } }
}

/// A temporary input and a claimed staging folder, as the app would send them.
struct WorkerRig {
    let dir: TempDir
    let input: URL

    init() throws {
        dir = try TempDir(prefix: "zivlet-worker")
        input = try dir.file("photo.png")
    }

    /// A fresh job with its staging folder and an empty staged file.
    func job() throws -> (JobRequest, JobWorkspace) {
        let id = JobID()
        let staged = try dir.folder(".zivlet-\(id)").appending(path: "staged.jpg")
        try Data().write(to: staged)
        let item = try InputItem(url: input, format: .png, byteCount: 4)
        let request = try JobRequest(id: id, input: item, operation: .convert(.jpg), destination: dir.url)
        return (request, JobWorkspace(job: id, stagedFile: staged))
    }

    func executeRequest(engine: EngineID = .image) throws -> (JobID, WorkerRequest) {
        let (request, workspace) = try job()
        let plan = try ScriptedEngine.plan(engine: engine, staged: workspace.stagedFile)
        return (request.id, .execute(request.id, plan, outputByteLimit: nil))
    }

    /// Whether the engine started a step before `reply` came back, polling for at most a second.
    static func started(_ engine: ScriptedEngine, unless reply: Task<WorkerReply, Never>) async -> Bool {
        let done = Signal()
        Task {
            _ = await reply.value
            done.fire()
        }
        for _ in 0..<500 where engine.executeCount == 0 && !done.hasFired {
            try? await Task.sleep(for: .milliseconds(2))
        }
        return engine.executeCount > 0
    }

    static func service(
        _ engines: [any Engine], sleeper: ManualSleeper = ManualSleeper(), idle: IdleCounter = IdleCounter()
    ) -> WorkerService {
        WorkerService(engines: engines, idleAfter: .seconds(60), sleep: sleeper.sleep, onIdle: { idle.fire() })
    }
}
