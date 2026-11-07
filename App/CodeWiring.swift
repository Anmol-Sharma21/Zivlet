import AppKit
import EngineVision
import ZivletActions
import ZivletCore
import ZivletRuntime
import ZivletUI
import os

/// READ QR from the wheel (P2-51, plan 20b A10, D-M7-13): the working line with Cancel where the placement says, the
/// job in the worker (`CodeService`), then the results window at the drop, "No codes found", a card for files not
/// read, or nothing after a cancel. A locked PDF asks for its password once (P2-107, plan 20f E10); one left locked is
/// listed as "Needs a password". Codes
/// are copied only when the person presses Copy or Copy All, and a link opens only when they press Open. Payloads
/// and file names are never logged (NFR-6).
@MainActor
final class CodeWiring {
    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "actions")
    private let codes: CodeService
    private let actions: ActionWiring
    private let toolWindows: ToolWindowWiring
    private let clipboard: ClipboardAction
    /// Asks for a locked PDF's password (set once the password sheet exists).
    var prompter: (any PasswordPrompting)?
    #if DEBUG
        /// The DEBUG Read QR demo's report (plan 20g F3): what each run showed, before it is shown.
        var outcomeObserver: (@MainActor (CodeToolModel.Outcome) -> Void)?
    #endif

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
            let result = await self.unlocking(await self.read(urls, line: line), urls: urls, near: point)
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

    /// Each locked PDF asks for its password; its own job then replaces its line (plan 20f E10). An error other than
    /// "still locked" becomes that file's line, never a wrong password; a cancelled job ends Read QR.
    private func unlocking(_ result: Result<[FileCodes], CodeError>, urls: [URL], near point: CGPoint?) async
        -> Result<[FileCodes], CodeError>
    {
        guard let prompter, case .success(let files) = result else { return result }
        let locked = files.indices.filter { files[$0].error == .pdfLocked && urls.indices.contains($0) }
        guard !locked.isEmpty else { return result }
        let codes = self.codes
        let outcomes = await LockedInputPrompting.unlockEach(locked.map { urls[$0] }, prompter: prompter, near: point) {
            file, secrets -> LockedAttempt<FileCodes, CodeError> in
            do throws(CodeError) {
                guard let read = try await codes.readCodes([file], secrets: secrets).first else {
                    return .failed(.unreadable)
                }
                return read.error == .pdfLocked ? .stillLocked : .opened(read)
            } catch {
                return .failed(error)
            }
        }
        var merged = files
        for (index, outcome) in zip(locked, outcomes) {
            switch outcome {
            case .opened(let read): merged[index] = read
            case .cancelled, .failed(.cancelled): return .failure(.cancelled)
            case .failed(let error): merged[index] = FileCodes(name: files[index].name, error: error)
            case .skipped, .unavailable: break
            }
        }
        return .success(merged)
    }

    /// The HUD result, or the results window (the working line is cleared first). Another tool's open window keeps
    /// its place; the HUD then says the codes open when it closes, and they do.
    private func show(_ outcome: CodeToolModel.Outcome, presenter: any ActionPresenter, near point: CGPoint?)
        -> ActionResult
    {
        #if DEBUG
            outcomeObserver?(outcome)
        #endif
        switch outcome {
        case .hud(let result):
            presenter.show(result, near: point)
            return result
        case .window(let model):
            presenter.show(.cancelled, near: point)
            let content = CodeResultsContent(model: model, clipboard: clipboard)
            guard toolWindows.present(results: content, near: point) else {
                let busy = ActionResult.done(
                    toast: "\(model.window.title) found. They open when the window closes", undo: nil)
                presenter.show(busy, near: point)
                return busy
            }
            return .cancelled
        }
    }
}
