import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

/// Every pair of the Phase 1 set plus SVG through the real pipeline with the E1 fixtures (P1-61). Opt-in:
/// `ZIVLET_MATRIX=subset` (PRs) or `full` (nightly); `make matrix` sets it and uses the vendored ffmpeg.
@Suite("Pair matrix (opt-in: ZIVLET_MATRIX)", .enabled(if: MatrixEnvironment.isEnabled), .timeLimit(.minutes(5)))
struct MatrixTests {
    @Test(arguments: MatrixEnvironment.pairs)
    func convertsAndHasTheRightProperties(pair: ConversionPair) async throws {
        let rig = try await MatrixRig.shared()
        let availability = await rig.availability(pair)
        // No silent gate passes: with the vendored build every Phase 1 pair must be available.
        if rig.isVendored {
            #expect(availability == .available, "\(pair.testDescription) gated off with the vendored build")
        } else if availability != .available {
            withKnownIssue("this ffmpeg is not the vendored build: \(availability)") { Issue.record("gated off") }
            return
        }
        guard availability == .available else { return }
        let output = try await rig.convert(pair, fixture: try await rig.fixture(pair.source))
        defer { output.discard() }
        #expect(output.url.pathExtension == FormatRegistry.standard.format(pair.target).canonicalExtension)
        try await PropertyChecks.verify(
            output, pair: pair, source: try await rig.fixtureFacts(pair.source), tools: rig.tools)
    }
}
