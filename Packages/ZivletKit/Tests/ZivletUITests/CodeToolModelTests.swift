import EngineVision
import Foundation
import Testing
import ZivletActions
import ZivletCore

@testable import ZivletUI

@Suite("READ QR from the wheel (P2-51, plan 20b A10): working line, then the window, a toast or nothing")
@MainActor
struct CodeToolModelTests {
    static func code(_ payload: String) -> FoundCode { FoundCode(payload: payload, symbology: "qr", page: nil) }

    @Test func theWorkingLineCountsUpInPercent() {
        #expect(
            CodeToolModel.working(fraction: nil) == WorkingStatus(line: "Reading codes…", symbol: "qrcode.viewfinder"))
        #expect(CodeToolModel.working(fraction: 0.42).line == "Reading codes… 42%")
        #expect(CodeToolModel.working(fraction: 1.5).line == "Reading codes… 100%")
    }

    @Test func twoImagesWithCodesOpenOneWindowGroupedByFile() {
        let files = [
            FileCodes(name: "menu.png", codes: [Self.code("https://zivlet.app/test")]),
            FileCodes(name: "ticket.png", codes: [Self.code("ZIVLET-0042"), Self.code("Table 12")]),
        ]
        guard case .window(let model) = CodeToolModel.outcome(.success(files)) else {
            Issue.record("no window")
            return
        }
        #expect(model.groupsByFile && model.rows.map(\.fileName) == ["menu.png", "ticket.png", "ticket.png"])
        #expect(model.window.title == "3 codes")
    }

    @Test func oneImageWithoutCodesIsAToast() {
        let outcome = CodeToolModel.outcome(.success([FileCodes(name: "blank.png", codes: [])]))
        #expect(outcome == .hud(.done(toast: "No codes found", undo: nil)))
    }

    @Test func aFileNotReadIsANoteInTheWindow() {
        let files = [
            FileCodes(name: "menu.png", codes: [Self.code("x")]), FileCodes(name: "bad.png", error: .unreadable),
        ]
        guard case .window(let model) = CodeToolModel.outcome(.success(files)) else {
            Issue.record("no window")
            return
        }
        #expect(model.notes.first == "1 file not read")
    }

    @Test func aCancelShowsNothingAndAJobErrorItsSentence() {
        #expect(CodeToolModel.outcome(.failure(.cancelled)) == .hud(.cancelled))
        #expect(
            CodeToolModel.outcome(.failure(.unavailable))
                == .hud(.failed(ActionCard(title: "Reading codes isn't available right now."))))
        #expect(
            CodeToolModel.outcome(.failure(.tooManyFiles(limit: 500)))
                == .hud(.failed(ActionCard(title: "Read QR reads up to 500 files at a time."))))
    }

    @Test func theLogLineCountsAndNeverNamesAFileOrAPayload() {
        let files = [
            FileCodes(name: "menu.png", codes: [Self.code("secret")]), FileCodes(name: "b.png", error: .pdfLocked),
        ]
        let line = CodeToolModel.logLine(.success(files))
        #expect(line == "2 files, 1 codes, 1 not read")
        #expect(!line.contains("menu") && !line.contains("secret"))
        #expect(CodeToolModel.logLine(.failure(.cancelled)) == "cancelled")
    }

    @Test func theDemoFlagNamesAnAbsoluteFolder() {
        #if DEBUG
            #expect(CodeToolModel.demoDirectory(arguments: ["Z", "-ZivletQRDemo", "/tmp/qr"])?.path == "/tmp/qr")
            #expect(CodeToolModel.demoDirectory(arguments: ["Z", "-ZivletQRDemo", "qr"]) == nil)
            #expect(CodeToolModel.demoDirectory(arguments: ["Z", "-ZivletQRDemo"]) == nil)
            #expect(CodeToolModel.demoDirectory(arguments: ["Z"]) == nil)
        #endif
    }
}

@Suite("Results open in the tool window (plan 20b A10)")
@MainActor
struct ToolWindowPresentTests {
    @Test func resultsOpenTheWindowAndANewResultReplacesThem() throws {
        let harness = ToolWindowCoordinatorTests.Harness()
        let first = ToolWindowCoordinatorTests.FakeContent(urls: [ToolWindowCoordinatorTests.report])
        #expect(harness.coordinator.present(first, near: CGPoint(x: 10, y: 20)))
        let window = try #require(harness.windows.first)
        #expect(window.shownAt == [CGPoint(x: 10, y: 20)] && harness.coordinator.isOpen)
        let second = ToolWindowCoordinatorTests.FakeContent(urls: [ToolWindowCoordinatorTests.other])
        #expect(harness.coordinator.present(second, near: nil, replacing: { $0 === first }))
        #expect(window.loaded.map(\.fileLine) == ["Report.pdf", "Other.pdf"] && first.cancelled == 1)
        window.onApply()
        #expect(second.submitted == [ToolWindowCoordinatorTests.other] && first.submitted.isEmpty)
    }

    @Test func resultsNeverTakeTheWindowFromAnotherTool() throws {
        let harness = ToolWindowCoordinatorTests.Harness()
        harness.coordinator.open(.pdfArrange, urls: [ToolWindowCoordinatorTests.report], near: nil)
        let results = ToolWindowCoordinatorTests.FakeContent(urls: [ToolWindowCoordinatorTests.other])
        #expect(!harness.coordinator.present(results, near: nil, replacing: { _ in false }))
        #expect(harness.windows.first?.loaded.count == 1 && harness.contents.first?.cancelled == 0)
    }
}
