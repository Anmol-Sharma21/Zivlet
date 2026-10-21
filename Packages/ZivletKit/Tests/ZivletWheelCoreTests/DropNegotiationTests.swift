import Testing
import ZivletCore

@testable import ZivletWheelCore

@Suite("Drag-operation negotiation and feedback gate (P0-28, 03a §2.5, §2.7)")
struct DropNegotiationTests {
    static let masks: [DragOperations] = (0..<16).map { bits in
        let pairs: [(Int, DragOperations)] = [(1, .copy), (2, .link), (4, .generic), (8, .move)]
        return pairs.reduce(into: []) { result, pair in if bits & pair.0 != 0 { result.insert(pair.1) } }
    }

    @Test(arguments: masks)
    func aSliceGetsTheFirstOfCopyGenericLinkMove(offered: DragOperations) {
        let expected = [DragOperations.copy, .generic, .link, .move].first { offered.contains($0) } ?? []
        #expect(DropNegotiation.operation(offered: offered, hit: .slot(0), hasTarget: true) == expected)
    }

    @Test(arguments: masks)
    func hubOutsideAndEmptyWheelRefuse(offered: DragOperations) {
        #expect(DropNegotiation.operation(offered: offered, hit: .hub, hasTarget: true) == [])
        #expect(DropNegotiation.operation(offered: offered, hit: .outside, hasTarget: true) == [])
        #expect(DropNegotiation.operation(offered: offered, hit: .slot(0), hasTarget: false) == [])
    }

    @Test func neverOffersDeleteOrPrivate() {
        let all = DragOperations(rawValue: .max)
        #expect(DropNegotiation.operation(offered: all, hit: .slot(1), hasTarget: true) == .copy)
        #expect(DropNegotiation.operation(offered: [.delete, .private], hit: .slot(1), hasTarget: true) == [])
    }

    @Test func rawValuesMatchTheAppKitBits() {
        #expect(DragOperations.copy.rawValue == 1 && DragOperations.link.rawValue == 2)
        #expect(DragOperations.generic.rawValue == 4 && DragOperations.private.rawValue == 8)
        #expect(DragOperations.move.rawValue == 16 && DragOperations.delete.rawValue == 32)
    }

    @Test func feedbackGateSpacesTicksAndDropsStaleRequests() {
        let gate = FeedbackGate()
        let first = gate.admit(requestedAt: .milliseconds(0), now: .milliseconds(1))
        #expect(first.admitted)
        let tooSoon = first.next.admit(requestedAt: .milliseconds(20), now: .milliseconds(20))
        #expect(!tooSoon.admitted)
        let spaced = tooSoon.next.admit(requestedAt: .milliseconds(36), now: .milliseconds(36))
        #expect(spaced.admitted)
        let stale = spaced.next.admit(requestedAt: .milliseconds(100), now: .milliseconds(251))
        #expect(!stale.admitted && stale.next == spaced.next)
    }
}
