import AppKit
import EngineVision
import SwiftUI
import Testing
import ZivletActions

@testable import ZivletUI

@Suite("Read QR's results (P2-51, plan 20b A9, D-M7-13): Copy, Copy All and an Open that waits for a click")
@MainActor
struct CodeResultsTests {
    static let link = FoundCode(payload: "https://zivlet.app/test", symbology: "qr", page: nil)
    static let ticket = FoundCode(payload: "ZIVLET-0042", symbology: "code128", page: 2)

    static func board() -> NSPasteboard { NSPasteboard(name: NSPasteboard.Name("zivlet-test-\(UUID().uuidString)")) }

    final class Opener {
        var opened: [URL] = []
        func open(_ url: URL) { opened.append(url) }
    }

    @Test func noCodesIsAToastNotAWindow() {
        let result = CodeResults.present([FileCodes(name: "blank.png", codes: [])])
        #expect(result == .toast(.done(toast: "No codes found", undo: nil)))
    }

    @Test func twoCodesMakeAWindowWithTwoRows() throws {
        let files = [
            FileCodes(name: "menu.png", codes: [Self.link]), FileCodes(name: "ticket.pdf", codes: [Self.ticket]),
        ]
        guard case .window(let model) = CodeResults.present(files) else {
            Issue.record("no window")
            return
        }
        #expect(model.window.title == "2 codes" && model.window.symbol == "qrcode.viewfinder")
        #expect(model.window.fileLine == "2 files" && model.window.apply == .enabled(label: "Copy All"))
        #expect(model.window.cancelLabel == "Close")
        #expect(model.rows.map(\.payload) == [Self.link.payload, Self.ticket.payload])
        #expect(model.rows.map(\.fileName) == ["menu.png", "ticket.pdf"])
        #expect(model.rows[0].caption == nil && model.rows[1].caption == "Code 128 · Page 2")
        #expect(model.rows[0].link?.absoluteString == Self.link.payload && model.rows[1].link == nil)
        #expect(model.copyAllText == "https://zivlet.app/test\nZIVLET-0042")
        #expect(model.groupsByFile)
    }

    @Test func oneCodeIsCountedInTheSingular() throws {
        guard case .window(let model) = CodeResults.present([FileCodes(name: "menu.png", codes: [Self.link])]) else {
            Issue.record("no window")
            return
        }
        #expect(model.window.title == "1 code" && model.window.fileLine == "menu.png" && !model.groupsByFile)
    }

    @Test func aFileNotReadIsANoteBesideTheCodes() throws {
        let files = [FileCodes(name: "menu.png", codes: [Self.link]), FileCodes(name: "bad.png", error: .unreadable)]
        guard case .window(let model) = CodeResults.present(files) else {
            Issue.record("no window")
            return
        }
        #expect(model.notes == ["1 file not read", "bad.png: This file couldn't be read"])
    }

    @Test func noCodesAndAFileNotReadIsACardNamingIt() {
        let files = [FileCodes(name: "locked.pdf", error: .pdfLocked), FileCodes(name: "blank.png", codes: [])]
        let card = ActionCard(title: "1 file not read", lines: ["locked.pdf: Needs a password"])
        #expect(CodeResults.present(files) == .toast(.partial(toast: "No codes found", card: card, undo: nil)))
        let only = [FileCodes(name: "locked.pdf", error: .pdfLocked)]
        #expect(
            CodeResults.present(only) == .toast(.failed(ActionCard(title: "Needs a password", lines: ["locked.pdf"]))))
    }

    @Test func copyWritesOneRowAndCopyAllEveryRowForThisMacOnly() throws {
        let board = Self.board()
        defer { board.releaseGlobally() }
        let opener = Opener()
        let content = try Self.content([Self.link, Self.ticket], board: board, opener: opener)
        content.press(.copy, row: 1)
        #expect(board.string(forType: .string) == "ZIVLET-0042")
        #expect(content.apply())
        #expect(board.string(forType: .string) == "https://zivlet.app/test\nZIVLET-0042")
    }

    @Test func openRunsOnlyAfterAClickAndOnlyForAWebLink() throws {
        let opener = Opener()
        let content = try Self.content([Self.link, Self.ticket], board: Self.board(), opener: opener)
        let host = NSHostingView(rootView: content.view)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.height > 0)
        #expect(opener.opened.isEmpty)
        content.press(.open, row: 1)
        #expect(opener.opened.isEmpty)
        content.press(.open, row: 0)
        #expect(opener.opened == [URL(string: "https://zivlet.app/test")])
        content.press(.copy, row: 9)
        content.cancel()
    }

    @Test func eachRowHasItsVoiceOverWords() {
        let row = CodeRow(index: 0, code: Self.link, fileName: "menu.png")
        #expect(CodeResultsView.openHint(row) == "Opens in your browser: https://zivlet.app/test")
        #expect(
            CodeRow(index: 1, code: FoundCode(payload: "file:///x", symbology: "qr", page: nil), fileName: "a")
                .caption == "Not a web link")
    }

    static func content(_ codes: [FoundCode], board: NSPasteboard, opener: Opener) throws -> CodeResultsContent {
        guard case .window(let model) = CodeResults.present([FileCodes(name: "menu.png", codes: codes)]) else {
            throw CodeResultsTestError.noWindow
        }
        return CodeResultsContent(
            model: model, clipboard: ClipboardAction(pasteboard: board), open: { opener.open($0) })
    }

    enum CodeResultsTestError: Error { case noWindow }
}
