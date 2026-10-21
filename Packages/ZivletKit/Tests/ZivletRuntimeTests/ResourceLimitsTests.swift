import Darwin
import Testing

@testable import ZivletRuntime

/// G-18: a batch of many files and helpers needs more descriptors than the default soft limit of 256.
@Suite("Open-file limit (G-18)")
struct ResourceLimitsTests {
    @Test func raisingReachesTheTargetOrTheHardLimit() throws {
        let change = try #require(ResourceLimits.raiseOpenFiles(to: 4_096))
        let now = try #require(ResourceLimits.openFiles())
        #expect(now.soft >= min(now.hard, 4_096) && change.new == now.soft && change.old <= change.new)
    }

    @Test func itNeverLowersTheLimit() throws {
        _ = ResourceLimits.raiseOpenFiles(to: 4_096)
        let before = try #require(ResourceLimits.openFiles())
        let change = try #require(ResourceLimits.raiseOpenFiles(to: 16))
        #expect(change.old == before.soft && change.new == before.soft)
        #expect(ResourceLimits.openFiles()?.soft == before.soft)
    }

    @Test(
        arguments: [
            (256, 10_240, 4_096, 4_096), (256, 1_024, 4_096, 1_024), (8_192, 10_240, 4_096, 8_192),
            (256, rlim_t.max >> 1, 4_096, 4_096),
        ] as [(rlim_t, rlim_t, rlim_t, rlim_t)])
    func theTargetIsCappedByTheHardLimitAndNeverBelowTheCurrentOne(
        soft: rlim_t, hard: rlim_t, wanted: rlim_t, expected: rlim_t
    ) {
        #expect(ResourceLimits.target(soft: soft, hard: hard, wanted: wanted) == expected)
    }
}
