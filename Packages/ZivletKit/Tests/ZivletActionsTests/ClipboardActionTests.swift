import AppKit
import Testing

@testable import ZivletActions

/// A pasteboard that refuses every write.
final class RefusingPasteboard: PasteboardWriting {
    func replaceContents(with objects: [any NSPasteboardWriting]) -> Bool { false }
}

@Suite("Copy and Copy Path write the pasteboard (P1-44)")
struct ClipboardActionTests {
    @Test func copyWritesFileURLs() throws {
        let board = NSPasteboard(name: .init("zivlet-test-\(UUID())"))
        defer { board.releaseGlobally() }
        let urls = [URL(fileURLWithPath: "/etc/hosts"), URL(fileURLWithPath: "/etc/shells")]
        let outcome = ClipboardAction(pasteboard: board).copyItems(urls)
        #expect((board.readObjects(forClasses: [NSURL.self]) as? [URL]) == urls)
        #expect(outcome == .done(toast: "Copied 2 items"))
        #expect(ClipboardAction(pasteboard: board).copyItems([urls[0]]).toast == "Copied 1 item")
    }

    @Test func copyReplacesWhatWasOnThePasteboard() {
        let board = NSPasteboard(name: .init("zivlet-test-\(UUID())"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("old", forType: .string)
        _ = ClipboardAction(pasteboard: board).copyItems([URL(fileURLWithPath: "/etc/hosts")])
        #expect(board.string(forType: .string) != "old")
    }

    @Test func copyPathWritesOneStringAndOptionQuotes() throws {
        let board = NSPasteboard(name: .init("zivlet-test-\(UUID())"))
        defer { board.releaseGlobally() }
        let action = ClipboardAction(pasteboard: board)
        _ = action.copyPaths([URL(fileURLWithPath: "/a b")], shellQuoted: true)
        #expect(board.string(forType: .string) == "'/a b'")
        #expect(action.copyPaths([URL(fileURLWithPath: "/x")], shellQuoted: false).toast == "Copied 1 path")
        let two = [URL(fileURLWithPath: "/x"), URL(fileURLWithPath: "/y z")]
        #expect(action.copyPaths(two, shellQuoted: false) == .done(toast: "Copied 2 paths"))
        #expect(board.string(forType: .string) == "/x\n/y z")
    }

    @Test func aRefusedWriteIsAFailureWithUserCopy() {
        let action = ClipboardAction(pasteboard: RefusingPasteboard())
        let url = URL(fileURLWithPath: "/x")
        #expect(action.copyItems([url]) == .failed(.clipboardRefused))
        #expect(action.copyPaths([url], shellQuoted: false) == .failed(.clipboardRefused))
        #expect(ActionError.clipboardRefused.userMessage == "Zivlet couldn't write to the clipboard. Try again.")
        #expect(ActionOutcome.failed(.clipboardRefused).toast == nil)
    }
}
