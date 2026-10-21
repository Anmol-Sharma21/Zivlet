import Foundation
import Testing

@testable import ZivletActions

/// Records what would be opened instead of launching apps.
final class FakeWorkspace: WorkspaceOpening {
    let installed: Set<String>
    let failure: (any Error)?
    private(set) var opened: [(urls: [URL], app: URL)] = []

    init(installed: Set<String>, failure: (any Error)? = nil) {
        self.installed = installed
        self.failure = failure
    }

    func applicationURL(for bundleID: String) -> URL? {
        installed.contains(bundleID) ? URL(fileURLWithPath: "/Applications/\(bundleID).app") : nil
    }

    func open(_ urls: [URL], withApplicationAt app: URL) async throws {
        if let failure { throw failure }
        opened.append((urls, app))
    }
}

@Suite("Open in Terminal (P1-45)")
struct TerminalActionTests {
    @Test func opensTheFoldersInTheChosenTerminal() async {
        let workspace = FakeWorkspace(installed: ["com.apple.Terminal", "com.mitchellh.ghostty"])
        let outcome = await TerminalAction(workspace: workspace).open(
            [Fx.file("/p/a.txt"), Fx.folder("/q")], terminalID: "com.mitchellh.ghostty")
        #expect(outcome == .done(toast: "Opened in Ghostty"))
        #expect(workspace.opened.map { $0.urls.map(\.path) } == [["/p", "/q"]])
        #expect(workspace.opened.map(\.app.lastPathComponent) == ["com.mitchellh.ghostty.app"])
    }

    @Test func anUnknownIDOpensTerminal() async {
        let workspace = FakeWorkspace(installed: ["com.apple.Terminal"])
        let outcome = await TerminalAction(workspace: workspace).open([Fx.folder("/q")], terminalID: "bogus")
        #expect(outcome == .done(toast: "Opened in Terminal"))
    }

    @Test func aChosenTerminalThatIsNotInstalledSaysSo() async {
        let workspace = FakeWorkspace(installed: ["com.apple.Terminal"])
        let outcome = await TerminalAction(workspace: workspace).open(
            [Fx.folder("/q")], terminalID: "dev.warp.Warp-Stable")
        #expect(outcome == .failed(.terminalMissing("Warp")) && workspace.opened.isEmpty)
    }

    @Test func aLaunchFailureKeepsItsCode() async {
        let workspace = FakeWorkspace(installed: ["com.apple.Terminal"], failure: CocoaError(.fileReadNoPermission))
        let outcome = await TerminalAction(workspace: workspace).open(
            [Fx.folder("/q")], terminalID: "com.apple.Terminal")
        #expect(outcome == .failed(.terminalFailed("Terminal", code: CocoaError.fileReadNoPermission.rawValue)))
    }
}
