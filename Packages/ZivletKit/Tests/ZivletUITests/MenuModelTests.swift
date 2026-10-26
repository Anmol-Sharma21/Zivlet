import Foundation
import Testing
import ZivletCore
import ZivletRuntime
import ZivletTrigger

@testable import ZivletUI

enum MenuFx {
    static let ids = (0..<20).map { _ in BatchID() }
    static func batchID(_ index: Int) -> BatchID { ids[index] }

    static func batch(_ name: String, percent: Int, index: Int = 0) -> MenuBatch {
        MenuBatch(id: batchID(index), name: name, percent: percent)
    }

    static func recent(_ index: Int) -> MenuRecent {
        MenuRecent(batch: batchID(index), title: "file \(index).png", urls: [URL(filePath: "/tmp/file \(index).png")])
    }
}

@Suite("Menu model (D4, 03b §8.3)")
struct MenuModelTests {
    @Test func idleMenuHasTheFixedItemsInOrder() {
        let titles = MenuModel.make(state: .idle(bindings: .standard)).map(\.title)
        #expect(
            titles == [
                "Zivlet is ready", "⇧: Convert · ⌘: Tools · ⌃: Actions", "—", "Show Progress and Results",
                "Show Drop Box", "Settings…", "Practice…", "Pause Zivlet", "Check for Updates…", "—", "About Zivlet",
                "Quit Zivlet",
            ])
    }

    @Test func infoLinesAreDisabledAndCommandsCarryTheirActionsAndKeys() {
        let entries = MenuModel.make(state: .idle(bindings: .standard, canCheckForUpdates: true))
        #expect(!entries[0].isEnabled && !entries[1].isEnabled)
        let settings = entries.first { $0.title == "Settings…" }
        #expect(settings?.action == .settings && settings?.keyEquivalent == ",")
        #expect(entries.first { $0.title == "Quit Zivlet" }?.keyEquivalent == "q")
        #expect(entries.first { $0.title == "Check for Updates…" }?.isEnabled == true)
        #expect(entries.map(\.action).contains(.practice) && entries.map(\.action).contains(.about))
    }

    @Test func showProgressAndResultsIsEnabledOnlyWhileTheIslandHasItems() {
        let idle = MenuModel.make(state: .idle(bindings: .standard))
        let show = idle.first { $0.title == "Show Progress and Results" }
        #expect(show?.isEnabled == false && show?.action == .showProgress)
        let busy = MenuState(bindings: .standard, paused: false, batches: [], recent: [], islandHasItems: true)
        #expect(MenuModel.make(state: busy).first { $0.title == "Show Progress and Results" }?.isEnabled == true)
    }

    @Test func showDropBoxFollowsShowProgressAndIsAlwaysEnabled() {
        let entries = MenuModel.make(state: .idle(bindings: .standard))
        let titles = entries.map(\.title)
        let index = titles.firstIndex(of: "Show Drop Box")
        #expect(index != nil && index == titles.firstIndex(of: "Show Progress and Results").map { $0 + 1 })
        let entry = entries.first { $0.title == "Show Drop Box" }
        #expect(entry?.action == .showDropBox && entry?.isEnabled == true)
    }

    @Test func checkForUpdatesIsDisabledUntilTheUpdaterRuns() {
        let entries = MenuModel.make(state: .idle(bindings: .standard))
        #expect(entries.first { $0.title == "Check for Updates…" }?.isEnabled == false)
    }

    @Test func workingShowsOneRowPerBatchAndTheCount() {
        let state = MenuState(
            bindings: .standard, paused: false,
            batches: [MenuFx.batch("holiday video.mov", percent: 40), MenuFx.batch("a.wav", percent: 90, index: 1)],
            recent: [])
        let entries = MenuModel.make(state: state)
        #expect(entries.first?.title == "Working on 2")
        #expect(entries.contains { $0.title == "holiday video.mov — 40%" && $0.action == .cancel(MenuFx.batchID(0)) })
        #expect(entries.first { $0.title == "a.wav — 90%" }?.subtitle == "Click to cancel")
    }

    @Test(arguments: [
        ("short.png", "short.png"),
        ("a very long file name that keeps going and going.mov", "a very long file…going and going.mov"),
        ("noextension-but-a-really-long-name-indeed-yes", "noextension-but-a-r…ng-name-indeed-yes"),
    ])
    func namesAreMiddleTruncatedTo38KeepingTheExtension(name: String, shown: String) {
        let truncated = NameTruncation.middle(name, limit: 38)
        #expect(truncated.count <= 38)
        #expect(truncated == shown)
    }

    @Test func aBatchNameIsTruncatedInItsRow() {
        let long = String(repeating: "x", count: 60) + ".mp4"
        let state = MenuState(
            bindings: .standard, paused: false, batches: [MenuFx.batch(long, percent: 5)], recent: [])
        let row = MenuModel.make(state: state).first { $0.action == .cancel(MenuFx.batchID(0)) }
        #expect(row?.title.hasSuffix(".mp4 — 5%") == true && (row?.title.count ?? 0) <= 38 + " — 5%".count)
    }

    @Test func pausedChangesTheStateLineAndToggle() {
        let entries = MenuModel.make(state: .idle(bindings: .standard, paused: true))
        #expect(entries.first?.title == "Paused" && entries.contains { $0.title == "Resume Zivlet" })
        #expect(entries.first { $0.title == "Resume Zivlet" }?.action == .togglePause)
    }

    @Test func recentResultsListsAtMostTenEachWithRevealAndUndo() throws {
        let state = MenuState(bindings: .standard, paused: false, batches: [], recent: (0..<14).map(MenuFx.recent))
        let recent = try #require(MenuModel.make(state: state).first { $0.title == "Recent Results" })
        #expect(recent.children.count == 10)
        let first = try #require(recent.children.first)
        #expect(first.title == "file 0.png")
        #expect(first.children.map(\.title) == ["Show in Finder", "Undo"])
        #expect(first.children.map(\.action) == [.reveal(MenuFx.batchID(0)), .undo(MenuFx.batchID(0))])
    }

    @Test func theSummaryFollowsTheBindings() throws {
        let bindings = try TriggerBindings(convert: .option, tools: .command, actions: .control)
        #expect(MenuModel.make(state: .idle(bindings: bindings))[1].title == "⌥: Convert · ⌘: Tools · ⌃: Actions")
    }
}

@Suite("Menu inputs from batches and undo entries (D4)")
struct MenuInputTests {
    @Test func activeBatchesKeepUnfinishedOnesInOrder() {
        let a = BatchSnapshot(batch: BatchID(), target: .png, plan: RequestPlan(requests: [], rejections: []))
        let b = BatchSnapshot(batch: BatchID(), target: .png, plan: RequestPlan(requests: [], rejections: []))
        let active = ActiveBatches().updating(a).updating(b).updating(a)
        #expect(active.snapshots.map(\.batch) == [a.batch, b.batch])
        #expect(active.removing(a.batch).snapshots.map(\.batch) == [b.batch])
    }

    @Test func aRecentEntryIsTitledByItsFirstItem() {
        let batch = BatchID()
        let urls = [URL(filePath: "/tmp/a.png"), URL(filePath: "/tmp/b.png"), URL(filePath: "/tmp/c.png")]
        #expect(MenuRecent(batch: batch, urls: urls).title == "a.png and 2 more")
        #expect(MenuRecent(batch: batch, urls: [urls[0]]).title == "a.png")
    }
}
