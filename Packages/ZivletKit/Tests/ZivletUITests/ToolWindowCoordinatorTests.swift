import AppKit
import SwiftUI
import Testing
import ZivletActions
import ZivletCore

@testable import ZivletUI

@Suite("Window tools open the tool window (P2-30, plan 20b A5): one at a time, Apply admits one job")
@MainActor
struct ToolWindowCoordinatorTests {
    static let report = URL(fileURLWithPath: "/tmp/in/Report.pdf")
    static let other = URL(fileURLWithPath: "/tmp/in/Other.pdf")

    final class FakeWindow: ToolWindowing {
        var onApply: () -> Void = {}
        var onCancel: () -> Void = {}
        var onClose: () -> Void = {}
        var loaded: [ToolWindowModel] = []
        var updates: [ToolWindowModel] = []
        var shownAt: [CGPoint?] = []
        var broughtForward = 0
        var isVisible = false

        func load(_ model: ToolWindowModel, content: AnyView) { loaded.append(model) }
        func update(_ model: ToolWindowModel) { updates.append(model) }
        func show(at wheelCenter: CGPoint?) {
            shownAt.append(wheelCenter)
            isVisible = true
        }
        func bringForward() { broughtForward += 1 }
        func close() {
            isVisible = false
            onClose()
        }
        /// Esc as the real window does it: Cancel, then close.
        func pressEscape() {
            onCancel()
            close()
        }
    }

    /// A tool's content whose Apply submits one job to `submitted` unless told to stay open.
    final class FakeContent: WindowToolContent {
        let model: ToolWindowModel
        var view: AnyView { AnyView(Text("fake")) }
        var modelChanged: (ToolWindowModel) -> Void = { _ in }
        var staysOpen = false
        var cancelled = 0
        var submitted: [URL] = []
        let urls: [URL]

        init(urls: [URL]) {
            self.urls = urls
            model = ToolWindowModel(
                symbol: "lock.doc", title: "Fake",
                fileLine: ToolWindowModel.fileLine(names: urls.map(\.lastPathComponent)),
                apply: .enabled(label: "Go"))
        }

        func apply() -> Bool {
            guard !staysOpen else { return false }
            submitted += urls
            return true
        }

        func cancel() { cancelled += 1 }
    }

    final class Harness {
        var windows: [FakeWindow] = []
        var contents: [FakeContent] = []
        var refusals: [ActionResult] = []
        var windowTools: Set<ToolID> = [.pdfArrange, .stripMetadata]
        lazy var coordinator = ToolWindowCoordinator(
            makeWindow: { [unowned self] in
                let window = FakeWindow()
                windows.append(window)
                return window
            },
            contents: { [unowned self] tool, urls in
                guard windowTools.contains(tool) else { return nil }
                let content = FakeContent(urls: urls)
                contents.append(content)
                return content
            },
            refuse: { [unowned self] result, _ in refusals.append(result) })
    }

    @Test func aWindowToolOpensOneWindowAtTheWheel() throws {
        let harness = Harness()
        #expect(harness.coordinator.open(.pdfArrange, urls: [Self.report], near: CGPoint(x: 300, y: 200)))
        let window = try #require(harness.windows.first)
        #expect(window.loaded.map(\.fileLine) == ["Report.pdf"])
        #expect(window.shownAt == [CGPoint(x: 300, y: 200)])
        #expect(harness.coordinator.isOpen)
    }

    @Test func aToolWithoutAWindowIsLeftToTheCaller() {
        let harness = Harness()
        #expect(!harness.coordinator.open(.videoTrim, urls: [Self.report], near: nil))
        #expect(harness.windows.isEmpty && harness.refusals.isEmpty)
    }

    @Test func aSecondWindowToolWhileOneIsOpenBringsTheOpenOneForward() throws {
        let harness = Harness()
        harness.coordinator.open(.pdfArrange, urls: [Self.report], near: nil)
        #expect(harness.coordinator.open(.stripMetadata, urls: [Self.other], near: nil))
        let window = try #require(harness.windows.first)
        #expect(harness.windows.count == 1 && window.loaded.count == 1 && window.broughtForward == 1)
        #expect(window.loaded.first?.fileLine == "Report.pdf")
    }

    @Test func applyAdmitsExactlyOneJobAndCloses() throws {
        let harness = Harness()
        harness.coordinator.open(.pdfArrange, urls: [Self.report], near: nil)
        let window = try #require(harness.windows.first)
        window.onApply()
        #expect(harness.contents.first?.submitted == [Self.report])
        #expect(!window.isVisible && !harness.coordinator.isOpen)
        window.onApply()
        #expect(harness.contents.first?.submitted == [Self.report])
    }

    @Test func anApplyTheToolRefusesKeepsTheWindowOpen() throws {
        let harness = Harness()
        harness.coordinator.open(.pdfArrange, urls: [Self.report], near: nil)
        let window = try #require(harness.windows.first)
        harness.contents.first?.staysOpen = true
        window.onApply()
        #expect(window.isVisible && harness.coordinator.isOpen)
        #expect(harness.contents.first?.submitted == [])
    }

    @Test func cancelAdmitsNoJobAndTheNextToolOpensTheWindowAgain() throws {
        let harness = Harness()
        harness.coordinator.open(.pdfArrange, urls: [Self.report], near: nil)
        let window = try #require(harness.windows.first)
        window.pressEscape()
        #expect(harness.contents.first?.submitted == [] && harness.contents.first?.cancelled == 1)
        #expect(!harness.coordinator.isOpen)
        harness.coordinator.open(.stripMetadata, urls: [Self.other], near: nil)
        #expect(window.loaded.map(\.fileLine) == ["Report.pdf", "Other.pdf"] && window.isVisible)
        #expect(harness.windows.count == 1)
    }

    @Test func theToolsChangesReachTheWindow() throws {
        let harness = Harness()
        harness.coordinator.open(.pdfArrange, urls: [Self.report], near: nil)
        let content = try #require(harness.contents.first)
        content.modelChanged(content.model.busy())
        #expect(harness.windows.first?.updates == [content.model.busy()])
    }

    @Test func aSingleFileToolWithSeveralFilesSaysWhyInsteadOfDoingNothing() {
        let harness = Harness()
        #expect(harness.coordinator.open(.pdfArrange, urls: [Self.report, Self.other], near: nil))
        #expect(harness.windows.isEmpty)
        #expect(harness.refusals == [.failed(ActionCard(title: "This tool works on one file at a time"))])
    }

    /// Read QR's results ready while another tool's window is open wait for it, and open when it closes.
    @Test func resultsReadyWhileAnotherWindowIsOpenShowWhenItCloses() throws {
        let harness = Harness()
        harness.coordinator.open(.pdfArrange, urls: [Self.report], near: nil)
        let window = try #require(harness.windows.first)
        let results = FakeContent(urls: [Self.other])
        #expect(!harness.coordinator.present(results, near: CGPoint(x: 5, y: 5), whenFree: true))
        #expect(window.loaded.count == 1 && window.broughtForward == 1)
        window.pressEscape()
        #expect(window.loaded.map(\.fileLine) == ["Report.pdf", "Other.pdf"] && window.isVisible)
        #expect(window.shownAt.last == CGPoint(x: 5, y: 5) && harness.coordinator.isOpen)
    }

    @Test func theRealWindowIsAToolWindow() {
        let window: any ToolWindowing = ToolWindow()
        defer { window.close() }
        #expect(!window.isVisible)
    }
}
