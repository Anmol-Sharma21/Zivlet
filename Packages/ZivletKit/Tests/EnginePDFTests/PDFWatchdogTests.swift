import Dispatch
import EngineTestSupport
import Foundation
import Synchronization
import TestSupport
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EnginePDF

/// The per-job watchdog of blocking qpdf calls (10 §8.3, D-M7-18). Time is injected: a recording timer stands in for
/// the real one, so nothing here waits for a budget.
@Suite("A stuck PDF call stops the worker (D-M7-18)")
struct PDFWatchdogTests {
    /// What the injected timer saw, and the fire it was handed.
    final class Recorder: Sendable {
        enum Event: Equatable, Sendable {
            case armed(Duration)
            case disarmed
        }

        let events = Mutex<[Event]>([])
        let stuck = Mutex(0)
        let fires = Mutex<[@Sendable () -> Void]>([])

        var watchdog: PDFWatchdog {
            PDFWatchdog(
                schedule: { budget, fire in
                    self.events.withLock { $0.append(.armed(budget)) }
                    self.fires.withLock { $0.append(fire) }
                    return { self.events.withLock { $0.append(.disarmed) } }
                }, onStuck: { self.stuck.withLock { $0 += 1 } })
        }
    }

    @Test func aStepThatEndsInTimeDisarmsItsTimer() throws {
        let recorder = Recorder()

        let value = try recorder.watchdog.guarding(inputBytes: 0) { () throws(PDFEngineError) -> Int in 7 }

        #expect(value == 7)
        #expect(recorder.events.withLock { $0 } == [.armed(.seconds(30)), .disarmed])
        #expect(recorder.stuck.withLock { $0 } == 0)
    }

    @Test func aStepThatThrowsDisarmsItsTimerToo() {
        let recorder = Recorder()

        #expect(throws: PDFEngineError.damaged) {
            try recorder.watchdog.guarding(inputBytes: 0) { () throws(PDFEngineError) in throw .damaged }
        }
        #expect(recorder.events.withLock { $0 } == [.armed(.seconds(30)), .disarmed])
    }

    @Test func theBudgetFollowsTheInputsSize() throws {
        let recorder = Recorder()

        try recorder.watchdog.guarding(inputBytes: 100_000_000) { () throws(PDFEngineError) in }

        #expect(recorder.events.withLock { $0 }.first == .armed(.seconds(40)))
    }

    @Test func aFiredTimerReportsAStuckCall() throws {
        let recorder = Recorder()

        try recorder.watchdog.guarding(inputBytes: 0) { () throws(PDFEngineError) in
            recorder.fires.withLock { $0 }.first?()
        }

        #expect(recorder.stuck.withLock { $0 } == 1)
    }

    /// qpdf runs one call at a time (D-M7-32); a small job waiting behind a large one must not spend its own budget
    /// on the wait, or it would stop the worker while the large one is working.
    @Test func aStepsBudgetStartsWhenItsTurnComes() {
        let recorder = Recorder()
        let watchdog = recorder.watchdog

        DispatchQueue.concurrentPerform(iterations: 12) { _ in
            _ = try? watchdog.guarding(inputBytes: 0) { () throws(PDFEngineError) in
                usleep(500)
            }
        }

        let events = recorder.events.withLock { $0 }
        #expect(events.count == 24)
        #expect(events.enumerated().allSatisfy { index, event in (event == .disarmed) == (index % 2 == 1) })
    }

    @Test func theRealTimerFires() async {
        let fired = Signal()

        // The returned closure keeps the timer alive, as `guarding` does for the length of a step.
        let disarm = PDFWatchdog.dispatchTimer(.milliseconds(1)) { fired.fire() }

        await fired.wait()
        disarm()
        #expect(fired.hasFired)
    }

    @Test func aWatchdogThatIsOffNeverFires() throws {
        let value = try PDFWatchdog.off.guarding(inputBytes: 0) { () throws(PDFEngineError) -> Int in 3 }

        #expect(value == 3)
    }

    @Test func theEngineArmsItsWatchdogForARewriteAndForItsVerify() async throws {
        let recorder = Recorder()
        let rig = try PDFEngineTests.Rig()
        let engine = PDFEngine(watchdog: recorder.watchdog)
        let source = try PDFFixtures.plain(in: rig.dir.url)
        let plan = try rig.plan(source)

        let output = try await engine.execute(plan, context: ExecutionContext())
        try await engine.verify(output, plan: plan)

        let events = recorder.events.withLock { $0 }
        #expect(events.filter { $0 == .disarmed }.count == 2)
        #expect(events.count == 4)
    }
}
