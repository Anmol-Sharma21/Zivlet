import Foundation
import Testing

@testable import ZivletActions

@Suite("Terminal choices and folders to open (P1-45, 03b §7 row 6)")
struct TerminalCatalogTests {
    @Test func theFiveTerminalsInOrderWithTerminalFirst() {
        #expect(TerminalCatalog.all.map(\.name) == ["Terminal", "iTerm2", "Ghostty", "WezTerm", "Warp"])
        #expect(
            TerminalCatalog.all.map(\.id) == [
                "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "com.github.wez.wezterm",
                "dev.warp.Warp-Stable",
            ])
        #expect(TerminalCatalog.standard == TerminalCatalog.all[0])
    }

    @Test func anUnknownStoredIDMeansTerminal() {
        #expect(TerminalCatalog.resolve("com.example.not-a-terminal") == TerminalCatalog.standard)
        #expect(TerminalCatalog.resolve("com.mitchellh.ghostty").name == "Ghostty")
    }

    @Test func foldersStayFilesAndPackagesBecomeTheirParentWithoutDuplicates() {
        let items = [
            Fx.folder("/p/Project"), Fx.file("/p/Project/readme.md"), Fx.file("/p/notes.txt"),
            Fx.package("/p/Tool.app"), Fx.folder("/p/Project/"),
        ]
        #expect(TerminalTargets.directories(for: items).map(\.path) == ["/p/Project", "/p"])
    }

    @Test func installedIsWhatTheWorkspaceCanFind() {
        let workspace = FakeWorkspace(installed: ["com.apple.Terminal", "com.mitchellh.ghostty"])
        #expect(TerminalCatalog.installed(workspace).map(\.name) == ["Terminal", "Ghostty"])
    }

    @Test func terminalIsInstalledOnThisMac() {
        #expect(TerminalCatalog.installed(SystemWorkspace()).contains(TerminalCatalog.standard))
    }

    @Test func missingAndFailedTerminalsHaveUserCopy() {
        #expect(
            ActionError.terminalMissing("Ghostty").userMessage == "Ghostty isn't installed. Choose another in Settings."
        )
        #expect(ActionError.terminalFailed("Warp", code: 3).userMessage == "Zivlet couldn't open Warp.")
        #expect(ActionError.terminalFailed("Warp", code: 3).detail == "The system reported error 3.")
    }
}
