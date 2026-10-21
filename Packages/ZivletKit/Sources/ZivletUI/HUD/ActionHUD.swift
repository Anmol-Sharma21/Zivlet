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
public final class ActionHUD {
    public static let width: CGFloat = 340
    static let toastLinger = Duration.milliseconds(1_500)
    static let undoLinger = Duration.seconds(4)

    /// Undoes a Move and returns the sentence to show in its place.
    public var onUndo: (BatchID) async -> UndoReply = { _ in UndoReply(message: "", canRetry: false) }

    let model = ActionHUDModel()
    private let panel = HUDWindow(size: CGSize(width: ActionHUD.width, height: 60))
    private let hosting: NSHostingView<ActionHUDView>
    private var hideTask: Task<Void, Never>?
    private(set) var hovering = false
    private(set) var pendingUndo: Task<Void, Never>?

    public init() {
        hosting = NSHostingView(rootView: ActionHUDView(model: model))
        hosting.rootView = ActionHUDView(
            model: model, undo: { [weak self] in self?.undo() }, details: { [weak self] in self?.showDetails() },
            close: { [weak self] in self?.hide() }, hover: { [weak self] in self?.hover($0) })
        panel.contentView = hosting
    }

    var hideIsScheduled: Bool { hideTask != nil }
    var canBecomeKey: Bool { panel.canBecomeKey }

    /// Shows `result` near `point`; a cancel shows nothing and leaves the current result alone.
    public func show(_ result: ActionResult, near point: CGPoint?) {
        if case .cancelled = result { return }
        model.present(result)
        hovering = false  // a new result starts unhovered; the next pointer move says otherwise
        resize(near: point)
        panel.orderFrontRegardless()
        scheduleHide()
    }

    /// Ordered out, the panel gets no exit event, so the hover flag is cleared here.
    public func hide() {
        cancelHide()
        hovering = false
        model.present(nil)
        panel.orderOut(nil)
    }

    func hover(_ inside: Bool) {
        hovering = inside
        if inside { cancelHide() } else { scheduleHide() }
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
        guard let result = model.result, result.card == nil, !hovering, !model.undoInFlight else { return }
        let linger = result.undo == nil ? Self.toastLinger : Self.undoLinger
        hideTask = Task { [weak self] in
            do {
                try await Task.sleep(for: linger)
            } catch {
                return  // replaced, hovered or closed meanwhile
            }
            self?.hide()
        }
    }

    private func cancelHide() {
        hideTask?.cancel()
        hideTask = nil
    }
}
