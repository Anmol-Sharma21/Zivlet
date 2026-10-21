import Foundation
import ZivletCore
import ZivletRuntime

/// One entry point for the five Phase 1 actions (P1-44, P1-45): validates the drop, runs the action and turns its
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
    private let terminalID: () -> String
    private let nextTurn: NextTurn

    public init(
        clipboard: ClipboardAction = ClipboardAction(), airDrop: AirDropAction = AirDropAction(),
        terminal: TerminalAction = TerminalAction(), folders: any FolderChoosing = MovePanel(),
        survey: MoveSurvey = MoveSurvey(), executor: MoveExecutor = MoveExecutor(), undoHistory: UndoHistory,
        terminalID: @escaping () -> String = { TerminalCatalog.standard.id },
        nextTurn: @escaping NextTurn = ActionService.runLoopTurn
    ) {
        self.clipboard = clipboard
        self.airDrop = airDrop
        self.terminal = terminal
        self.folders = folders
        self.survey = survey
        self.executor = executor
        self.undoHistory = undoHistory
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
        case .moveTo:
            await nextTurn()
            return await move(request.items)
        case .pinFloating: return ActionResult(.failed(.floatNotYetAvailable))
        }
    }

    private func move(_ urls: [URL]) async -> ActionResult {
        guard let folder = await folders.chooseFolder(for: urls.map(survey.item)) else { return .cancelled }
        let plan: MovePlan
        do {
            plan = try survey.plan(items: urls, destination: folder)
        } catch {
            return .failed(ActionCard(title: error.userMessage))
        }
        let report = await executor.run(plan)
        return Self.result(report, undo: await recordUndo(report.moved))
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

    static func result(_ report: MoveReport, undo: BatchID?) -> ActionResult {
        let lines = report.failures.map(\.userMessage)
        guard !report.moved.isEmpty else {
            return lines.isEmpty
                ? .done(toast: "Already in that folder", undo: nil)
                : .failed(ActionCard(title: "Nothing was moved.", lines: lines))
        }
        let toast = "Moved " + counted(report.moved.count, "item")
        guard !lines.isEmpty else { return .done(toast: toast, undo: undo) }
        return .partial(toast: toast, card: ActionCard(title: "Some items weren't moved.", lines: lines), undo: undo)
    }

    /// Resumes on the next pass of the main run loop.
    public static func runLoopTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
