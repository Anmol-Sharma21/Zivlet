import AppKit
import ZivletActions
import ZivletCore
import ZivletRuntime
import ZivletUI
import os

/// Wires a drop on an action petal to `ActionService` and its result to the action HUD or the notch island, by the
/// placement at the time of the drop (P1-44, P1-45, D-M5a-3). The BOX slice adds to the Drop Box (P2-55 §9.5), so no
/// action is hidden any more. The terminal is the one chosen in Settings.
final class ActionWiring {
    static let unavailableActions: Set<ActionID> = []

    private let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "actions")
    private let service: ActionService
    private let hud = ActionHUD()
    private let notch: NotchHUD
    private let route: () -> HUDRoute
    /// After every action (a Move adds to the undo history).
    var onFinished: () -> Void = {}

    init(
        undoHistory: UndoHistory, notch: NotchHUD, route: @escaping () -> HUDRoute, box: any BoxAdding,
        terminalID: @escaping () -> String, undo: @escaping (BatchID) async -> UndoReply
    ) {
        service = ActionService(undoHistory: undoHistory, box: box, terminalID: terminalID)
        self.notch = notch
        self.route = route
        hud.onUndo = undo
    }

    /// The presenter for `route`; the notch HUD's undo closure is set by the conversion wiring. The island without a
    /// display hands the result to the card near the drop.
    private func presenter(_ route: HUDRoute) -> any ActionPresenter {
        route.usable(islandHasDisplay: notch.canShow) == .notch ? notch : hud
    }

    private var presenter: any ActionPresenter { presenter(route()) }

    /// Runs the action and shows its result near `point`, where the placement at the drop says; the task's value is
    /// the result (for the DEBUG demo).
    @discardableResult
    func run(_ action: ActionID, urls: [URL], optionHeld: Bool, near point: CGPoint?) -> Task<ActionResult, Never> {
        let route = self.route()
        return Task { [service, logger, onFinished] in
            let result = await service.perform(action, urls: urls, optionHeld: optionHeld)
            self.presenter(route).show(result, near: point)
            Self.log(result, action: action, logger: logger)
            onFinished()
            return result
        }
    }

    /// A sentence from elsewhere (an undo from the status menu, no drop) as a toast where the placement says: the
    /// centre of the main screen or the menu-bar display's island.
    func announce(_ message: String) {
        presenter.show(.done(toast: message, undo: nil), near: nil)
    }

    /// A result from elsewhere (a drop on the Drop Box panel), where the placement says.
    func present(_ result: ActionResult, near point: CGPoint?) {
        presenter.show(result, near: point)
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
