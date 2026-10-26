import AppKit
import TestSupport
import Testing
import ZivletCore
import ZivletRuntime

@testable import ZivletActions

/// Hands back a fixed folder (nil = the person cancelled) and counts the questions.
final class FakeFolders: FolderChoosing {
    let answer: URL?
    private(set) var asked = 0

    init(answer: URL?) { self.answer = answer }

    func chooseFolder(for items: [MoveItem]) async -> URL? {
        asked += 1
        return answer
    }
}

/// One service over fakes and a sandbox: a private pasteboard, fake AirDrop and workspace, a real temp folder for
/// moves with a sandbox Trash, and an undo history stored in the sandbox.
@MainActor
final class ServiceRig {
    let dir: TempDir
    let board = NSPasteboard(name: .init("zivlet-test-\(UUID())"))
    let trash: SandboxTrash
    let history: UndoHistory
    var sharing = FakeSharing()
    var workspace = FakeWorkspace(installed: ["com.apple.Terminal"])
    var folders: FakeFolders
    var pasteboard: (any PasteboardWriting)?
    var terminalID = "com.apple.Terminal"
    var box: FakeBoxAdding? = FakeBoxAdding()
    private(set) var turns = 0

    init() throws {
        dir = try TempDir(prefix: "zivlet-actions")
        trash = try SandboxTrash(in: dir)
        history = UndoHistory(store: UndoStore(file: dir.url.appending(path: "undo.json")))
        folders = FakeFolders(answer: try dir.folder("dst"))
    }

    isolated deinit { board.releaseGlobally() }

    var service: ActionService {
        ActionService(
            clipboard: ClipboardAction(pasteboard: pasteboard ?? board), airDrop: AirDropAction(service: sharing),
            terminal: TerminalAction(workspace: workspace), folders: folders,
            executor: MoveExecutor(trash: trash.trash), undoHistory: history,
            box: box, terminalID: { [unowned self] in terminalID }, nextTurn: { [unowned self] in turns += 1 })
    }

    func perform(_ action: ActionID, _ urls: [URL], option: Bool = false) async -> ActionResult {
        await service.perform(action, urls: urls, optionHeld: option)
    }
}

@Suite("Action service: one entry point, toasts, cards and undo (P1-44, P1-45)")
struct ActionServiceTests {
    static func web() throws -> URL { try #require(URL(string: "https://example.com/photo.png")) }

    @Test func allOkGivesAToastForEachAction() async throws {
        let rig = try ServiceRig()
        let file = try rig.dir.file("src/a.txt")
        #expect(await rig.perform(.copyTo, [file]) == .done(toast: "Copied 1 item", undo: nil))
        #expect(await rig.perform(.copyFilePath, [file], option: true) == .done(toast: "Copied 1 path", undo: nil))
        #expect(rig.board.string(forType: .string) == "'\(file.path)'")
        #expect(await rig.perform(.shareAirDrop, [file]) == .done(toast: "Sent with AirDrop", undo: nil))
        #expect(await rig.perform(.openInTerminal, [file]) == .done(toast: "Opened in Terminal", undo: nil))
        #expect(rig.workspace.opened.map { $0.urls.map(\.lastPathComponent) } == [["src"]])
        #expect(rig.turns == 2)
    }

    @Test func aMoveIsUndoable() async throws {
        let rig = try ServiceRig()
        let file = try rig.dir.file("src/a.txt")
        let result = await rig.perform(.moveTo, [file])
        guard case .done(let toast, let undo?) = result else {
            Issue.record("expected an undoable toast, got \(result)")
            return
        }
        #expect(toast == "Moved 1 item" && rig.turns == 1 && rig.folders.asked == 1)
        #expect(FileManager.default.fileExists(atPath: rig.dir.url.appending(path: "dst/a.txt").path))
        #expect(await rig.history.undo(undo)?.restored.map(\.lastPathComponent) == ["a.txt"])
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test(arguments: ActionID.phaseOne)
    func rejectedItemsAlwaysGetACard(action: ActionID) async throws {
        let rig = try ServiceRig()
        let file = try rig.dir.file("src/a.txt")
        let result = await rig.perform(action, [file, try Self.web()])
        guard case .partial(_, let card, _) = result else {
            Issue.record("expected a partial result for \(action), got \(result)")
            return
        }
        #expect(card.title == "1 item was left out." && card.lines == ["photo.png: Not stored on this Mac."])
    }

    @Test(arguments: ActionID.phaseOne)
    func nothingLocalIsAFailureCardInTheActionsWords(action: ActionID) async throws {
        let rig = try ServiceRig()
        let result = await rig.perform(action, [try Self.web()])
        let card = ActionCard(
            title: ActionError.nothingLocal(action).userMessage, lines: ["photo.png: Not stored on this Mac."])
        #expect(result == .failed(card))
    }

    @Test func failuresBecomeCards() async throws {
        let rig = try ServiceRig()
        let file = try rig.dir.file("src/a.txt")
        rig.pasteboard = RefusingPasteboard()
        rig.sharing = FakeSharing(result: .failed(domain: NSPOSIXErrorDomain, code: 5))
        rig.terminalID = "dev.warp.Warp-Stable"
        #expect(
            await rig.perform(.copyTo, [file]) == .failed(ActionCard(title: ActionError.clipboardRefused.userMessage)))
        #expect(
            await rig.perform(.copyFilePath, [file])
                == .failed(ActionCard(title: ActionError.clipboardRefused.userMessage)))
        #expect(
            await rig.perform(.shareAirDrop, [file])
                == .failed(
                    ActionCard(
                        title: ActionError.airDropFailed(code: 5).userMessage, detail: "AirDrop reported error 5.")))
        #expect(
            await rig.perform(.openInTerminal, [file])
                == .failed(ActionCard(title: "Warp isn't installed. Choose another in Settings.")))
    }

    @Test func aMoveIntoItselfIsRefused() async throws {
        let rig = try ServiceRig()
        let folder = try rig.dir.folder("src/F")
        rig.folders = FakeFolders(answer: try rig.dir.folder("src/F/inner"))
        #expect(await rig.perform(.moveTo, [folder]) == .failed(ActionCard(title: "“F” can't be moved into itself.")))
    }

    @Test func aMoveWithSomeFailuresIsPartialAndStillUndoable() async throws {
        let rig = try ServiceRig()
        let good = try rig.dir.file("src/a.txt")
        let bad = try rig.dir.file("other/b.txt")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: bad.deletingLastPathComponent().path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: bad.deletingLastPathComponent().path)
        }
        let result = await rig.perform(.moveTo, [good, bad])
        guard case .partial(let toast, let card, let undo) = result else {
            Issue.record("expected a partial move, got \(result)")
            return
        }
        #expect(toast == "Moved 1 item" && undo != nil)
        #expect(
            card.title == "Some items weren't moved."
                && card.lines == ["“b.txt” couldn't be moved there (error \(EACCES))."])
    }

    @Test func aMoveWhereNothingMovedIsAFailure() async throws {
        let rig = try ServiceRig()
        let bad = try rig.dir.file("other/b.txt")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: bad.deletingLastPathComponent().path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: bad.deletingLastPathComponent().path)
        }
        let result = await rig.perform(.moveTo, [bad])
        #expect(
            result
                == .failed(
                    ActionCard(
                        title: "Nothing was moved.", lines: ["“b.txt” couldn't be moved there (error \(EACCES))."])))
    }

    @Test func itemsAlreadyInTheFolderAreNotAFailure() async throws {
        let rig = try ServiceRig()
        let file = try rig.dir.file("dst/a.txt")
        #expect(await rig.perform(.moveTo, [file]) == .done(toast: "Already in that folder", undo: nil))
    }

    @Test func cancellingIsSilent() async throws {
        let rig = try ServiceRig()
        let file = try rig.dir.file("src/a.txt")
        rig.folders = FakeFolders(answer: nil)
        rig.sharing = FakeSharing(result: .failed(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        #expect(await rig.perform(.moveTo, [file]) == .cancelled)
        #expect(await rig.perform(.shareAirDrop, [file]) == .cancelled)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func theBoxSliceAddsToTheCurrentBoxOrANewOneWithOption() async throws {
        let rig = try ServiceRig()
        let file = try rig.dir.file("a.txt")
        #expect(await rig.perform(.pinFloating, [file], option: true) == .done(toast: "Added 1", undo: nil))
        _ = await rig.perform(.pinFloating, [file])
        #expect(rig.box?.calls == [.init(count: 1, newBox: true), .init(count: 1, newBox: false)])
    }

    @Test func theBoxSliceRefusesNothingLocalInItsOwnWords() async throws {
        let rig = try ServiceRig()
        let result = await rig.perform(.pinFloating, [URL(string: "https://example.com/a.png")!])
        #expect(result.card?.title == "Only items stored on this Mac can be added.")
        #expect(rig.box?.calls.isEmpty == true)
    }

    @Test func withoutABoxTheSliceSaysSo() async throws {
        let rig = try ServiceRig()
        rig.box = nil
        let file = try rig.dir.file("a.txt")
        #expect(
            await rig.perform(.pinFloating, [file]) == .failed(ActionCard(title: "Zivlet couldn't open the Drop Box.")))
    }

    @Test func toastsAndCardsSayWhetherTheyCanBeUndone() {
        let batch = BatchID()
        #expect(ActionResult.done(toast: "Moved 1 item", undo: batch).undo == batch)
        #expect(ActionResult.done(toast: "Copied 1 item", undo: nil).toast == "Copied 1 item")
        #expect(ActionResult.cancelled.toast == nil && ActionResult.cancelled.card == nil)
        #expect(ActionResult.failed(ActionCard(title: "x")).card?.title == "x")
    }
}

extension ActionID {
    /// The five actions of Phase 1 (Float waits for the shelf, D-M4-13).
    nonisolated static let phaseOne: [ActionID] = [.shareAirDrop, .copyTo, .moveTo, .copyFilePath, .openInTerminal]
}

/// Records what the BOX slice asked the box to add, and answers as the box would.
@MainActor
final class FakeBoxAdding: BoxAdding {
    struct Call: Equatable {
        let count: Int
        let newBox: Bool
    }

    private(set) var calls: [Call] = []

    func add(_ urls: [URL], newBox: Bool) async -> ActionResult {
        calls.append(Call(count: urls.count, newBox: newBox))
        return .done(toast: "Added \(urls.count)", undo: nil)
    }
}
