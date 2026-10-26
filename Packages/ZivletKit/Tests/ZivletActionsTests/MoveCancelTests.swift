import Foundation
import TestSupport
import Testing
import ZivletRuntime

@testable import ZivletActions

/// A copy that copies for real and then holds after the `pauseAfter`th item until `resume()`, recording the
/// progress the executor reports.
nonisolated final class StepGate: @unchecked Sendable {
    private let lock = NSCondition()
    private let pauseAfter: Int
    private var copies = 0
    private var held = false
    private var released = false
    private var calls: [[Int]] = []

    init(pauseAfter: Int) { self.pauseAfter = pauseAfter }

    var progress: [[Int]] { lock.withLock { calls } }
    var isHeld: Bool { lock.withLock { held } }

    var copy: MoveExecutor.Copy {
        { [self] source, copy throws(MoveIOError) in
            try MoveExecutor.copyTree(source, copy)
            lock.withLock {
                copies += 1
                guard copies == pauseAfter else { return }
                held = true
                while !released { lock.wait() }
            }
        }
    }

    func record(_ done: Int, _ total: Int) { lock.withLock { calls.append([done, total]) } }

    func resume() {
        lock.withLock {
            released = true
            lock.broadcast()
        }
    }

    func reachedPause() async throws {
        for _ in 0..<2_000 where !isHeld { try await Task.sleep(for: .milliseconds(5)) }
        #expect(isHeld)
    }
}

@Suite("Move and Copy to stop between items when cancelled (G-M5b-9)")
struct MoveCancelTests {
    let dir: TempDir

    init() throws { dir = try TempDir(prefix: "zivlet-move-cancel") }

    func plan(items: Int, mode: MovePlan.Mode = .move) throws -> MovePlan {
        let files = try (0..<items).map { try dir.file("src/f\($0).txt", "item \($0)") }
        let plan = try MoveSurvey().plan(items: files, destination: try dir.folder("dst"), mode: mode)
        return mode == .copy ? plan : MoveExecutorTests.crossVolume(plan)
    }

    func hiddenLeft() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.url.appending(path: "dst").path)
            .filter { $0.hasPrefix(MoveExecutor.hiddenPrefix) }
    }

    @Test func aCancelledRunStopsBetweenItemsAndListsTheRest() async throws {
        let plan = try plan(items: 10)
        let gate = StepGate(pauseAfter: 3)
        let executor = MoveExecutor(copy: gate.copy, trash: { _ in })
        let task = Task { await executor.run(plan, progress: { gate.record($0, $1) }) }
        try await gate.reachedPause()
        task.cancel()
        gate.resume()
        let report = await task.value
        #expect(report.moved.count == 3 && report.cancelled.count == 7 && report.failures.isEmpty)
        #expect(report.cancelled == plan.steps.dropFirst(3).map(\.source))
        #expect(try hiddenLeft().isEmpty)
        #expect(gate.progress == [[1, 10], [2, 10], [3, 10]])
    }

    @Test func anUncancelledRunReportsEveryItemAndCancelsNothing() async throws {
        let plan = try plan(items: 4, mode: .copy)
        let gate = StepGate(pauseAfter: 0)
        let report = await MoveExecutor(copy: gate.copy, trash: { _ in }).run(plan, progress: { gate.record($0, $1) })
        #expect(report.moved.count == 4 && report.cancelled.isEmpty)
        #expect(gate.progress.last == [4, 4] && gate.progress.count == 4)
    }

    @Test func aRunCancelledBeforeItStartsMovesNothing() async throws {
        let plan = try plan(items: 2)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await MoveExecutor(trash: { _ in }).run(plan)
        }
        let report = await task.value
        #expect(report.moved.isEmpty && report.cancelled.count == 2)
    }
}
