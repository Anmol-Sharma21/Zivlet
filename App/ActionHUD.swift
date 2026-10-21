import AppKit
import SwiftUI
import ZivletActions
import ZivletCore

/// What the action HUD renders; replaced on every result.
@Observable
final class ActionHUDModel {
    var result: ActionResult?
    var undoMessage: String?
    var undoCanRetry = false
    var showsDetail = false
}

/// The action result panel (03b §7 "Success feedback", "Failure UI"): a toast that leaves after 1.5 s, or after 4 s
/// when it offers Undo (held while the pointer is over it); a card stays until closed. Non-activating, near the drop
/// point. Stream D moves results into the shared HUD; until then actions have this small panel of their own.
final class ActionHUD {
    static let width: CGFloat = 340
    static let toastLinger = Duration.milliseconds(1_500)
    static let undoLinger = Duration.seconds(4)

    /// Undoes a Move and returns the sentence to show in its place.
    var onUndo: (BatchID) async -> UndoReply = { _ in UndoReply(message: "", canRetry: false) }

    private let model = ActionHUDModel()
    private let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: ActionHUD.width, height: 60),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let hosting: NSHostingView<ActionHUDView>
    private var hideTask: Task<Void, Never>?
    private var hovering = false

    init() {
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hosting = NSHostingView(rootView: ActionHUDView(model: model))
        hosting.rootView = ActionHUDView(
            model: model, undo: { [weak self] in self?.undo() }, details: { [weak self] in self?.showDetails() },
            close: { [weak self] in self?.hide() }, hover: { [weak self] in self?.hover($0) })
        panel.contentView = hosting
    }

    /// Shows `result` near `point`; a cancel shows nothing and leaves the current result alone.
    func show(_ result: ActionResult, near point: CGPoint?) {
        if case .cancelled = result { return }
        model.result = result
        model.undoMessage = nil
        model.undoCanRetry = false
        model.showsDetail = false
        resize(near: point)
        panel.orderFrontRegardless()
        scheduleHide()
    }

    func hide() {
        hideTask?.cancel()
        model.result = nil
        panel.orderOut(nil)
    }

    private func resize(near point: CGPoint?) {
        let height = hosting.fittingSize.height
        let size = NSSize(width: Self.width, height: height)
        panel.setContentSize(size)
        if let origin = HUDPlacement.origin(near: point, size: size) { panel.setFrameOrigin(origin) }
    }

    /// Toasts leave on their own; cards, and toasts while hovered, stay.
    private func scheduleHide() {
        hideTask?.cancel()
        guard let result = model.result, result.card == nil, !hovering else { return }
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

    private func hover(_ inside: Bool) {
        hovering = inside
        if inside { hideTask?.cancel() } else { scheduleHide() }
    }

    private func showDetails() {
        model.showsDetail = true
        refit()
    }

    /// Grows or shrinks to the content, keeping the top edge where it is.
    private func refit() {
        let height = hosting.fittingSize.height
        let frame = panel.frame
        panel.setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: Self.width, height: height), display: true)
    }

    private func undo() {
        guard let batch = model.result?.undo else { return }
        hideTask?.cancel()
        Task { [weak self, onUndo] in
            let reply = await onUndo(batch)
            guard let self, self.model.result?.undo == batch else { return }
            self.model.undoMessage = reply.message
            self.model.undoCanRetry = reply.canRetry
            self.refit()
            self.scheduleHide()
        }
    }
}

struct ActionHUDView: View {
    static let maxLines = 5

    let model: ActionHUDModel
    var undo: () -> Void = {}
    var details: () -> Void = {}
    var close: () -> Void = {}
    var hover: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let result = model.result {
                if let toast = result.toast { Text(toast).font(.headline).lineLimit(1) }
                if let card = result.card { cardView(card, isAlone: result.toast == nil) }
                if let message = model.undoMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                buttons(result)
            }
        }
        .padding(14)
        .frame(width: ActionHUD.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .onHover(perform: hover)
    }

    private func cardView(_ card: ActionCard, isAlone: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.title).font(isAlone ? .headline : .callout).lineLimit(3)
            ForEach(Array(card.lines.prefix(Self.maxLines).enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if card.lines.count > Self.maxLines {
                Text("and \(card.lines.count - Self.maxLines) more").font(.caption).foregroundStyle(.secondary)
            }
            if model.showsDetail, let detail = card.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private func buttons(_ result: ActionResult) -> some View {
        HStack {
            Spacer()
            if result.undo != nil, model.undoMessage == nil || model.undoCanRetry { Button("Undo", action: undo) }
            if result.card?.detail != nil, !model.showsDetail { Button("Show details", action: details) }
            if result.card != nil { Button("Close", action: close).keyboardShortcut(.cancelAction) }
        }
        .controlSize(.small)
    }
}
