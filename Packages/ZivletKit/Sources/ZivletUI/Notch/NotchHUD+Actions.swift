import Foundation
import SwiftUI
import ZivletActions
import ZivletCore
import ZivletNotch
import ZivletNotchCore
import ZivletRuntime

// The island's client side: a view per surface, the accessibility text and the island's notices.
extension NotchHUD: IslandClient {
    public func content(for surface: IslandSurface, display: UInt32) -> AnyView {
        let act: (Press, NotchHUDItemID) -> Void = { [weak self] press, id in self?.press(press, onItem: id) }
        switch surface {
        case .hidden, .dropTarget, .sensor: return AnyView(EmptyView())  // the HUD never asks for the tray's surfaces
        case .collapsed: return AnyView(NotchTab(model: model, display: display, underHousing: hasHousing(display)))
        case .toast: return AnyView(NotchToast(model: model, display: display, act: act))
        case .expanded:
            let drag: (Bool) -> Void = { [weak self] began in self?.dragChanged(began, display: display) }
            return AnyView(
                NotchExpanded(
                    model: model, display: display, underHousing: hasHousing(display), drag: drag, act: act))
        }
    }

    public func accessibilityLabel(display: UInt32) -> String { NotchHUDCopy.islandLabel }

    public func accessibilityValue(display: UInt32) -> String { board.accessibilityValue(on: display) }

    public var accessibilityActionName: String { NotchHUDCopy.showAction }

    public func accessibilityActionPerformed(display: UInt32) { hosts?.expandRequested(on: display) }

    public func held(_ held: Bool, display: UInt32, now: Duration) {
        apply(board.holding(held, display: display, now: now))
    }

    /// The island opens or closes: an open card follows its own percent and time left (19b §6.2).
    public func surfaceChanged(_ surface: IslandSurface, display: UInt32) {
        apply(board.showing(surface, on: display, now: clock.now()))
    }

    /// Escape on a closable card: everything on that display goes.
    public func closeRequested(display: UInt32) {
        for item in board.items[display] ?? [] {
            undos.removeValue(forKey: item.id)?.cancel()
            forget(item.id)
        }
        apply(board.closingAll(on: display))
    }

    public func displaysChanged(_ ids: [UInt32], replacing: [UInt32: UInt32]) {
        let moved = replacing.keys.sorted().reduce(board) { next, removed in
            next.movingItems(from: removed, to: replacing[removed] ?? removed)
        }
        apply(moved)
    }
}

// Presses: the same closures `ResultHUD` and `ActionHUD` call, each on its own item.
extension NotchHUD {
    public func press(_ press: Press, on batch: BatchID) { self.press(press, onItem: .batch(batch)) }

    func press(_ press: Press, onItem id: NotchHUDItemID) {
        switch id {
        case .batch(let batch): pressBatch(press, batch)
        case .action(let index): pressAction(press, id: id, index: index)
        }
    }

    private func pressBatch(_ press: Press, _ batch: BatchID) {
        let id = NotchHUDItemID.batch(batch)
        let saved = board.item(id)?.snapshot?.outputs.map(\.url) ?? []
        let outputs = card(batch)?.remaining(saved) ?? saved
        switch press {
        case .cancel: onCancel(batch)
        case .undo: undoBatch(batch)
        case .reveal: onReveal(outputs)
        case .open: onOpen(outputs)
        case .copy: onCopy(outputs)
        case .showDetails: showDetails(batch)
        case .retry:
            let anchor = anchors[batch]
            close(id)
            onRetry(batch, anchor)
        case .close: close(id)
        }
    }

    private func pressAction(_ press: Press, id: NotchHUDItemID, index: Int) {
        switch press {
        case .undo: undoAction(id, index: index)
        case .showDetails:
            model.actions[index]?.showsDetail = true
            contentChanged(id)
        case .close: close(id)
        case .cancel, .reveal, .open, .copy, .retry: break
        }
    }

    private func showDetails(_ batch: BatchID) {
        card(batch)?.showsDetails = true
        contentChanged(.batch(batch))
    }

    /// Undo once: a press while the reply is pending is ignored; the linger waits for the reply, then starts again.
    private func undoBatch(_ batch: BatchID) {
        let id = NotchHUDItemID.batch(batch)
        guard let card = card(batch), !card.undoInFlight else { return }
        card.undoInFlight = true
        apply(board.pausing(id))
        undos[id] = Task { [weak self, onUndo] in
            let reply = await onUndo(batch)
            guard let self else { return }
            self.undos[id] = nil
            guard let card = self.card(batch) else { return }
            card.undoMessage = reply.message
            card.undoCanRetry = reply.canRetry
            card.remove(reply.removed)
            card.undoInFlight = false
            self.contentChanged(id)
            if !reply.canRetry { self.apply(self.board.restarting(id, now: self.clock.now())) }
        }
    }

    private func undoAction(_ id: NotchHUDItemID, index: Int) {
        guard let action = model.actions[index], let batch = action.result?.undo, action.offersUndo else { return }
        action.beginUndo()
        apply(board.pausing(id))
        undos[id] = Task { [weak self, onUndo] in
            let reply = await onUndo(batch)
            guard let self else { return }
            self.undos[id] = nil
            guard let action = self.model.actions[index] else { return }
            action.finishUndo(reply)
            self.contentChanged(id)
            self.apply(self.board.restarting(id, now: self.clock.now()))
        }
    }

    private func contentChanged(_ id: NotchHUDItemID) {
        if let display = board.display(of: id) { hosts?.contentChanged(on: display) }
    }
}

// Test seams: what an item offers and whether its undo is on its way.
extension NotchHUD {
    func card(_ batch: BatchID) -> CardState? { model.cards[batch] }
    func pendingUndo(_ id: NotchHUDItemID) -> Task<Void, Never>? { undos[id] }

    func actionModel(_ id: NotchHUDItemID) -> ActionHUDModel? {
        guard case .action(let index) = id else { return nil }
        return model.actions[index]
    }
}
