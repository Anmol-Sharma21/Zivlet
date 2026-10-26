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

    @Test func copyToSaysCopy() {
        let panel = NSOpenPanel()
        MovePanel.configure(panel, for: [Fx.file("/tmp/a.txt"), Fx.file("/tmp/b.txt")], above: .normal, mode: .copy)
        #expect(panel.prompt == "Copy Here" && panel.message == "Choose where to copy 2 items.")
        MovePanel.configure(panel, for: [Fx.file("/tmp/a.txt")], above: .normal, mode: .copy)
        #expect(panel.message == "Choose where to copy “a.txt”.")
    }

    @Test func aChooserWithoutModesAnswersBothActions() async {
        let folders = OneFolder()
        #expect(await folders.chooseFolder(for: [], mode: .copy) == URL(filePath: "/tmp"))
    }
}

/// A chooser that only knows the Move question.
private struct OneFolder: FolderChoosing {
    func chooseFolder(for items: [MoveItem]) async -> URL? { URL(filePath: "/tmp") }
}
