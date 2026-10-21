import AppKit
import Testing

@testable import ZivletActions

@Suite("Move Here panel set-up (P1-45)")
struct MovePanelTests {
    @Test func thePanelChoosesOneFolderAndStartsBesideTheFirstItem() {
        let panel = NSOpenPanel()
        let items = [Fx.file("/Users/x/Desktop/a.txt"), Fx.file("/tmp/b.txt")]
        MovePanel.configure(panel, for: items, above: .floating)
        #expect(panel.canChooseDirectories && !panel.canChooseFiles && !panel.allowsMultipleSelection)
        #expect(panel.canCreateDirectories && !panel.treatsFilePackagesAsDirectories)
        #expect(panel.prompt == "Move Here" && panel.message == "Choose where to move 2 items.")
        #expect(panel.directoryURL?.path == "/Users/x/Desktop")
        #expect(panel.level.rawValue > NSWindow.Level.floating.rawValue)
    }

    @Test func oneItemIsNamedInTheMessage() {
        let panel = NSOpenPanel()
        MovePanel.configure(panel, for: [Fx.folder("/tmp/Photos")], above: .normal)
        #expect(panel.message == "Choose where to move “Photos”.")
    }
}
