import Testing
import ZivletCore
import ZivletRuntime

@testable import ZivletUI

#if DEBUG
    @Suite("Island preview for the demo and the idle-CPU row (DEBUG)")
    struct IslandPreviewTests {
        @Test func theFlagNamesAState() throws {
            #expect(try IslandPreview.parse(arguments: ["Z", "-ZivletIslandPreview", "progress"]) == .progress)
            #expect(try IslandPreview.parse(arguments: ["Z"]) == nil)
            #expect(throws: IslandPreview.Invalid.missingValue) {
                try IslandPreview.parse(arguments: ["Z", "-ZivletIslandPreview"])
            }
            #expect(throws: IslandPreview.Invalid.unknown("sideways")) {
                try IslandPreview.parse(arguments: ["Z", "-ZivletIslandPreview", "sideways"])
            }
        }

        @Test func eachStateStartsWithTheSnapshotItShows() throws {
            let working = try IslandPreview.collapsed.first()
            #expect(!working.isFinished && !working.isIndeterminate && working.fraction == 0.4)
            #expect(try IslandPreview.indeterminate.first().isIndeterminate)
            let saved = try IslandPreview.result.first()
            #expect(saved.isFinished && saved.failures.isEmpty && saved.outputs.count == 1)
            let failed = try IslandPreview.failure.first()
            #expect(failed.isFinished && failed.failures.count == 1)
            #expect(IslandPreview.expanded.opens && IslandPreview.result.opens && !IslandPreview.collapsed.opens)
        }

        @Test func onlyProgressChangesAtTenHertzAndWraps() throws {
            #expect(IslandPreview.progress.tick == .milliseconds(100))
            #expect(IslandPreview.collapsed.tick == nil && IslandPreview.indeterminate.tick == nil)
            let start = try IslandPreview.progress.first()
            let later = try IslandPreview.progress.advanced(start, step: 3)
            #expect(later.batch == start.batch && abs(later.fraction - 0.006) < 1e-9)
            let wrapped = try IslandPreview.progress.advanced(start, step: 600)
            #expect(abs(wrapped.fraction - 0.2) < 1e-9)
        }
    }
#endif
