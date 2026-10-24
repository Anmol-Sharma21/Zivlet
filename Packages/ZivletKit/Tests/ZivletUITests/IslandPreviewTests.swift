import Testing
import ZivletActions
import ZivletCore
import ZivletNotchCore
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

        @Test(arguments: ["list", "savedToast", "failureToast", "actionToast"])
        func theNewPreviewStatesParse(value: String) throws {
            #expect(try IslandPreview.parse(arguments: ["-ZivletIslandPreview", value]) != nil)
            let state = try #require(IslandPreview(rawValue: value))
            #expect(state.opens == (state == .list) && state.tick == nil)  // the list shows only when opened
        }

        @Test func theListPreviewHasSevenItemsOneFailed() throws {
            let snapshots = try IslandPreview.list.snapshots()
            #expect(snapshots.count == 7 && snapshots.filter { !$0.failures.isEmpty }.count == 1)
            let board = snapshots.reduce(NotchHUDBoard()) { $0.updating($1, display: 1, now: .seconds(1)) }
            #expect(board.rows(on: 1).count == 5 && board.moreLabel(on: 1) == "+2 more")
            #expect(board.rows(on: 1).first?.status == .failed)
            #expect(Set(snapshots.map(\.target)).count >= 3)  // the tab and rows show several families
        }

        @Test func theToastStatesShowOneFinishedBatchOrAnActionWithUndo() throws {
            #expect(try IslandPreview.savedToast.snapshots().map(\.outputs.count) == [1])
            #expect(try IslandPreview.failureToast.snapshots().map(\.failures.count) == [1])
            #expect(try IslandPreview.actionToast.snapshots().isEmpty)
            #expect(IslandPreview.actionToast.action?.undo != nil && IslandPreview.result.action == nil)
        }

        @Test func theScreenshotFlagsParse() throws {
            let flags = try IslandShotFlags.parse(arguments: [
                "Z", "-ZivletIslandFinish", "contrast", "-ZivletIslandPill", "YES", "-ZivletIslandBackdrop", "white",
            ])
            #expect(flags.finish == IslandFinish.Settings(reduceTransparency: false, increaseContrast: true))
            #expect(flags.pill && flags.backdrop == .white && !flags.reduceMotion)
            #expect(try IslandShotFlags.parse(arguments: ["Z", "-ZivletIslandReduceMotion", "YES"]).reduceMotion)
            #expect(
                try IslandShotFlags.parse(arguments: ["Z", "-ZivletIslandFinish", "solid"]).finish?.reduceTransparency
                    == true)
            #expect(try IslandShotFlags.parse(arguments: ["Z", "-ZivletIslandFinish", "glass"]).finish == .standard)
            #expect(try IslandShotFlags.parse(arguments: ["Z"]) == IslandShotFlags())
            #expect(throws: IslandShotFlags.Invalid.unknown("-ZivletIslandFinish", "frosted")) {
                try IslandShotFlags.parse(arguments: ["Z", "-ZivletIslandFinish", "frosted"])
            }
        }
    }
#endif
