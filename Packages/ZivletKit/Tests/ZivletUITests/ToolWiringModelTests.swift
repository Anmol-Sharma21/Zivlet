import EngineVision
import Foundation
import Testing
import ZivletActions

@testable import ZivletUI

@Suite("Copy Text wiring (P2-104, plan 18d D12): the working line, the result and the error copy")
struct ToolWiringModelTests {
    static let photo = URL(fileURLWithPath: "/tmp/in/photo.png")
    static let scan = URL(fileURLWithPath: "/tmp/in/scan.pdf")

    static func text(_ files: [(String, String)]) -> RecognizedText {
        TextAssembly.combine(files.map { FileText(name: $0.0, pages: [RecognizedPage(text: $0.1)]) })
    }

    @Test func theWorkingLineSaysWhetherTheOneTimePreparationRuns() {
        #expect(ToolWiringModel.workingLine(warmupDone: false, fraction: nil) == "Preparing text recognition (one time)…")
        #expect(ToolWiringModel.workingLine(warmupDone: false, fraction: 0.5) == "Preparing text recognition (one time)…")
        #expect(ToolWiringModel.workingLine(warmupDone: true, fraction: nil) == "Recognising text…")
        #expect(ToolWiringModel.workingLine(warmupDone: true, fraction: 0.42) == "Recognising text… 42%")
        #expect(ToolWiringModel.workingLine(warmupDone: true, fraction: 1) == "Recognising text… 100%")
    }

    @Test func optionWritesTextFiles() {
        #expect(ToolWiringModel.writesFiles(optionHeld: true))
        #expect(!ToolWiringModel.writesFiles(optionHeld: false))
    }

    @Test func textBecomesTheTextCard() throws {
        let recognized = Self.text([("photo.png", "आज मौसम अच्छा है\nGood day")])
        let result = ToolWiringModel.result(recognized, sources: [Self.photo], saved: [])
        let outcome = try #require(result.text)
        #expect(outcome.preview == ["आज मौसम अच्छा है", "Good day"])
        #expect(outcome.scriptLine == "Hindi and English")
        #expect(outcome.windowTitle == "Text from photo.png")
        #expect(outcome.fullText == recognized.text)
        #expect(outcome.text.files.map(\.source) == [Self.photo])
        #expect(outcome.characterCount == recognized.characterCount)
    }

    @Test func severalFilesNameTheirCountAndKeepEachText() throws {
        let recognized = Self.text([("photo.png", "One"), ("scan.pdf", "Two")])
        let outcome = try #require(ToolWiringModel.result(recognized, sources: [Self.photo, Self.scan], saved: []).text)
        #expect(outcome.windowTitle == "Text from 2 files")
        #expect(outcome.text.files.map(\.text) == ["One\n", "Two\n"])
    }

    @Test func noTextIsAToastNotAnError() {
        let result = ToolWiringModel.result(Self.text([("blank.png", "  ")]), sources: [Self.photo], saved: [])
        #expect(result == .done(toast: "No text found", undo: nil))
    }

    @Test(arguments: [
        (TextError.unavailable, "Text recognition isn't available right now."),
        (.copyingNotAllowed, "This PDF doesn't allow copying its text."),
        (.pdfLocked, "This PDF is locked."),
        (.engineCrashedOnInput, "This file made the engine crash."),
        (.tooLarge, "This file is larger than Zivlet's safety limit."),
        (.unreadable, "This file couldn't be read. It may be damaged."),
        (.tooManyPages(900), "This PDF has more than 500 pages."),
        (.recognitionFailed("Vision said no"), "Zivlet couldn't read the text in this file."),
    ])
    func everyErrorHasItsSentence(_ error: TextError, _ sentence: String) {
        #expect(ToolWiringModel.failure(error) == .failed(ActionCard(title: sentence)))
    }

    @Test func aCancelShowsNothing() {
        #expect(ToolWiringModel.failure(.cancelled) == .cancelled)
    }

    @Test func savedFilesAreNamedInTheToast() {
        #expect(ToolWiringModel.savedToast([URL(fileURLWithPath: "/tmp/photo Text.txt")]) == "Saved photo Text.txt")
        #expect(ToolWiringModel.savedToast([Self.photo, Self.scan]) == "Saved 2 text files")
    }
}
