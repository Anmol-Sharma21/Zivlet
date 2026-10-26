import Foundation
import Testing
import ZivletActions
import ZivletRuntime
import ZivletShelfCore

@testable import ZivletBox

/// Polls the main actor until `condition` holds, for at most about five seconds.
@MainActor
func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<500 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    #expect(condition())
}

@Suite("The box's busy overlay for Move to… and Copy to…, with Cancel and Esc (G-M5b-9)")
@MainActor
struct BoxBusyTests {
    static func pausedBox(_ rig: BoxRig, items: Int, gate: RenameGate) async throws -> (BoxController, [URL]) {
        rig.executor = MoveExecutor(rename: gate.rename, trash: { _ in })
        let box = rig.controller()
        box.start()
        let files = try rig.files(items)
        _ = await box.add(files, newBox: false)
        box.showPanel()
        return (box, files)
    }

    @Test func escapeStopsAMoveAndKeepsUndoForThePartThatMoved() async throws {
        let rig = try BoxRig()
        let gate = RenameGate(pauseAt: 4)
        let (box, files) = try await Self.pausedBox(rig, items: 12, gate: gate)
        box.press(.moveTo)
        try await waitUntil { box.presentation.overlay == .busy(verb: "Moving 12 items", fraction: 0.25) }
        box.apply(.escape)
        gate.resume()
        await box.running?.value
        let result = try #require(rig.results.results.last)
        #expect(result.toast == "Moved 4 items")
        #expect(result.card?.title == "Stopped. 8 items weren't moved.")
        #expect(box.presentation.overlay == nil)
        let destination = rig.destination.standardizedFileURL.path
        #expect(box.library.current?.items.prefix(4).allSatisfy { $0.lastKnownPath.hasPrefix(destination) } == true)
        #expect(files.dropFirst(4).allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let undone = await rig.undo.undo(try #require(result.undo))
        #expect(undone?.restored.count == 4 && files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        box.hidePanel()
    }

    @Test func theCancelButtonStopsACopyInItsOwnWords() async throws {
        let rig = try BoxRig()
        let gate = RenameGate(pauseAt: 2)
        let (box, files) = try await Self.pausedBox(rig, items: 3, gate: gate)
        box.press(.copyTo)
        try await waitUntil { box.presentation.overlay == .busy(verb: "Copying 3 items", fraction: 1 / 3) }
        box.press(.cancelBusy)
        gate.resume()
        await box.running?.value
        let result = try #require(rig.results.results.last)
        #expect(result.toast == "Copied 2 items" && result.card?.title == "Stopped. 1 item wasn't copied.")
        #expect(result.undo != nil && box.presentation.overlay == nil)
        #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        box.hidePanel()
    }

    @Test func aMoveThatRunsToTheEndRemovesTheOverlay() async throws {
        let rig = try BoxRig()
        let gate = RenameGate(pauseAt: 0)
        let (box, _) = try await Self.pausedBox(rig, items: 2, gate: gate)
        box.press(.moveTo)
        await box.running?.value
        #expect(rig.results.results.map(\.toast) == ["Moved 2 items"] && box.presentation.overlay == nil)
        box.hidePanel()
    }

    @Test func busyVerbsCountTheItems() {
        #expect(BoxCopy.moving(1) == "Moving 1 item" && BoxCopy.copying(12) == "Copying 12 items")
        #expect(BoxCopy.trashing(3) == "Moving 3 items to the Trash")
    }
}
