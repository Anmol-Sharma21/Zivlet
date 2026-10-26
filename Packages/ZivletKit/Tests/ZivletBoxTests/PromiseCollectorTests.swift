import Foundation
import Testing

@testable import ZivletBox

/// Scheduled checks the test runs by hand: the deadline and each quiet-moment check.
nonisolated final class ManualSchedule: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [(delay: Double, work: @Sendable () -> Void)] = []

    var delays: [Double] { lock.withLock { pending.map(\.delay) } }

    func schedule(_ delay: Double, _ work: @escaping @Sendable () -> Void) {
        lock.withLock { pending.append((delay, work)) }
    }

    /// Runs only the oldest check scheduled for `delay`.
    func runFirst(_ delay: Double) {
        let due: (@Sendable () -> Void)? = lock.withLock {
            guard let index = pending.firstIndex(where: { $0.delay == delay }) else { return nil }
            return pending.remove(at: index).work
        }
        due?()
    }

    /// Runs the checks scheduled for `delay`, oldest first.
    func run(_ delay: Double) {
        let due = lock.withLock { pending.filter { $0.delay == delay } }
        lock.withLock { pending.removeAll { $0.delay == delay } }
        due.forEach { $0.work() }
    }
}

/// What the collector finished with, and how often it finished.
nonisolated final class Finishes: @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [PromiseOutcome] = []

    var all: [PromiseOutcome] { lock.withLock { outcomes } }
    func record(_ outcome: PromiseOutcome) { lock.withLock { outcomes.append(outcome) } }
}

@Suite("Receiving file promises ends, once (D-M5b-5)")
struct PromiseCollectorTests {
    let a = URL(filePath: "/box/a.eml")
    let b = URL(filePath: "/box/b.eml")
    let c = URL(filePath: "/box/c.eml")

    func collector(expected: Int, named: Bool) -> (PromiseCollector, ManualSchedule, Finishes) {
        let schedule = ManualSchedule()
        let finishes = Finishes()
        let collector = PromiseCollector(
            expected: expected, named: named, schedule: schedule.schedule, finish: finishes.record)
        collector.start()
        return (collector, schedule, finishes)
    }

    @Test func namedPromisesFinishWhenEveryFileCalledBackAndLateOnesAreIgnored() {
        let (collector, schedule, finishes) = collector(expected: 2, named: true)
        collector.add(a)
        #expect(finishes.all.isEmpty)
        collector.add(nil)
        collector.add(b)
        schedule.run(PromiseCollector.deadline(expected: 2))
        #expect(finishes.all == [PromiseOutcome(received: [a], failed: 1)])
    }

    @Test func aSenderThatNeverCallsBackEndsAtTheDeadlineWithTheRestFailed() {
        let (collector, schedule, finishes) = collector(expected: 3, named: true)
        collector.add(a)
        #expect(schedule.delays == [PromiseCollector.deadline(expected: 3)])
        schedule.run(PromiseCollector.deadline(expected: 3))
        #expect(finishes.all == [PromiseOutcome(received: [a], failed: 2)])
        collector.add(b)
        #expect(finishes.all.count == 1)
    }

    @Test func unnamedPromisesKeepExtraFilesUntilAQuietMoment() {
        let (collector, schedule, finishes) = collector(expected: 1, named: false)
        collector.add(a)
        collector.add(b)
        schedule.runFirst(PromiseCollector.quiet)
        #expect(finishes.all.isEmpty)
        collector.add(c)
        schedule.run(PromiseCollector.quiet)
        #expect(finishes.all == [PromiseOutcome(received: [a, b, c], failed: 0)])
    }

    @Test func theDeadlineIsBounded() {
        #expect(PromiseCollector.deadline(expected: 1) == 20)
        #expect(PromiseCollector.deadline(expected: 1_000) == 120)
    }
}
