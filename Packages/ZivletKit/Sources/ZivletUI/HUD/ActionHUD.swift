import AppKit
import SwiftUI
import ZivletActions
import ZivletCore

/// What the action HUD renders; replaced on every result.
@Observable
final class ActionHUDModel {
    private(set) var result: ActionResult?
    private(set) var undoMessage: String?
    private(set) var undoCanRetry = false
    /// Undo was pressed and its reply has not come back; a second press is ignored.
    private(set) var undoInFlight = false
    var showsDetail = false

    /// Undo is offered until it has answered, and again when the Trash refused something.
    var offersUndo: Bool { result?.undo != nil && !undoInFlight && (undoMessage == nil || undoCanRetry) }

    func present(_ result: ActionResult?) {
        self.result = result
        undoMessage = nil
        undoCanRetry = false
        undoInFlight = false
        showsDetail = false
    }

    func beginUndo() { undoInFlight = true }

    func finishUndo(_ reply: UndoReply) {
        undoMessage = reply.message
        undoCanRetry = reply.canRetry
        undoInFlight = false
    }
}

/// The action result panel (03b §7 "Success feedback", "Failure UI"): a toast that leaves after 1.5 s, or after 4 s
/// when it offers Undo (held while the pointer is over it); a card stays until closed. Non-activating, near the drop
/// point. Actions have this small panel of their own until results share the conversion HUD.
public final class ActionHUD: ActionPresenter {
    public static let width: CGFloat = 340
    static let toastLinger = Duration.milliseconds(1_500)
    static let undoLinger = Duration.seconds(4)

    /// Undoes a Move and returns the sentence to show in its place.
    public var onUndo: (BatchID) async -> UndoReply = { _ in UndoReply(message: "", canRetry: false) }
    public var onTextButton: (TextResultButton, TextOutcome) -> Void = { _, _ in }

    let model = ActionHUDModel()
    private let panel = HUDWindow(size: CGSize(width: ActionHUD.width, height: 60))
    private let hosting: NSHostingView<ActionHUDView>
    private var hideTask: Task<Void, Never>?
    private(set) var hovering = false
    private(set) var pendingUndo: Task<Void, Never>?
    /// What the working line's Cancel runs, while it is up.
    private var workingCancel: (() -> Void)?

    public init() {
        hosting = NSHostingView(rootView: ActionHUDView(model: model))
        hosting.rootView = ActionHUDView(
            model: model, undo: { [weak self] in self?.undo() }, details: { [weak self] in self?.showDetails() },
            close: { [weak self] in self?.hide() }, hover: { [weak self] in self?.hover($0) },
            text: { [weak self] in self?.pressText($0) }, cancel: { [weak self] in self?.cancelWorking() })
        panel.contentView = hosting
    }

    var hideIsScheduled: Bool { hideTask != nil }
    /// Where the panel is, for the DEBUG screenshots.
    public var panelFrame: CGRect { panel.frame }
    var canBecomeKey: Bool { panel.canBecomeKey }

    /// Shows `result` near `point`. A cancel shows nothing: it leaves a finished result alone and removes a working
    /// line, which would otherwise stay.
    public func show(_ result: ActionResult, near point: CGPoint?) {
        workingCancel = nil
        if case .cancelled = result {
            if model.result?.working != nil { hide() }
            return
        }
        model.present(result)
        hovering = false  // a new result starts unhovered; the next pointer move says otherwise
        resize(near: point)
        panel.orderFrontRegardless()
        scheduleHide()
    }

    /// The working line, its bar and Cancel; it stays until the result replaces it, and its height follows the line.
    public func showWorking(_ status: WorkingStatus, near point: CGPoint?, cancel: @escaping () -> Void) {
        let replacing = model.result?.working != nil
        model.present(.working(status))
        workingCancel = cancel
        cancelHide()
        if replacing { return refit() }
        hovering = false
        resize(near: point)
        panel.orderFrontRegardless()
    }

    /// Cancel (or Escape once the panel is key) on the working line: the job stops and the line goes at once.
    func cancelWorking() {
        guard model.result?.working != nil, let cancel = workingCancel else { return }
        hide()
        cancel()
    }

    /// Ordered out, the panel gets no exit event, so the hover flag is cleared here.
    public func hide() {
        cancelHide()
        workingCancel = nil
        hovering = false
        model.present(nil)
        panel.orderOut(nil)
    }

    func hover(_ inside: Bool) {
        hovering = inside
        if inside { cancelHide() } else { scheduleHide() }
    }

    /// A text card button: the app copies, saves or shows the text; the card stays for its linger.
    func pressText(_ button: TextResultButton) {
        guard let outcome = model.result?.text else { return }
        onTextButton(button, outcome)
        scheduleHide()
    }

    func undo() {
        guard let batch = model.result?.undo, model.offersUndo else { return }
        cancelHide()
        model.beginUndo()
        pendingUndo = Task { [weak self, onUndo] in
            let reply = await onUndo(batch)
            guard let self, self.model.result?.undo == batch else { return }
            self.model.finishUndo(reply)
            self.refit()
            self.scheduleHide()
        }
    }

    private func showDetails() {
        model.showsDetail = true
        refit()
    }

    private func resize(near point: CGPoint?) {
        let size = NSSize(width: Self.width, height: fittingHeight())
        panel.setContentSize(size)
        if let origin = HUDLayout.origin(near: point, size: size) { panel.setFrameOrigin(origin) }
    }

    /// Grows or shrinks to the content, keeping the top edge where it is.
    private func refit() {
        let height = fittingHeight()
        let frame = panel.frame
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: Self.width, height: height), display: true)
    }

    /// The height of the current content: SwiftUI lays out the new model first.
    private func fittingHeight() -> CGFloat {
        hosting.layoutSubtreeIfNeeded()
        return hosting.fittingSize.height
    }

    /// Toasts leave on their own; cards, and toasts while hovered, stay.
    private func scheduleHide() {
        cancelHide()
        guard let result = model.result, result.card == nil, result.working == nil, !hovering, !model.undoInFlight
        else { return }
        let linger = Self.linger(for: result)
        hideTask = Task { [weak self] in
            do {
                try await Task.sleep(for: linger)
            } catch {
                return  // replaced, hovered or closed meanwhile
            }
            self?.hide()
        }
    }

    /// The result's own linger (Clear's 10 s undo window), else 1.5 s, or 4 s with Undo.
    static func linger(for result: ActionResult) -> Duration {
        result.linger ?? (result.undo == nil ? toastLinger : undoLinger)
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }
}
