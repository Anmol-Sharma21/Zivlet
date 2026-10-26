import DragTraceSupport
import Foundation
import TestSupport
import Testing
import ZivletCore

@testable import ZivletTrigger

@Suite("Synthetic drag traces (plan 16 §3.6)")
struct SyntheticTraceTests {
    @Test func aSyntheticTraceRoundTrips() throws {
        var rng = SplitMix64(seed: 197)
        let trace = try SyntheticDrags.notchBound(on: try TraceDisplay.mbp14(), spread: .gaussian50, &rng)
        #expect(try JSONDecoder().decode(DragTrace.self, from: JSONEncoder().encode(trace)) == trace)
    }

    @Test func theGeneratorIsTheSameForASeed() throws {
        let display = try TraceDisplay.pill1080()
        let first = try SyntheticDrags.proximitySet(on: display, seed: 7, normal: 20, notchBound: 5)
        let second = try SyntheticDrags.proximitySet(on: display, seed: 7, normal: 20, notchBound: 5)
        let other = try SyntheticDrags.proximitySet(on: display, seed: 8, normal: 20, notchBound: 5)
        #expect(first == second && first != other)
        #expect(first.filter { $0.label == .normal }.count == 20 && first.filter { $0.label == .notch }.count == 5)
    }

    @Test(arguments: SyntheticDrags.Spread.allCases)
    func everySyntheticTracePassesValidation(_ spread: SyntheticDrags.Spread) throws {
        for display in [try TraceDisplay.mbp14(), try TraceDisplay.pill1080()] {
            let set = try SyntheticDrags.proximitySet(on: display, seed: 3, spread: spread)
            let decoded = try set.map { try JSONDecoder().decode(DragTrace.self, from: JSONEncoder().encode($0)) }
            #expect(decoded == set)
        }
    }
}
