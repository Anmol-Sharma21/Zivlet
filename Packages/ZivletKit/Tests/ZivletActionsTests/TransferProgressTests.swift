import Foundation
import TestSupport
import Testing
import ZivletCore
import ZivletRuntime

@testable import ZivletActions

/// What a TransferProgress port was told, in order.
nonisolated final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [Int] = []
    private var steps: [[Int]] = []

    var started: [Int] { lock.withLock { counts } }
    var advanced: [[Int]] { lock.withLock { steps } }

    var port: TransferProgress {
        TransferProgress(
            started: { [self] count in lock.withLock { counts.append(count) } },
            advanced: { [self] done, total in lock.withLock { steps.append([done, total]) } })
    }
}

@Suite("Move to… and Copy to… report their progress and a stop (G-M5b-9)")
@MainActor
struct TransferProgressTests {
    static let source = URL(fileURLWithPath: "/s/a.txt")
    static let moved = MovedItem(source: source, target: URL(fileURLWithPath: "/d/a.txt"), stamp: nil)
    static func left(_ count: Int) -> [URL] { (0..<count).map { URL(fileURLWithPath: "/s/left\($0).txt") } }

    @Test func theCountComesOnceThePlanIsMadeThenEachItem() async throws {
        let rig = try ServiceRig()
        let files = [try rig.dir.file("src/a.txt"), try rig.dir.file("src/b.txt"), try rig.dir.file("src/c.txt")]
        let log = ProgressLog()
        let (result, _) = await rig.service.moveReporting(files, progress: log.port)
        #expect(result.toast == "Moved 3 items")
        #expect(log.started == [3] && log.advanced == [[1, 3], [2, 3], [3, 3]])
    }

    @Test func aCancelledFolderChoiceNeverStarts() async throws {
        let rig = try ServiceRig()
        rig.folders = FakeFolders(answer: nil)
        let log = ProgressLog()
        let (result, _) = await rig.service.copyReporting([try rig.dir.file("src/a.txt")], progress: log.port)
        #expect(result == .cancelled && log.started.isEmpty && log.advanced.isEmpty)
    }

    @Test func aStoppedMoveIsPartialWithUndoForWhatMoved() {
        let batch = BatchID()
        let report = MoveReport(moved: [Self.moved, Self.moved], failures: [], skipped: [], cancelled: Self.left(9))
        #expect(
            ActionService.result(report, undo: batch)
                == .partial(
                    toast: "Moved 2 items", card: ActionCard(title: "Stopped. 9 items weren't moved."), undo: batch))
        #expect(
            ActionService.result(report, undo: batch, mode: .copy)
                == .partial(
                    toast: "Copied 2 items", card: ActionCard(title: "Stopped. 9 items weren't copied."), undo: batch))
    }

    @Test func aStopCountsTheFailuresAndListsThem() {
        let failure = MoveFailure(url: Self.source, reason: .verifyFailed)
        let report = MoveReport(moved: [Self.moved], failures: [failure], skipped: [], cancelled: [])
        let one = MoveReport(moved: [Self.moved], failures: [], skipped: [], cancelled: Self.left(1))
        let both = MoveReport(moved: [Self.moved], failures: [failure], skipped: [], cancelled: Self.left(1))
        #expect(ActionService.result(one, undo: nil).card?.title == "Stopped. 1 item wasn't moved.")
        #expect(
            ActionService.result(both, undo: nil).card
                == ActionCard(title: "Stopped. 2 items weren't moved.", lines: [failure.userMessage]))
        #expect(ActionService.result(report, undo: nil).card?.title == "Some items weren't moved.")
    }

    @Test func aStopBeforeAnythingMovedIsSilentUnlessSomethingFailed() {
        let failure = MoveFailure(url: Self.source, reason: .verifyFailed)
        let none = MoveReport(moved: [], failures: [], skipped: [], cancelled: Self.left(4))
        let failed = MoveReport(moved: [], failures: [failure], skipped: [], cancelled: Self.left(4))
        #expect(ActionService.result(none, undo: nil) == .cancelled)
        #expect(
            ActionService.result(failed, undo: nil, mode: .copy)
                == .failed(ActionCard(title: "Nothing was copied.", lines: [failure.userMessage(for: .copy)])))
    }
}
