import AppKit
import EngineVision
import ZivletActions
import ZivletCore
import ZivletRuntime
import ZivletUI
import os

/// READ QR from the wheel (P2-51, plan 20b A10, D-M7-13): the working line with Cancel where the placement says, the
/// job in the worker (`CodeService`), then the results window at the drop, "No codes found", a card for files not
/// read, or nothing after a cancel. A locked PDF is listed as "Needs a password" until P2-107 adds the prompt. Codes
/// are copied only when the person presses Copy or Copy All, and a link opens only when they press Open. Payloads
/// and file names are never logged (NFR-6).
@MainActor
final class CodeWiring {
    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "actions")
    private let codes: CodeService
    private let actions: ActionWiring
    private let toolWindows: ToolWindowWiring
    private let clipboard: ClipboardAction

    /// `clipboard` is the general pasteboard; the DEBUG Read QR demo passes a private one.
    init(codes: CodeService, actions: ActionWiring, toolWindows: ToolWindowWiring, clipboard: ClipboardAction) {
        self.codes = codes
        self.actions = actions
        self.toolWindows = toolWindows
        self.clipboard = clipboard
    }

    /// Runs READ QR; nil for every other tool.
    @discardableResult
    func run(_ tool: ToolID, urls: [URL], near point: CGPoint?) -> Task<ActionResult, Never>? {
        guard tool == .qrScan else { return nil }
        let presenter = actions.currentPresenter
        let line = WorkingLine(presenter: presenter, point: point)
        line.show(CodeToolModel.working(fraction: nil))
        let task = Task { @MainActor in
            let result = await self.read(urls, line: line)
            line.finish()
            self.logger.notice("Read QR finished: \(CodeToolModel.logLine(result), privacy: .public)")
            return self.show(CodeToolModel.outcome(result), presenter: presenter, near: point)
        }
        line.attach(task)
        return task
    }

    private func read(_ urls: [URL], line: WorkingLine) async -> Result<[FileCodes], CodeError> {
        do {
            return .success(
                try await codes.readCodes(urls) { fraction in
                    Task { @MainActor in line.show(CodeToolModel.working(fraction: fraction)) }
                })
        } catch {
            return .failure(error)
        }
    }

    /// The HUD result, or the results window (the working line is cleared first). Another tool's open window keeps
    /// its place; the codes are then announced in the HUD instead.
    private func show(_ outcome: CodeToolModel.Outcome, presenter: any ActionPresenter, near point: CGPoint?)
        -> ActionResult
    {
        switch outcome {
        case .hud(let result):
            presenter.show(result, near: point)
            return result
        case .window(let model):
            presenter.show(.cancelled, near: point)
            let content = CodeResultsContent(model: model, clipboard: clipboard)
            guard toolWindows.present(results: content, near: point) else {
                let busy = ActionResult.done(
                    toast: "\(model.window.title) found. Close the tool window to see them", undo: nil)
                presenter.show(busy, near: point)
                return busy
            }
            return .cancelled
        }
    }
}
