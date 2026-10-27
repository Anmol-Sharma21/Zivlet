import Testing

// The helpers of the timing target run in every `make test`; only the timed suites wait for ZIVLET_TIMING=1.
@Suite("Timing target helpers")
struct TimingGateTests {
    @Test func theNearestRankPercentileOfTwentySamples() throws {
        let samples = Durations((1...20).map { Duration.milliseconds($0) })
        #expect(try samples.percentile(95) == .milliseconds(19))
        #expect(try samples.percentile(50) == .milliseconds(10))
        #expect(try samples.percentile(100) == .milliseconds(20))
    }

    @Test func aPercentileOfNoSamplesOrOutOfRangeIsAnError() {
        #expect(throws: TimingError.noSamples) { try Durations([]).percentile(95) }
        #expect(throws: TimingError.badPercentile(0)) { try Durations([.seconds(1)]).percentile(0) }
        #expect(throws: TimingError.badPercentile(101)) { try Durations([.seconds(1)]).percentile(101) }
    }

    @Test func durationsPrintInMillisecondsWithOneDecimal() {
        #expect(TimingGate.milliseconds(.microseconds(18_249)) == "18.2 ms")
        #expect(TimingGate.milliseconds(.seconds(1)) == "1000.0 ms")
    }

    @Test func theGateIsOffUnlessTheScriptTurnsItOn() {
        #expect(TimingGate.isEnabled(["ZIVLET_TIMING": "1"]))
        #expect(!TimingGate.isEnabled([:]))
        #expect(!TimingGate.isEnabled(["ZIVLET_TIMING": "yes"]))
    }
}
