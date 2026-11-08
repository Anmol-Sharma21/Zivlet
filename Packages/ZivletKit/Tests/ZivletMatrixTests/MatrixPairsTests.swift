import Testing
import ZivletCore

@Suite("Phase 1 pair set (P1-61)")
struct MatrixPairsTests {
    @Test func countsMatchThePhaseOneScopePlusSVGAndDNG() {
        let pairs = MatrixPairs.all
        #expect(pairs.count == 169)
        #expect(MatrixPairs.count(.raster) == 57 && MatrixPairs.count(.svg) == 8)
        #expect(MatrixPairs.count(.audio) == 56 && MatrixPairs.count(.video) == 42 && MatrixPairs.count(.gif) == 6)
        #expect(Set(pairs).count == pairs.count)
    }

    @Test func thePhaseOneSetIsTheFullSetWithoutSVGAndDNG() {
        #expect(MatrixPairs.phaseOne.count == 153)
        #expect(MatrixPairs.phaseOne.allSatisfy { $0.source != .svg && $0.source != .dng })
    }

    @Test func theSubsetCoversEverySourceAndEveryTarget() {
        let subset = MatrixPairs.subset
        #expect(Set(subset.map(\.source)) == Set(MatrixPairs.all.map(\.source)))
        #expect(Set(subset.map(\.target)) == Set(MatrixPairs.all.map(\.target)))
        #expect(subset.count <= 46 && Set(subset).isSubset(of: Set(MatrixPairs.all)))
    }

    @Test func everySourceHasAFixture() {
        for source in Set(MatrixPairs.all.map(\.source)) {
            #expect(MatrixFixtures.primary[source] != nil, "no fixture for \(source)")
        }
    }

    @Test func theEnvironmentSelectsNothingSubsetOrFull() {
        #expect(MatrixEnvironment.pairs(for: nil).isEmpty)
        #expect(MatrixEnvironment.pairs(for: "subset") == MatrixPairs.subset)
        #expect(MatrixEnvironment.pairs(for: "full") == MatrixPairs.all)
        #expect(MatrixEnvironment.pairs(for: "everything").isEmpty)
    }
}
