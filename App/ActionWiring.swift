import AppKit
import ZivletActions
import ZivletCore
import ZivletRuntime
import ZivletUI
import os

/// Wires a drop on an action petal to `ActionService` and its result to the action HUD (P1-44, P1-45). Float stays
/// hidden until its shelf exists (D-M4-13). The terminal is the one chosen in Settings.
final class ActionWiring {
    static let unavailableActions: Set<ActionID> = [.pinFloating]

    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "actions")
    private let service: ActionService
    private let hud = ActionHUD()
    /// After every action (a Move adds to the undo history).
    var onFinished: () -> Void = {}

    init(
        undoHistory: UndoHistory, terminalID: @escaping () -> String, undo: @escaping (BatchID) async -> UndoReply
    ) {
        service = ActionService(undoHistory: undoHistory, terminalID: terminalID)
        hud.onUndo = undo
    }

    /// Runs the action and shows its result near `point`; the task's value is the result (for the DEBUG demo).
    @discardableResult
    func run(_ action: ActionID, urls: [URL], optionHeld: Bool, near point: CGPoint?) -> Task<ActionResult, Never> {
        Task { [service, hud, logger, onFinished] in
            let result = await service.perform(action, urls: urls, optionHeld: optionHeld)
            hud.show(result, near: point)
            Self.log(result, action: action, logger: logger)
            onFinished()
            return result
        }
    }

    /// A sentence from elsewhere (an undo from the status menu) as a toast at the centre of the main screen.
    func announce(_ message: String) {
        hud.show(.done(toast: message, undo: nil), near: nil)
    }

    /// Toasts hold counts and app names only, so they are public; card titles may name files, so they are private.
    private static func log(_ result: ActionResult, action: ActionID, logger: Logger) {
        let kind: String
        switch result {
        case .done: kind = "done"
        case .partial: kind = "partial"
        case .failed: kind = "failed"
        case .cancelled: kind = "cancelled"
        }
        logger.notice(
            "Action finished: \(action.rawValue, privacy: .public) \(kind, privacy: .public): \(result.toast ?? "", privacy: .public)"
        )
        if let card = result.card {
            logger.notice("Action card: \(card.title, privacy: .private) \(card.lines.count) lines")
        }
    }
}
