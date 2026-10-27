import AppKit
import NotchTestSupport
import SwiftUI
import Testing
import ZivletActions
import ZivletCore
import ZivletNotch

@testable import ZivletUI

enum TextFx {
    static func outcome(saved: [URL] = [], text: TextHolder = TextHolder("आज मौसम अच्छा है\nGood day\n"))
        -> TextOutcome
    {
        TextOutcome(
            preview: ["आज मौसम अच्छा है", "Good day"], characterCount: 342, scriptLine: "Hindi and English",
            savedFiles: saved, windowTitle: "Text from photo.png", text: text)
    }
}

@Suite("The text result (P2-104, plan 18d D11): a toast, a short card and three buttons")
@MainActor
struct TextResultTests {
    @Test func theNearDropCardsButtonsHaveTheIslandsHitArea() {
        #expect(TextResultContent.buttonSide == 28)
    }

    @Test func theResultIsAToastWithAnEightSecondLingerAndNoUndo() {
        let result = ActionResult.text(TextFx.outcome())
        #expect(result.toast == "Text copied")
        #expect(result.card == nil && result.undo == nil)
        #expect(result.linger == .seconds(8))
        #expect(ActionHUD.linger(for: result) == .seconds(8))
    }

    @Test func theCountLineSaysCharactersAndScripts() {
        #expect(TextFx.outcome().countLine == "342 characters · Hindi and English")
        let one = TextOutcome(
            preview: ["x"], characterCount: 1, scriptLine: "English", savedFiles: [], windowTitle: "t",
            text: TextHolder("x"))
        #expect(one.countLine == "1 character · English")
        let digits = TextOutcome(
            preview: ["12"], characterCount: 2, scriptLine: "", savedFiles: [], windowTitle: "t", text: TextHolder("12")
        )
        #expect(digits.countLine == "2 characters")
    }

    @Test func theCardShowsThePreviewTheCountAndThreeButtons() {
        let model = TextResultModel(TextFx.outcome())
        #expect(model.lines == ["आज मौसम अच्छा है", "Good day"])
        #expect(model.countLine == "342 characters · Hindi and English")
        #expect(model.buttons == [.copyAgain, .saveText, .showAll])
        #expect(model.savedLine == nil)
    }

    @Test func savedFilesReplaceTheSaveButtonWithALine() {
        let one = TextResultModel(TextFx.outcome(saved: [URL(fileURLWithPath: "/tmp/photo Text.txt")]))
        #expect(one.buttons == [.copyAgain, .showAll])
        #expect(one.savedLine == "Saved photo Text.txt")
        let urls = (1...3).map { URL(fileURLWithPath: "/tmp/\($0) Text.txt") }
        #expect(TextResultModel(TextFx.outcome(saved: urls)).savedLine == "Saved 3 text files")
    }

    @Test func theButtonsHaveTitlesLabelsAndSymbols() {
        #expect(TextResultButton.allCases.map(\.title) == ["Copy Again", "Save as Text", "Show All"])
        #expect(TextResultButton.allCases.map(\.accessibilityLabel) == ["Copy again", "Save as text", "Show all text"])
        #expect(TextResultButton.allCases.map(\.symbol) == ["doc.on.doc", "square.and.arrow.down", "text.alignleft"])
        for button in TextResultButton.allCases {
            #expect(NSImage(systemSymbolName: button.symbol, accessibilityDescription: nil) != nil)
        }
    }

    /// NFR-14: the preview and count lines use the secondary inks, which hold 4.5:1 on both surfaces.
    @Test func thePreviewAndCountLinesKeepTheirContrast() {
        #expect(TextResultContent.lineOpacity == HUDInk.secondaryOpacity)
        #expect(HUDInk.worstContrast(scheme: .light, textOpacity: TextResultContent.lineOpacity) >= 4.5)
        #expect(HUDInk.worstContrast(scheme: .dark, textOpacity: TextResultContent.lineOpacity) >= 4.5)
        #expect(NotchTextCard.lineOpacity == IslandInk.secondaryOpacity)
        #expect(IslandInk.contrast(textOpacity: NotchTextCard.lineOpacity) >= 4.5)
    }

    @Test func aButtonInTheHUDReachesTheAppWithTheText() {
        let hud = ActionHUD()
        defer { hud.hide() }
        var pressed: [(TextResultButton, String)] = []
        hud.onTextButton = { button, outcome in pressed.append((button, outcome.fullText)) }
        hud.show(.text(TextFx.outcome()), near: CGPoint(x: -5_000, y: -5_000))
        hud.pressText(.copyAgain)
        hud.pressText(.showAll)
        #expect(pressed.map(\.0) == [.copyAgain, .showAll])
        #expect(pressed.first?.1 == "आज मौसम अच्छा है\nGood day\n")
        #expect(hud.hideIsScheduled)
    }

    @Test func closingTheCardDropsTheText() {
        let hud = ActionHUD()
        weak var held: TextHolder?
        do {
            let holder = TextHolder("secret marker")
            held = holder
            hud.show(.text(TextFx.outcome(text: holder)), near: CGPoint(x: -5_000, y: -5_000))
        }
        #expect(held != nil)
        hud.hide()
        #expect(held == nil)
    }

    @Test func aButtonInTheIslandReachesTheAppWithTheText() throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        var pressed: [TextResultButton] = []
        rig.hud.onTextButton = { button, _ in pressed.append(button) }
        rig.hud.show(.text(TextFx.outcome()), near: NotchRig.onNotch)
        rig.hud.pressText(.saveText, onItem: .action(0))
        #expect(pressed == [.saveText])
    }
}

@Suite("Copy Text's working line (plan 18d D12): one line that the result replaces")
@MainActor
struct TextWorkingTests {
    @Test func theHUDShowsTheLineThenTheResultInItsPlace() {
        let hud = ActionHUD()
        defer { hud.hide() }
        let point = CGPoint(x: -5_000, y: -5_000)
        hud.showWorking(WorkingStatus(line: "Recognising text…", symbol: "text.viewfinder"), near: point) {}
        #expect(hud.model.result?.toast == "Recognising text…")
        hud.showWorking(WorkingStatus(line: "Recognising text… 50%", symbol: "text.viewfinder"), near: point) {}
        #expect(hud.model.result?.toast == "Recognising text… 50%")
        hud.show(.text(TextFx.outcome()), near: point)
        #expect(hud.model.result?.text != nil)
    }

    @Test func theIslandKeepsOneWorkingItemAndTheResultReplacesIt() throws {
        let rig = try NotchRig.notch()
        defer { rig.hosts.close() }
        rig.hud.showWorking(
            WorkingStatus(line: "Preparing text recognition (one time)…", symbol: "text.viewfinder"),
            near: NotchRig.onNotch
        ) {}
        rig.hud.showWorking(
            WorkingStatus(line: "Recognising text… 50%", fraction: 0.5, symbol: "text.viewfinder"),
            near: NotchRig.onNotch
        ) {}
        #expect(rig.hud.board.ordered(on: 1).count == 1)
        #expect(rig.hud.actionModel(.action(0))?.result?.toast == "Recognising text… 50%")
        rig.hud.show(.text(TextFx.outcome()), near: NotchRig.onNotch)
        let items = rig.hud.board.ordered(on: 1)
        #expect(items.map(\.id) == [.action(1)])
    }
}
