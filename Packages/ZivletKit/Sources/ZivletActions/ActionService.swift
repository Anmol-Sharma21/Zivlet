import Foundation
import ZivletCore
import ZivletRuntime

/// One entry point for the six actions (P1-44, P1-45; BOX from P2-55): validates the drop, runs the action and turns its
/// outcome into a toast, a card or nothing. AirDrop, Move and Terminal wait one run-loop turn first, so the wheel
/// and the drag session are gone before a sheet or panel takes focus (03b §7 "Ordering"). Moves are recorded in
/// the undo history.
public final class ActionService {
    public typealias NextTurn = @MainActor () async -> Void

    private let clipboard: ClipboardAction
    private let airDrop: AirDropAction
    private let terminal: TerminalAction
    private let folders: any FolderChoosing
    private let survey: MoveSurvey
    private let executor: MoveExecutor
    private let undoHistory: UndoHistory
    private let box: (any BoxAdding)?
    private let terminalID: () -> String
    private let nextTurn: NextTurn

    public init(
        clipboard: ClipboardAction = ClipboardAction(), airDrop: AirDropAction = AirDropAction(),
        terminal: TerminalAction = TerminalAction(), folders: any FolderChoosing = MovePanel(),
        survey: MoveSurvey = MoveSurvey(), executor: MoveExecutor = MoveExecutor(), undoHistory: UndoHistory,
        box: (any BoxAdding)? = nil, terminalID: @escaping () -> String = { TerminalCatalog.standard.id },
        nextTurn: @escaping NextTurn = ActionService.runLoopTurn
    ) {
        self.clipboard = clipboard
        self.airDrop = airDrop
        self.terminal = terminal
        self.folders = folders
        self.survey = survey
        self.executor = executor
        self.undoHistory = undoHistory
        self.box = box
        self.terminalID = terminalID
        self.nextTurn = nextTurn
    }

    /// Validates `urls` at the boundary; a drop with nothing local is a card in the action's own words.
    public func perform(_ action: ActionID, urls: [URL], optionHeld: Bool) async -> ActionResult {
        do {
            return await perform(try ActionRequest(action: action, urls: urls, optionHeld: optionHeld))
        } catch {
            return ActionResult.failed(ActionCard(error)).listing(ActionRequest.screen(urls).rejected)
        }
    }

    public func perform(_ request: ActionRequest) async -> ActionResult {
        await run(request).listing(request.rejected)
    }

    private func run(_ request: ActionRequest) async -> ActionResult {
        switch request.action {
        case .copyTo: return ActionResult(clipboard.copyItems(request.items))
        case .copyFilePath: return ActionResult(clipboard.copyPaths(request.items, shellQuoted: request.optionHeld))
        case .shareAirDrop:
            await nextTurn()
            return ActionResult(await airDrop.send(request.items))
        case .openInTerminal:
            await nextTurn()
            return ActionResult(await terminal.open(request.items.map(survey.item), terminalID: terminalID()))
        case .moveTo: return await moveReporting(request.items).0
        case .pinFloating:
            guard let box else { return ActionResult(.failed(.boxUnavailable)) }
            return await box.add(request.items, newBox: request.optionHeld)
        }
    }

    /// Move to… for callers that need to know where each item went (the Drop Box updates its references): one run-loop
    /// turn, the folder chooser, the plan, the executor and one undo entry for the whole batch. The report is nil when
    /// nothing ran (the choice was cancelled or the plan refused).
    public func moveReporting(_ urls: [URL], progress: TransferProgress = .silent) async -> (ActionResult, MoveReport?) {
        await transfer(urls, .move, progress)
    }

    /// Copy to… (P2-142, D-M5b-13): as Move to…, but every item is copied and the originals stay; one undo entry puts
    /// the copies that are still unchanged in the Trash.
    public func copyReporting(_ urls: [URL], progress: TransferProgress = .silent) async -> (ActionResult, MoveReport?) {
        await transfer(urls, .copy, progress)
    }

    /// The chooser, the plan, then the executor; `progress` hears the count only once there is a plan, so nothing
    /// it shows can cover the chooser. Cancelling the caller's task stops the run between items.
    private func transfer(_ urls: [URL], _ mode: MovePlan.Mode, _ progress: TransferProgress) async -> (
        ActionResult, MoveReport?
    ) {
        await nextTurn()
        guard let folder = await folders.chooseFolder(for: urls.map(survey.item), mode: mode) else {
            return (.cancelled, nil)
        }
        let plan: MovePlan
        do {
            plan = try survey.plan(items: urls, destination: folder, mode: mode)
        } catch {
            return (.failed(ActionCard(title: error.userMessage)), nil)
        }
        progress.started(plan.steps.count)
        let report = await executor.run(plan, progress: progress.advanced)
        let undo = mode == .move ? await recordUndo(report.moved) : await recordUndo(copies: report.moved)
        return (Self.result(report, undo: undo, mode: mode), report)
    }

    /// Records the copies that could be stamped; nil when there is nothing to undo.
    private func recordUndo(copies: [MovedItem]) async -> BatchID? {
        let entries = copies.compactMap { item in item.stamp.map { UndoCopy(copy: item.target, stamp: $0) } }
        guard !entries.isEmpty else { return nil }
        let batch = BatchID()
        await undoHistory.record(batch, copies: entries)
        return batch
    }

    /// Records the moved items that could be stamped; nil when there is nothing to undo.
    private func recordUndo(_ moved: [MovedItem]) async -> BatchID? {
        let entries = moved.compactMap { item in
            item.stamp.map { UndoMove(original: item.source, moved: item.target, stamp: $0) }
        }
        guard !entries.isEmpty else { return nil }
        let batch = BatchID()
        await undoHistory.record(batch, moves: entries)
        return batch
    }

    static func result(_ report: MoveReport, undo: BatchID?, mode: MovePlan.Mode = .move) -> ActionResult {
        let lines = report.failures.map { $0.userMessage(for: mode) }
        let copying = mode == .copy
        guard report.cancelled.isEmpty else { return stopped(report, undo: undo, mode: mode, lines: lines) }
        guard !report.moved.isEmpty else {
            return lines.isEmpty && !copying
                ? .done(toast: "Already in that folder", undo: nil)
                : .failed(ActionCard(title: copying ? "Nothing was copied." : "Nothing was moved.", lines: lines))
        }
        let toast = (copying ? "Copied " : "Moved ") + counted(report.moved.count, "item")
        guard !lines.isEmpty else { return .done(toast: toast, undo: undo) }
        let title = copying ? "Some items weren't copied." : "Some items weren't moved."
        return .partial(toast: toast, card: ActionCard(title: title, lines: lines), undo: undo)
    }

    /// A run cancelled between items: what moved keeps its Undo and the card counts what did not. Nothing moved is
    /// silent, as a cancelled choice is, unless something failed on the way.
    private static func stopped(_ report: MoveReport, undo: BatchID?, mode: MovePlan.Mode, lines: [String])
        -> ActionResult
    {
        let copying = mode == .copy
        guard !report.moved.isEmpty else {
            guard !lines.isEmpty else { return .cancelled }
            return .failed(ActionCard(title: copying ? "Nothing was copied." : "Nothing was moved.", lines: lines))
        }
        let left = report.cancelled.count + report.failures.count
        let verb = (left == 1 ? " wasn't " : " weren't ") + (copying ? "copied." : "moved.")
        let toast = (copying ? "Copied " : "Moved ") + counted(report.moved.count, "item")
        let card = ActionCard(title: "Stopped. " + counted(left, "item") + verb, lines: lines)
        return .partial(toast: toast, card: card, undo: undo)
    }

    /// Resumes on the next pass of the main run loop.
    public static func runLoopTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
