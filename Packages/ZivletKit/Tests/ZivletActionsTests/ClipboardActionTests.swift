import AppKit
import Testing

@testable import ZivletActions

/// A pasteboard that refuses every write.
final class RefusingPasteboard: PasteboardWriting {
    func replaceContents(with objects: [any NSPasteboardWriting]) -> Bool { false }
    func replaceContentsForThisMac(with objects: [any NSPasteboardWriting]) -> Bool { false }
}

/// Records which write was used and what it carried.
final class RecordingPasteboard: PasteboardWriting {
    private(set) var calls: [(thisMacOnly: Bool, strings: [String])] = []

    func replaceContents(with objects: [any NSPasteboardWriting]) -> Bool { record(objects, thisMacOnly: false) }

    func replaceContentsForThisMac(with objects: [any NSPasteboardWriting]) -> Bool {
        record(objects, thisMacOnly: true)
    }

    private func record(_ objects: [any NSPasteboardWriting], thisMacOnly: Bool) -> Bool {
        calls.append((thisMacOnly, objects.compactMap { ($0 as? NSString).map(String.init) }))
        return true
    }
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

    /// P2-104: recognised text stays on this Mac (no Universal Clipboard).
    @Test func copyTextWritesTheStringForThisMacOnly() {
        let recorder = RecordingPasteboard()
        let outcome = ClipboardAction(pasteboard: recorder).copyText("आज मौसम\nGood")
        #expect(outcome == .done(toast: "Text copied"))
        #expect(recorder.calls.count == 1)
        #expect(recorder.calls.first?.thisMacOnly == true)
        #expect(recorder.calls.first?.strings == ["आज मौसम\nGood"])
    }

    @Test func copyTextReadsBackFromARealPasteboard() {
        let board = NSPasteboard(name: .init("zivlet-test-\(UUID())"))
        defer { board.releaseGlobally() }
        _ = ClipboardAction(pasteboard: board).copyText("कुल बिल: ₹2,340.50")
        #expect(board.string(forType: .string) == "कुल बिल: ₹2,340.50")
        #expect(ClipboardAction(pasteboard: RefusingPasteboard()).copyText("x") == .failed(.clipboardRefused))
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
