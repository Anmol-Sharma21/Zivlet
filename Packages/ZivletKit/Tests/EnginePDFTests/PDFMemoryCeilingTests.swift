import Darwin
import EngineTestSupport
import Foundation
import TestSupport
import Testing
import ZivletEngineKit

/// The memory ceiling behind the limits (D-M7-44), in a process of its own, because what it does is end one: the probe
/// runs its check as the worker does, and a step past the ceiling is stopped by SIGKILL. The files are small and the
/// ceilings smaller, so a failing run costs the Mac nothing.
@Suite("A hostile PDF stops at the memory ceiling (D-M7-44)")
struct PDFMemoryCeilingTests {
    private static let ceiling: Int64 = 50_000_000
    private static let passwords = ["", "new user", "new owner"]

    private func expectStopped(_ run: PDFProbe) {
        #expect(run.reason == .uncaughtSignal)
        #expect(run.status == SIGKILL)
    }

    /// A small file that the check inflates in memory, which no parser limit sees.
    @Test func aFlateBombIsStopped() throws {
        let dir = try TempDir()
        let bomb = try PDFFixtures.flateBomb(in: dir.url, decoded: 200_000_000)
        #expect(try Data(contentsOf: bomb).count < 1_000_000)

        let run = try PDFProbe.run(
            bomb, into: try dir.folder("out"), passwords: Self.passwords, memoryCeiling: Self.ceiling)

        expectStopped(run)
    }

    /// Numbers are what the container limit does not count (see `HostilePDFTests`), so this file passes it.
    @Test func aFileOfUncountedEntriesIsStopped() throws {
        let dir = try TempDir()
        let entries = String(repeating: "0 ", count: 3_000_000)
        let numbers = try PDFFixtures.raw(
            in: dir.url, name: "numbers.pdf", objects: PDFFixtures.objects(catalog: "/Big [\(entries)]"))

        let run = try PDFProbe.run(
            numbers, into: try dir.folder("out"), passwords: Self.passwords, memoryCeiling: Self.ceiling)

        expectStopped(run)
    }

    /// The probe's first step reads this file and frees it, and malloc keeps those pages. A ceiling on a step's growth
    /// would start above them and see almost nothing, so a batch of crafted files could climb past it. This one counts
    /// what the process holds. Seen to fail on a limit on growth, at this ceiling.
    @Test func memoryAnEarlierStepFreedStillCounts() throws {
        let dir = try TempDir()
        let entries = String(repeating: "0 ", count: 5_000_000)
        let numbers = try PDFFixtures.raw(
            in: dir.url, name: "numbers.pdf", objects: PDFFixtures.objects(catalog: "/Big [\(entries)]"))

        let run = try PDFProbe.run(
            numbers, into: try dir.folder("out"), passwords: Self.passwords, memoryCeiling: 150_000_000)

        expectStopped(run)
    }

    @Test func anOrdinaryFileUnderTheCeilingRunsToTheEnd() throws {
        let dir = try TempDir()
        let plain = try PDFFixtures.plain(in: dir.url)

        let run = try PDFProbe.run(
            plain, into: try dir.folder("out"), passwords: Self.passwords, memoryCeiling: Self.ceiling)

        #expect(run.reason == .exit)
        #expect(run.status == 0)
    }

    @Test func theFileIsReadToTheEndWithNoCeiling() throws {
        let dir = try TempDir()
        let bomb = try PDFFixtures.flateBomb(in: dir.url, name: "small.pdf", decoded: 1_000_000)

        let run = try PDFProbe.run(bomb, into: try dir.folder("out"), passwords: Self.passwords)

        #expect(run.reason == .exit)
        #expect(run.status == 0)
    }
}
