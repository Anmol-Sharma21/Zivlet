import EngineVision
import Foundation
import TestSupport
import Testing
import ZivletActions

@testable import ZivletUI

@Suite("Copy Text keeps what it read (P2-104): files not read, a refused clipboard and unsaved files are notes")
@MainActor
struct TextDeliveryTests {
    static let sources = ["a.png", "bad.pdf", "c.png"].map { URL(fileURLWithPath: "/tmp/in/\($0)") }

    static func text(_ pages: [String?]) -> RecognizedText {
        let names = sources.map(\.lastPathComponent)
        let files = zip(names, pages).map { FileText(name: $0.0, pages: $0.1.map { [RecognizedPage(text: $0)] } ?? []) }
        let skipped = zip(names, pages).filter { $0.1 == nil }.map { SkippedFile(name: $0.0, error: .pdfLocked) }
        return TextAssembly.combine(files, skipped: skipped)
    }

    @Test func aFileNotReadIsANoteOnTheTextCard() throws {
        let result = ToolWiringModel.result(Self.text(["First", nil, "Third"]), sources: Self.sources)
        let outcome = try #require(result.text)
        #expect(outcome.notes == ["1 file couldn't be read.", "bad.pdf — locked"])
        #expect(outcome.text.files.map(\.source.lastPathComponent) == ["a.png", "c.png"])
        #expect(result.toast == "Text copied")
    }

    @Test func noFileReadIsACardThatNamesThem() {
        let all = ToolWiringModel.result(Self.text([nil, nil, nil]), sources: Self.sources)
        #expect(all.card?.title == "3 files couldn't be read.")
        #expect(all.card?.lines.first == "a.png — locked")
        #expect(all.toast == nil)
        let some = ToolWiringModel.result(Self.text(["", nil, ""]), sources: Self.sources)
        #expect(some.toast == "No text found" && some.card?.lines == ["bad.pdf — locked"])
    }

    @Test func aSingleFileNotReadKeepsItsSentenceAndIsNamed() {
        let one = TextAssembly.combine(
            [FileText(name: "scan.pdf", pages: [])], skipped: [SkippedFile(name: "scan.pdf", error: .pdfLocked)])
        let result = ToolWiringModel.result(one, sources: [URL(fileURLWithPath: "/tmp/scan.pdf")])
        #expect(result.card == ActionCard(title: "This PDF is locked.", lines: ["scan.pdf"]))
    }

    @Test func aRefusedClipboardKeepsTheTextCard() throws {
        let result = ToolWiringModel.result(
            Self.text(["First", "Second", "Third"]), sources: Self.sources, delivery: TextDelivery(copied: false))
        let outcome = try #require(result.text)
        #expect(result.toast == "Text found")
        #expect(outcome.notes == [TextCopy.clipboardRefused])
        #expect(TextResultModel(outcome).buttons.contains(.copyAgain))
    }

    @Test func unsavedTextFilesAreNotesAndTheSavedOnesAreKept() throws {
        let saved = [URL(fileURLWithPath: "/tmp/in/a Text.txt")]
        let delivery = TextDelivery(
            copied: true, saved: saved, notSaved: [NotSavedFile(name: "c.png", reason: "The folder is full.")])
        let outcome = try #require(
            ToolWiringModel.result(Self.text(["First", "Second", "Third"]), sources: Self.sources, delivery: delivery)
                .text)
        #expect(outcome.savedFiles == saved)
        #expect(outcome.notes == ["1 text file wasn't saved.", "c.png — The folder is full."])
    }

    @Test func saveAsTextReportsBothSavedAndNotSaved() {
        let saved = [URL(fileURLWithPath: "/tmp/a Text.txt"), URL(fileURLWithPath: "/tmp/b Text.txt")]
        let failed = [NotSavedFile(name: "c.png", reason: "x")]
        #expect(
            ToolWiringModel.saved(TextDelivery(copied: true, saved: saved))
                == .done(toast: "Saved 2 text files", undo: nil))
        let partial = ToolWiringModel.saved(TextDelivery(copied: true, saved: saved, notSaved: failed))
        #expect(partial.toast == "Saved 2 text files" && partial.card?.lines == ["c.png — x"])
        #expect(ToolWiringModel.saved(TextDelivery(copied: true, notSaved: failed)).toast == nil)
    }

    @Test func manyNotesAreCutAfterThree() {
        #expect(TextCopy.listed("t", ["1", "2", "3", "4", "5"]) == ["t", "1", "2", "3", "and 2 more"])
        #expect(TextCopy.listed("t", []).isEmpty)
    }

    @Test func noTextSaysWhenHindiWasSkipped() {
        let empty = TextAssembly.combine([FileText(name: "a.png", pages: [])])
        let sources = [URL(fileURLWithPath: "/tmp/a.png")]
        #expect(
            ToolWiringModel.result(empty, sources: sources, skipsHindi: true).toast
                == ToolWiringModel.noTextWithoutHindi)
        #expect(ToolWiringModel.result(empty, sources: sources).toast == ToolWiringModel.noText)
    }

    @Test func tooManyFilesHasItsOwnSentence() {
        #expect(
            ToolWiringModel.failure(.tooManyFiles(limit: 200)).card?.title
                == "Copy Text reads up to 200 files at a time.")
    }

    @Test func savingGoesOnPastAFailedFile() async throws {
        let dir = try TempDir(prefix: "zivlet-text-saving")
        let good = try dir.file("good.png")
        let missing = dir.url.appending(path: "gone/missing.png")
        let delivery = await TextSaver.save(
            [TextFile(source: missing, text: "x"), TextFile(source: good, text: "y")],
            fallbackFolder: dir.url.appending(path: "no-such-folder"), copied: true)
        #expect(delivery.saved.map(\.lastPathComponent) == ["good Text.txt"])
        #expect(delivery.notSaved.map(\.name) == ["missing.png"])
    }
}
